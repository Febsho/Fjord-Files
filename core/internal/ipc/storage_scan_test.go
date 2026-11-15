package ipc

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestStorageScanDoesNotFollowLinksOrDoubleCount(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(outside, "secret"), make([]byte, 8192), 0600))
	a, b := filepath.Join(root, "a"), filepath.Join(root, "b")
	require.NoError(t, os.Mkdir(a, 0700))
	require.NoError(t, os.Mkdir(b, 0700))
	original := filepath.Join(a, "file")
	require.NoError(t, os.WriteFile(original, make([]byte, 9), 0600))
	require.NoError(t, os.WriteFile(filepath.Join(b, "other"), make([]byte, 3), 0600))
	require.NoError(t, os.Link(original, filepath.Join(a, "hardlink")))
	require.NoError(t, os.Symlink(outside, filepath.Join(root, "outside")))
	got, err := storageScan(context.Background(), root, 100)
	require.NoError(t, err)
	require.False(t, got.Truncated)
	require.Len(t, got.Files, 2)
	require.EqualValues(t, 12, got.TotalSize)
	require.EqualValues(t, 9, got.Files[0].Size)
	require.Len(t, got.Directories, 2)
	require.Equal(t, a, got.Directories[0].Path)
	require.EqualValues(t, 9, got.Directories[0].Size)
	require.GreaterOrEqual(t, got.Skipped, 1)
	for _, item := range got.Files {
		require.NotContains(t, item.Path, "secret")
	}
	_, err = storageScan(context.Background(), filepath.Join(root, "outside"), 100)
	require.Error(t, err)
}

func TestStorageScanLimitsAndCancellation(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"a", "b", "c"} {
		require.NoError(t, os.WriteFile(filepath.Join(root, name), []byte("x"), 0600))
	}
	got, err := storageScan(context.Background(), root, 1)
	require.NoError(t, err)
	require.True(t, got.Truncated)
	require.Equal(t, 1, got.Visited)
	require.EqualValues(t, 1, got.TotalSize)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err = storageScan(ctx, root, 100)
	require.ErrorIs(t, err, context.Canceled)
	_, err = storageScan(context.Background(), "relative", 100)
	require.Error(t, err)
}
