package ipc

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type sweepSession struct {
	raw      []byte
	plan     sweepPlan
	binary   string
	digest   [32]byte
	expires  time.Time
	prepared bool
}

var sweepSessions = struct {
	sync.Mutex
	entries map[string]sweepSession
}{entries: make(map[string]sweepSession)}

func sweepExecutable() (string, [32]byte, error) {
	var zero [32]byte
	p, err := exec.LookPath("sweep")
	if err != nil {
		return "", zero, err
	}
	p, err = filepath.Abs(p)
	if err != nil {
		return "", zero, err
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return "", zero, err
	}
	return p, sha256.Sum256(b), nil
}
func storeSweep(s sweepSession) (string, error) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	token := hex.EncodeToString(b[:])
	sweepSessions.Lock()
	defer sweepSessions.Unlock()
	now := time.Now()
	for k, v := range sweepSessions.entries {
		if now.After(v.expires) {
			delete(sweepSessions.entries, k)
		}
	}
	if len(sweepSessions.entries) >= 8 {
		return "", fmt.Errorf("too many pending Sweep plans")
	}
	s.expires = now.Add(10 * time.Minute)
	sweepSessions.entries[token] = s
	return token, nil
}
func discardSweep(token string) {
	sweepSessions.Lock()
	defer sweepSessions.Unlock()
	delete(sweepSessions.entries, token)
}

func takeSweep(token string, prepared bool) (sweepSession, error) {
	sweepSessions.Lock()
	defer sweepSessions.Unlock()
	s, ok := sweepSessions.entries[token]
	if !ok || time.Now().After(s.expires) || s.prepared != prepared {
		return sweepSession{}, fmt.Errorf("sweep plan is invalid or expired; scan again")
	}
	delete(sweepSessions.entries, token)
	return s, nil
}
func checkSweepExecutable(s sweepSession) error {
	b, err := os.ReadFile(s.binary)
	if err != nil {
		return err
	}
	if sha256.Sum256(b) != s.digest {
		return fmt.Errorf("sweep executable changed; scan again")
	}
	return nil
}
func runSweepPlan(ctx context.Context, s sweepSession, dry bool) ([]byte, error) {
	dir, err := os.MkdirTemp("", "fjord-sweep-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(dir)
	path := filepath.Join(dir, "plan.json")
	if err = os.WriteFile(path, s.raw, 0600); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()
	args := []string{"--yes", "apply", "--plan", path, "--json", "--trash"}
	if dry {
		args = append(args, "--dry-run")
	}
	cmd := exec.CommandContext(ctx, s.binary, args...)
	var stdout, stderr limitedBuffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err = cmd.Run()
	if err != nil {
		return stdout.Bytes(), fmt.Errorf("sweep failed: %w: %s", err, stderr.String())
	}
	return stdout.Bytes(), nil
}
func prepareSweep(ctx context.Context, token string, ids []string) (*sweepPlan, error) {
	s, err := takeSweep(token, false)
	if err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		return nil, fmt.Errorf("select at least one candidate")
	}
	if err = checkSweepExecutable(s); err != nil {
		return nil, err
	}
	candidates := make(map[string]sweepCandidate)
	for _, c := range s.plan.Candidates {
		if !filepath.IsAbs(c.Path) || filepath.Clean(c.Path) != c.Path || !filepath.IsAbs(s.plan.TargetDir) {
			return nil, fmt.Errorf("invalid Sweep candidate path")
		}
		if c.ID == "" {
			return nil, fmt.Errorf("missing candidate ID")
		}
		if _, ok := candidates[c.ID]; ok {
			return nil, fmt.Errorf("duplicate candidate ID")
		}
		candidates[c.ID] = c
	}
	seen := make(map[string]bool)
	selected := make([]sweepCandidate, 0, len(ids))
	for _, id := range ids {
		c, ok := candidates[id]
		if !ok || seen[id] || (c.RiskTier != "safe" && c.RiskTier != "caution") {
			return nil, fmt.Errorf("invalid or disallowed Sweep selection")
		}
		seen[id] = true
		selected = append(selected, c)
	}
	for _, chosen := range selected {
		for _, other := range s.plan.Candidates {
			if !seen[other.ID] && strings.HasPrefix(filepath.Clean(other.Path), filepath.Clean(chosen.Path)+string(os.PathSeparator)) {
				return nil, fmt.Errorf("selected directory contains an unselected candidate")
			}
		}
	}
	var raw map[string]json.RawMessage
	if err = json.Unmarshal(s.raw, &raw); err != nil {
		return nil, err
	}
	raw["selectedCandidateIds"], err = json.Marshal(ids)
	if err != nil {
		return nil, err
	}
	var summary map[string]json.RawMessage
	if err = json.Unmarshal(raw["summary"], &summary); err != nil {
		return nil, err
	}
	if summary == nil {
		return nil, fmt.Errorf("missing Sweep summary")
	}
	summary["selectedCount"], _ = json.Marshal(len(ids))
	raw["summary"], err = json.Marshal(summary)
	if err != nil {
		return nil, err
	}
	s.raw, err = json.Marshal(raw)
	if err != nil {
		return nil, err
	}
	if _, err = runSweepPlan(ctx, s, true); err != nil {
		return nil, fmt.Errorf("sweep preview failed: %w", err)
	}
	s.prepared = true
	s.plan.Candidates = selected
	s.plan.Summary.CandidateCount = len(selected)
	s.plan.Token, err = storeSweep(s)
	if err != nil {
		return nil, err
	}
	return &s.plan, nil
}
func applySweep(ctx context.Context, token string) (json.RawMessage, error) {
	s, err := takeSweep(token, true)
	if err != nil {
		return nil, err
	}
	if err = checkSweepExecutable(s); err != nil {
		return nil, err
	}
	output, runErr := runSweepPlan(ctx, s, false)
	var report struct {
		ProtocolVersion string            `json:"protocolVersion"`
		TargetDir       string            `json:"targetDir"`
		DeletedCount    *int              `json:"deletedCount"`
		FailedCount     *int              `json:"failedCount"`
		SelectedIDs     []string          `json:"selectedCandidateIds"`
		TrashMoves      []json.RawMessage `json:"trashMoves"`
	}
	if json.Unmarshal(output, &report) != nil || report.ProtocolVersion != "1" || report.TargetDir != s.plan.TargetDir || report.DeletedCount == nil || report.FailedCount == nil {
		return nil, fmt.Errorf("sweep returned no complete report; outcome may be unknown: %v", runErr)
	}
	if len(report.SelectedIDs) != len(s.plan.Candidates) || *report.DeletedCount < 0 || *report.FailedCount < 0 || (*report.DeletedCount > 0 && len(report.TrashMoves) != *report.DeletedCount) {
		return nil, fmt.Errorf("sweep returned an inconsistent report; outcome may be unknown")
	}
	expected := make(map[string]bool, len(s.plan.Candidates))
	for _, c := range s.plan.Candidates {
		expected[c.ID] = true
	}
	for _, id := range report.SelectedIDs {
		if !expected[id] {
			return nil, fmt.Errorf("sweep returned an inconsistent selection; outcome may be unknown")
		}
		delete(expected, id)
	}
	return json.RawMessage(output), nil
}
