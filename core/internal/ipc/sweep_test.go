package ipc

import (
	"context"
	"crypto/sha256"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestScanSweep(t *testing.T) {
	bin := t.TempDir()
	t.Setenv("PATH", bin)
	log := filepath.Join(bin, "args")
	t.Setenv("SWEEP_TEST_ARGS", log)
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$SWEEP_TEST_ARGS\"\nprintf '%s' '{\"protocolVersion\":\"1\",\"targetDir\":\"/tmp\",\"candidates\":[{\"path\":\"/tmp/node_modules\",\"estimatedBytes\":42,\"riskTier\":\"safe\",\"reasons\":[]}],\"summary\":{\"candidateCount\":1,\"estimatedTotalBytes\":42}}'\n"
	require.NoError(t, os.WriteFile(filepath.Join(bin, "sweep"), []byte(script), 0o755))
	target := t.TempDir()
	plan, err := scanSweep(context.Background(), target)
	require.NoError(t, err)
	require.Len(t, plan.Candidates, 1)
	require.EqualValues(t, 42, plan.Candidates[0].EstimatedBytes)
	args, err := os.ReadFile(log)
	require.NoError(t, err)
	require.Equal(t, "--json\nscan\n--\n"+target+"\n", string(args))
	_, err = scanSweep(context.Background(), "relative")
	require.Error(t, err)
}

func TestScanSweepRejectsInvalidOutput(t *testing.T) {
	bin := t.TempDir()
	t.Setenv("PATH", bin)
	require.NoError(t, os.WriteFile(filepath.Join(bin, "sweep"), []byte("#!/bin/sh\nprintf '%s' '{\"protocolVersion\":\"2\",\"candidates\":[],\"summary\":{\"candidateCount\":0}}'\n"), 0o755))
	_, err := scanSweep(context.Background(), t.TempDir())
	require.Error(t, err)
}

func TestSweepCleanupRealCLI(t *testing.T) {
	binary := os.Getenv("SWEEP_TEST_BINARY")
	if binary == "" {
		t.Skip("set SWEEP_TEST_BINARY to test a real Sweep CLI")
	}
	bin := t.TempDir()
	require.NoError(t, os.Symlink(binary, filepath.Join(bin, "sweep")))
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	target := t.TempDir()
	first := filepath.Join(target, "first", "node_modules")
	second := filepath.Join(target, "second", "node_modules")
	for _, p := range []string{first, second} {
		require.NoError(t, os.MkdirAll(p, 0700))
		require.NoError(t, os.WriteFile(filepath.Join(p, "artifact"), []byte("fixture"), 0600))
		require.NoError(t, os.WriteFile(filepath.Join(filepath.Dir(p), "package.json"), []byte("{}"), 0600))
	}
	plan, err := scanSweep(context.Background(), target)
	require.NoError(t, err)
	var id string
	for _, c := range plan.Candidates {
		if c.Path == first {
			id = c.ID
			require.Equal(t, filepath.Dir(first), c.ProjectRoot)
			require.NotNil(t, c.ProjectActiveMs)
			require.Equal(t, "node_modules", c.Kind)
		}
	}
	require.NotEmpty(t, id)
	_, err = prepareSweep(context.Background(), plan.Token, []string{"foreign-id"})
	require.Error(t, err)
	plan, err = scanSweep(context.Background(), target)
	require.NoError(t, err)
	preview, err := prepareSweep(context.Background(), plan.Token, []string{id})
	require.NoError(t, err)
	require.Len(t, preview.Candidates, 1)
	require.NoError(t, os.Rename(first, first+"-old"))
	require.NoError(t, os.MkdirAll(first, 0700))
	require.NoError(t, os.WriteFile(filepath.Join(first, "replacement"), []byte("keep"), 0600))
	report, err := applySweep(context.Background(), preview.Token)
	require.NoError(t, err)
	require.Contains(t, string(report), "candidate identity is missing or changed")
	_, err = applySweep(context.Background(), preview.Token)
	require.Error(t, err)
	require.FileExists(t, filepath.Join(first, "replacement"))
	require.FileExists(t, filepath.Join(second, "artifact"))
	plan, err = scanSweep(context.Background(), target)
	require.NoError(t, err)
	for _, c := range plan.Candidates {
		if c.Path == first {
			id = c.ID
		}
	}
	preview, err = prepareSweep(context.Background(), plan.Token, []string{id})
	require.NoError(t, err)
	report, err = applySweep(context.Background(), preview.Token)
	require.NoError(t, err)
	require.Contains(t, string(report), `"deletedCount": 1`)
	require.NoDirExists(t, first)
	require.Contains(t, string(report), `"trashMoves"`)
	require.Contains(t, string(report), `.sweep-trash-`)
	require.FileExists(t, filepath.Join(second, "artifact"))
}

func TestSweepRejectsInvalidSelectionAndReusedToken(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "sweep")
	require.NoError(t, os.WriteFile(executable, []byte("#!/bin/sh\nexit 0\n"), 0700))
	data, err := os.ReadFile(executable)
	require.NoError(t, err)
	var plan sweepPlan
	plan.TargetDir = t.TempDir()
	plan.Candidates = []sweepCandidate{{ID: "one", Path: filepath.Join(plan.TargetDir, "one"), RiskTier: "safe"}, {ID: "blocked", Path: filepath.Join(plan.TargetDir, "blocked"), RiskTier: "blocked"}}
	newToken := func() string {
		token, err := storeSweep(sweepSession{plan: plan, binary: executable, digest: sha256.Sum256(data)})
		require.NoError(t, err)
		return token
	}
	for _, ids := range [][]string{{}, {"unknown"}, {"one", "one"}, {"blocked"}} {
		token := newToken()
		_, err = prepareSweep(context.Background(), token, ids)
		require.Error(t, err)
		_, err = prepareSweep(context.Background(), token, []string{"one"})
		require.Error(t, err)
	}
	token := newToken()
	discardSweep(token)
	_, err = prepareSweep(context.Background(), token, []string{"one"})
	require.Error(t, err)
	_, err = applySweep(context.Background(), "unknown")
	require.Error(t, err)
}

func TestCancelSweepScan(t *testing.T) {
	bin := t.TempDir()
	t.Setenv("PATH", bin)
	started := filepath.Join(bin, "started")
	t.Setenv("SWEEP_TEST_STARTED", started)
	script := "#!/bin/sh\n/bin/sleep 30 &\nprintf '%s\n' \"$!\" > \"$SWEEP_TEST_STARTED\"\nwait\n"
	require.NoError(t, os.WriteFile(filepath.Join(bin, "sweep"), []byte(script), 0755))
	target := t.TempDir()
	done := make(chan error, 1)
	go func() {
		_, err := managedSweepScan(context.Background(), target, "test-cancel")
		done <- err
	}()
	require.Eventually(t, func() bool { _, err := os.Stat(started); return err == nil }, 3*time.Second, 10*time.Millisecond)
	require.True(t, cancelSweepScan("test-cancel"))
	select {
	case err := <-done:
		require.ErrorContains(t, err, "context canceled")
	case <-time.After(3 * time.Second):
		t.Fatal("cancelled scan did not stop")
	}
	require.False(t, cancelSweepScan("test-cancel"))
}
