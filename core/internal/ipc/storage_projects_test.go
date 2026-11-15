package ipc

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestStorageProjectsScanIsReadOnlyBoundedAndEstimatesActivity(t *testing.T) {
	root := t.TempDir()
	projects := filepath.Join(root, "projects")
	goProject := filepath.Join(projects, "go-app")
	nodeProject := filepath.Join(projects, "web-app")
	plain := filepath.Join(projects, "plain")
	for _, dir := range []string{goProject, nodeProject, plain} {
		require.NoError(t, os.MkdirAll(dir, 0700))
	}
	require.NoError(t, os.WriteFile(filepath.Join(goProject, "go.mod"), []byte("module example\n"), 0600))
	require.NoError(t, os.WriteFile(filepath.Join(goProject, "main.go"), []byte("package main\n"), 0600))
	require.NoError(t, os.Mkdir(filepath.Join(goProject, "node_modules"), 0700))
	require.NoError(t, os.WriteFile(filepath.Join(goProject, "node_modules", "generated.js"), []byte("generated"), 0600))
	require.NoError(t, os.WriteFile(filepath.Join(nodeProject, "package.json"), []byte("{}\n"), 0600))
	require.NoError(t, os.WriteFile(filepath.Join(plain, "Makefile"), []byte("all:\n"), 0600))

	old := time.Date(2021, 2, 3, 4, 5, 6, 0, time.Local)
	require.NoError(t, os.Chtimes(filepath.Join(goProject, "go.mod"), old, old))
	require.NoError(t, os.Chtimes(filepath.Join(goProject, "main.go"), old.Add(time.Hour), old.Add(time.Hour)))
	// Generated dependency changes contribute to size but not to the activity estimate.
	require.NoError(t, os.Chtimes(filepath.Join(goProject, "node_modules", "generated.js"), time.Now(), time.Now()))

	outside := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(outside, "Cargo.toml"), []byte("[package]\n"), 0600))
	require.NoError(t, os.Symlink(outside, filepath.Join(projects, "external")))

	got, err := storageProjectsScan(context.Background(), projects, 1000)
	require.NoError(t, err)
	require.False(t, got.Truncated)
	require.False(t, got.ProjectsTruncated)
	require.Len(t, got.Projects, 2)
	require.Equal(t, goProject, got.Projects[0].Path)
	require.Equal(t, []string{"Go"}, got.Projects[0].Kinds)
	require.EqualValues(t, len("module example\n")+len("package main\n")+len("generated"), got.Projects[0].Size)
	require.NotNil(t, got.Projects[0].LastActivityMs)
	require.EqualValues(t, old.Add(time.Hour).UnixMilli(), *got.Projects[0].LastActivityMs)
	require.Equal(t, nodeProject, got.Projects[1].Path)
	require.NotContains(t, got.Projects, storageProject{Path: filepath.Join(projects, "external")})
	require.NotContains(t, got.Projects, storageProject{Path: filepath.Join(outside)})

	_, err = storageProjectsScan(context.Background(), filepath.Join(projects, "external"), 1000)
	require.Error(t, err)
	_, err = storageProjectsScan(context.Background(), "relative", 1000)
	require.Error(t, err)
}

func TestStorageProjectsScanHonorsLimitsAndCancellation(t *testing.T) {
	root := t.TempDir()
	project := filepath.Join(root, "project")
	require.NoError(t, os.Mkdir(project, 0700))
	require.NoError(t, os.WriteFile(filepath.Join(project, "Cargo.toml"), []byte("[package]\n"), 0600))
	for _, name := range []string{"a", "b", "c"} {
		require.NoError(t, os.WriteFile(filepath.Join(project, name), []byte("x"), 0600))
	}
	got, err := storageProjectsScan(context.Background(), root, 1)
	require.NoError(t, err)
	require.True(t, got.Truncated)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err = storageProjectsScan(ctx, root, 100)
	require.ErrorIs(t, err, context.Canceled)
}
