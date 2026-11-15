package ipc

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestTextEditorSaveAndConflicts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "note.txt")
	require.NoError(t, os.WriteFile(path, []byte("original\n"), 0600))
	doc, _, err := editorRead(path)
	require.NoError(t, err)
	for _, invalid := range []string{"a\rb", "a\u2028b", "a\u2029b"} {
		_, err = editorSave(path, doc.Revision, invalid)
		require.Error(t, err)
	}
	saved, err := editorSave(path, doc.Revision, "edited\n")
	require.NoError(t, err)
	require.Equal(t, path+".edited", saved.Path)
	original, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Equal(t, "original\n", string(original))
	data, err := os.ReadFile(saved.Path)
	require.NoError(t, err)
	require.Equal(t, "edited\n", string(data))
	require.NoError(t, os.WriteFile(saved.Path, []byte("external\n"), 0600))
	_, err = editorSave(saved.Path, saved.Revision, "mine\n")
	require.ErrorContains(t, err, "changed")
	data, err = os.ReadFile(saved.Path)
	require.NoError(t, err)
	require.Equal(t, "external\n", string(data))
}

func TestTextEditorRevisionDetectsExternalChange(t *testing.T) {
	path := filepath.Join(t.TempDir(), "note.txt")
	require.NoError(t, os.WriteFile(path, []byte("before"), 0600))
	document, _, err := editorRead(path)
	require.NoError(t, err)
	revision, err := editorRevision(path)
	require.NoError(t, err)
	require.Equal(t, document.Revision, revision)

	require.NoError(t, os.WriteFile(path, []byte("after!"), 0600))
	revision, err = editorRevision(path)
	require.NoError(t, err)
	require.NotEqual(t, document.Revision, revision)
	require.NoError(t, os.Remove(path))
	_, err = editorRevision(path)
	require.Error(t, err)
}

func TestTextRevisionIPC(t *testing.T) {
	path := filepath.Join(t.TempDir(), "note.txt")
	require.NoError(t, os.WriteFile(path, []byte("before"), 0600))
	out := routeAndRead(t, Request{ID: 1, Method: "files.textRevision", Params: map[string]any{"path": path}}, Deps{})["result"].(map[string]any)
	require.NotEmpty(t, out["revision"])
	require.NoError(t, os.WriteFile(path, []byte("after"), 0600))
	changed := routeAndRead(t, Request{ID: 2, Method: "files.textRevision", Params: map[string]any{"path": path}}, Deps{})["result"].(map[string]any)
	require.NotEqual(t, out["revision"], changed["revision"])
}

func TestTextEditorAvoidsCollisionsAndLinks(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "note.txt")
	require.NoError(t, os.WriteFile(path, []byte("text"), 0600))
	require.NoError(t, os.WriteFile(path+".edited", []byte("existing"), 0600))
	require.NoError(t, os.Symlink(path, path+".edited.1"))
	doc, _, err := editorRead(path)
	require.NoError(t, err)
	saved, err := editorSave(path, doc.Revision, "new")
	require.NoError(t, err)
	require.Equal(t, path+".edited.2", saved.Path)
	existing, err := os.ReadFile(path + ".edited")
	require.NoError(t, err)
	require.Equal(t, "existing", string(existing))
	original, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Equal(t, "text", string(original))
	_, _, err = editorRead(path + ".edited.1")
	require.Error(t, err)
	require.NoError(t, os.WriteFile(path, []byte(strings.Repeat("x", editorMaxBytes+1)), 0600))
	_, _, err = editorRead(path)
	require.Error(t, err)
	require.NoError(t, os.WriteFile(path, []byte("a\r\nb"), 0600))
	_, _, err = editorRead(path)
	require.Error(t, err)
}
