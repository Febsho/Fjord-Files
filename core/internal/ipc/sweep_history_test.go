package ipc

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestSweepHistoryReadAndValidate(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	argfile := filepath.Join(dir, "args")
	t.Setenv("HISTORY_TEST_ARGS", argfile)
	script := `#!/bin/sh
printf '%s\n' "$@" > "$HISTORY_TEST_ARGS"
printf '%s' '{"scope":"retained-history","byteBasis":"plan-estimate","recent":[{"ts":"2026-11-15T10:00:00Z","targetDir":"/home/test","deleted":1,"bytesFreed":10,"failed":0,"interrupted":false,"trashDir":"/home/test/.sweep-trash"}]}'
`
	executable := filepath.Join(dir, "sweep")
	require.NoError(t, os.WriteFile(executable, []byte(script), 0700))
	history, err := readSweepHistory(context.Background())
	require.NoError(t, err)
	require.Len(t, history.Recent, 1)
	require.Equal(t, "/home/test/.sweep-trash", history.Recent[0].TrashDir)
	args, err := os.ReadFile(argfile)
	require.NoError(t, err)
	require.Equal(t, "--json\nstats\n", string(args))
	require.NoError(t, os.WriteFile(executable, []byte("#!/bin/sh\nprintf '%s' '{\"scope\":\"wrong\",\"recent\":[]}'\n"), 0700))
	_, err = readSweepHistory(context.Background())
	require.ErrorContains(t, err, "unsupported")
	require.NoError(t, os.WriteFile(executable, []byte("#!/bin/sh\nprintf '%s' '{\"scope\":\"retained-history\",\"byteBasis\":\"plan-estimate\",\"recent\":[{\"ts\":\"2026-11-15\",\"targetDir\":\"/tmp\"}]}'\n"), 0700))
	_, err = readSweepHistory(context.Background())
	require.ErrorContains(t, err, "invalid Sweep history entry")
}

func TestSweepHistoryRealCLI(t *testing.T) {
	binary := os.Getenv("SWEEP_TEST_BINARY")
	if binary == "" {
		t.Skip("set SWEEP_TEST_BINARY to test the real Sweep CLI")
	}
	root := t.TempDir()
	bin := filepath.Join(root, "bin")
	config := filepath.Join(root, "config")
	require.NoError(t, os.MkdirAll(bin, 0700))
	require.NoError(t, os.MkdirAll(filepath.Join(config, "sweep"), 0700))
	require.NoError(t, os.Symlink(binary, filepath.Join(bin, "sweep")))
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("HOME", root)
	t.Setenv("XDG_CONFIG_HOME", config)
	record := `{"ts":"2026-11-15T10:00:00Z","targetDir":"/tmp/project","engine":"js","deleted":1,"bytesFreed":42,"failed":0,"interrupted":false,"trashDir":"/tmp/project/.sweep-trash"}` + "\n"
	require.NoError(t, os.WriteFile(filepath.Join(config, "sweep", "history.jsonl"), []byte(record), 0600))
	history, err := readSweepHistory(context.Background())
	require.NoError(t, err)
	require.Len(t, history.Recent, 1)
	require.Equal(t, "/tmp/project/.sweep-trash", history.Recent[0].TrashDir)
	require.EqualValues(t, 42, *history.Recent[0].BytesFreed)
}
