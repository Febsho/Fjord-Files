package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"github.com/duxlabs-dev/dux-files/core/internal/wire"
	"github.com/duxlabs-dev/dux-go/ipc/params"
)

const sweepOutputLimit = 4 << 20

var sweepScanSlots = make(chan struct{}, 2)
var sweepScans = struct {
	sync.Mutex
	cancel map[string]context.CancelFunc
}{cancel: make(map[string]context.CancelFunc)}

func managedSweepScan(ctx context.Context, path, id string) (*sweepPlan, error) {
	if id == "" || len(id) > 96 {
		return nil, fmt.Errorf("invalid scan ID")
	}
	ctx, cancel := context.WithCancel(ctx)
	sweepScans.Lock()
	if len(sweepScans.cancel) >= 32 {
		sweepScans.Unlock()
		cancel()
		return nil, fmt.Errorf("too many pending Sweep scans")
	}
	if _, exists := sweepScans.cancel[id]; exists {
		sweepScans.Unlock()
		cancel()
		return nil, fmt.Errorf("scan ID already in use")
	}
	sweepScans.cancel[id] = cancel
	sweepScans.Unlock()
	defer func() {
		sweepScans.Lock()
		delete(sweepScans.cancel, id)
		sweepScans.Unlock()
		cancel()
	}()
	return scanSweep(ctx, path)
}

func cancelSweepScan(id string) bool {
	sweepScans.Lock()
	defer sweepScans.Unlock()
	cancel, ok := sweepScans.cancel[id]
	if ok {
		cancel()
	}
	return ok
}

type sweepCandidate struct {
	ID              string   `json:"id"`
	Path            string   `json:"path"`
	Kind            string   `json:"kind,omitempty"`
	ProjectRoot     string   `json:"projectRoot,omitempty"`
	ProjectActiveMs *int64   `json:"projectActiveMs,omitempty"`
	ModifiedMs      *int64   `json:"modifiedMs,omitempty"`
	EstimatedBytes  int64    `json:"estimatedBytes"`
	BytesKnown      *bool    `json:"bytesKnown,omitempty"`
	RiskTier        string   `json:"riskTier"`
	Reasons         []string `json:"reasons"`
}

type sweepPlan struct {
	Token           string           `json:"token,omitempty"`
	ProtocolVersion string           `json:"protocolVersion"`
	TargetDir       string           `json:"targetDir"`
	Candidates      []sweepCandidate `json:"candidates"`
	Summary         struct {
		CandidateCount      int   `json:"candidateCount"`
		EstimatedTotalBytes int64 `json:"estimatedTotalBytes"`
		SkippedDirs         int   `json:"skippedDirs"`
		Exact               bool  `json:"exact"`
	} `json:"summary"`
}

type limitedBuffer struct{ bytes.Buffer }

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if len(p) > sweepOutputLimit-b.Len() {
		return 0, fmt.Errorf("sweep output exceeded limit")
	}
	return b.Buffer.Write(p)
}

func scanSweep(ctx context.Context, path string) (*sweepPlan, error) {
	select {
	case sweepScanSlots <- struct{}{}:
		defer func() { <-sweepScanSlots }()
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	if !filepath.IsAbs(path) {
		return nil, fmt.Errorf("path must be an absolute directory")
	}
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("path must be a directory")
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	binary, digest, err := sweepExecutable()
	if err != nil {
		return nil, err
	}
	cmd := exec.CommandContext(ctx, binary, "--json", "scan", "--", path)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		if errors.Is(err, syscall.ESRCH) {
			return os.ErrProcessDone
		}
		return err
	}
	var output, stderr limitedBuffer
	cmd.Stdout, cmd.Stderr = &output, &stderr
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("sweep scan: %w", ctx.Err())
		}
		return nil, fmt.Errorf("sweep scan failed: %w: %s", err, stderr.String())
	}
	if err := ctx.Err(); err != nil {
		return nil, fmt.Errorf("sweep scan: %w", err)
	}
	var plan sweepPlan
	if err := json.Unmarshal(output.Bytes(), &plan); err != nil {
		return nil, fmt.Errorf("invalid sweep scan output: %w", err)
	}
	if plan.ProtocolVersion != "1" || plan.Candidates == nil || plan.Summary.CandidateCount != len(plan.Candidates) {
		return nil, fmt.Errorf("unsupported or incomplete sweep scan output")
	}
	plan.Token, err = storeSweep(sweepSession{raw: append([]byte(nil), output.Bytes()...), plan: plan, binary: binary, digest: digest})
	if err != nil {
		return nil, err
	}
	return &plan, nil
}

func HandleSweep(ctx context.Context, w *ConnWriter, req Request) {
	var result any
	var err error
	switch req.Method {
	case "sweep.scan":
		id := params.StringOpt(req.Params, "scanId", "")
		if id == "" {
			result, err = scanSweep(ctx, params.StringOpt(req.Params, "path", ""))
		} else {
			result, err = managedSweepScan(ctx, params.StringOpt(req.Params, "path", ""), id)
		}
	case "sweep.history":
		result, err = readSweepHistory(ctx)
	case "sweep.cancel":
		result = map[string]bool{"cancelled": cancelSweepScan(params.StringOpt(req.Params, "scanId", ""))}
	case "sweep.discard":
		discardSweep(params.StringOpt(req.Params, "token", ""))
		result = map[string]bool{"discarded": true}
	case "sweep.prepare":
		result, err = prepareSweep(ctx, params.StringOpt(req.Params, "token", ""), wire.StringList(req.Params, "ids"))
	case "sweep.apply":
		if !params.BoolLoose(req.Params, "confirmed") {
			err = fmt.Errorf("explicit confirmation required")
		} else {
			result, err = applySweep(ctx, params.StringOpt(req.Params, "token", ""))
		}
	default:
		err = fmt.Errorf("unknown sweep method: %s", req.Method)
	}
	if err != nil {
		wire.RespondError(w, req.ID, err)
		return
	}
	w.Respond(req.ID, result)
}
