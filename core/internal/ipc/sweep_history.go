package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"time"
)

type sweepHistoryEntry struct {
	Timestamp   string `json:"ts"`
	TargetDir   string `json:"targetDir"`
	Deleted     *int   `json:"deleted"`
	BytesFreed  *int64 `json:"bytesFreed"`
	Failed      *int   `json:"failed"`
	Interrupted *bool  `json:"interrupted"`
	TrashDir    string `json:"trashDir,omitempty"`
}

type sweepHistory struct {
	Scope     string              `json:"scope"`
	ByteBasis string              `json:"byteBasis"`
	Recent    []sweepHistoryEntry `json:"recent"`
}

func readSweepHistory(ctx context.Context) (sweepHistory, error) {
	var history sweepHistory
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	select {
	case sweepScanSlots <- struct{}{}:
		defer func() { <-sweepScanSlots }()
	case <-ctx.Done():
		return history, ctx.Err()
	}
	binary, err := exec.LookPath("sweep")
	if err != nil {
		return history, err
	}
	cmd := exec.CommandContext(ctx, binary, "--json", "stats")
	var out, stderr limitedBuffer
	cmd.Stdout, cmd.Stderr = &out, &stderr
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return history, ctx.Err()
		}
		return history, fmt.Errorf("sweep history failed: %w: %s", err, stderr.String())
	}
	if err := json.Unmarshal(out.Bytes(), &history); err != nil {
		return history, fmt.Errorf("invalid Sweep history: %w", err)
	}
	if history.Scope != "retained-history" || history.ByteBasis != "plan-estimate" || history.Recent == nil || len(history.Recent) > 5 {
		return history, errors.New("unsupported or incomplete Sweep history")
	}
	for _, item := range history.Recent {
		if item.Timestamp == "" || item.TargetDir == "" || item.Deleted == nil || item.Failed == nil || item.BytesFreed == nil || item.Interrupted == nil || *item.Deleted < 0 || *item.Failed < 0 || *item.BytesFreed < 0 {
			return sweepHistory{}, errors.New("invalid Sweep history entry")
		}
	}
	return history, nil
}
