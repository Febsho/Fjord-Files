package fileops

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestExtractMember(t *testing.T) {
	dir := t.TempDir()
	archive := filepath.Join(dir, "test.zip")
	f, err := os.Create(archive)
	require.NoError(t, err)
	z := zip.NewWriter(f)
	for _, entry := range []struct{ name, body string }{{"folder/file.txt", "wanted"}, {"other.txt", "other"}, {"duplicate", "one"}, {"duplicate", "two"}} {
		w, err := z.Create(entry.name)
		require.NoError(t, err)
		_, err = w.Write([]byte(entry.body))
		require.NoError(t, err)
	}
	require.NoError(t, z.Close())
	require.NoError(t, f.Close())
	manager, bus := newHarness(t)
	job := func(member string) View {
		return run(t, manager, bus, spec{kind: KindExtractMember, sources: []string{archive}, dest: dir, member: member})
	}
	require.Equal(t, StateDone, job("folder/file.txt").State)
	b, err := os.ReadFile(filepath.Join(dir, "file.txt"))
	require.NoError(t, err)
	require.Equal(t, "wanted", string(b))
	require.Equal(t, StateFailed, job("folder/file.txt").State)
	b, err = os.ReadFile(filepath.Join(dir, "file.txt"))
	require.NoError(t, err)
	require.Equal(t, "wanted", string(b))
	require.Equal(t, StateFailed, job("duplicate").State)
	require.NoFileExists(t, filepath.Join(dir, "duplicate"))
	require.Equal(t, StateFailed, job("../other.txt").State)
	require.NoFileExists(t, filepath.Join(dir, "other.txt"))
}

func TestExtractMemberFromSevenZipAndRar(t *testing.T) {
	t.Run("7z", func(t *testing.T) {
		sevenZip, err := exec.LookPath("7z")
		if err != nil {
			t.Skip("7z is needed to create a real 7-Zip fixture")
		}
		root := t.TempDir()
		require.NoError(t, os.Mkdir(filepath.Join(root, "safe"), 0700))
		require.NoError(t, os.WriteFile(filepath.Join(root, "safe", "note.txt"), []byte("hello"), 0600))
		archive := filepath.Join(root, "sample.7z")
		cmd := exec.Command(sevenZip, "a", "-t7z", "-mx=0", archive, "safe/note.txt")
		cmd.Dir = root
		output, err := cmd.CombinedOutput()
		require.NoError(t, err, string(output))
		manager, bus := newHarness(t)
		result := run(t, manager, bus, spec{kind: KindExtractMember, sources: []string{archive}, dest: root, member: "safe/note.txt"})
		require.Equal(t, StateDone, result.State)
		body, err := os.ReadFile(filepath.Join(root, "note.txt"))
		require.NoError(t, err)
		require.Equal(t, "hello", string(body))
	})

	t.Run("rar", func(t *testing.T) {
		root := t.TempDir()
		archive := filepath.Join("testdata", "libarchive.rar")
		manager, bus := newHarness(t)
		result := run(t, manager, bus, spec{kind: KindExtractMember, sources: []string{archive}, dest: root, member: "test.txt"})
		require.Equal(t, StateDone, result.State)
		body, err := os.ReadFile(filepath.Join(root, "test.txt"))
		require.NoError(t, err)
		require.Len(t, body, 20)
	})
}

func TestExtractCorruptMemberLeavesNoOutput(t *testing.T) {
	dir := t.TempDir()
	archive := filepath.Join(dir, "corrupt.zip")
	f, err := os.Create(archive)
	require.NoError(t, err)
	z := zip.NewWriter(f)
	h := &zip.FileHeader{Name: "broken.txt", Method: zip.Store}
	w, err := z.CreateHeader(h)
	require.NoError(t, err)
	_, err = w.Write([]byte("before corruption"))
	require.NoError(t, err)
	require.NoError(t, z.Close())
	require.NoError(t, f.Close())
	zr, err := zip.OpenReader(archive)
	require.NoError(t, err)
	offset, err := zr.File[0].DataOffset()
	require.NoError(t, err)
	require.NoError(t, zr.Close())
	f, err = os.OpenFile(archive, os.O_WRONLY, 0)
	require.NoError(t, err)
	_, err = f.WriteAt([]byte("X"), offset)
	require.NoError(t, err)
	require.NoError(t, f.Close())
	manager, bus := newHarness(t)
	result := run(t, manager, bus, spec{kind: KindExtractMember, sources: []string{archive}, dest: dir, member: "broken.txt"})
	require.Equal(t, StateFailed, result.State)
	require.NoFileExists(t, filepath.Join(dir, "broken.txt"))
	entries, err := os.ReadDir(dir)
	require.NoError(t, err)
	require.Len(t, entries, 1, "temporary extraction directory must be removed")
}

func TestExtractTarGzipMemberAndRejectDuplicates(t *testing.T) {
	dir := t.TempDir()
	archive := filepath.Join(dir, "test.tar.gz")
	f, err := os.Create(archive)
	require.NoError(t, err)
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	for _, item := range []struct{ name, body string }{{"nested/first.txt", "first"}, {"dupe.txt", "one"}, {"dupe.txt", "two"}} {
		require.NoError(t, tw.WriteHeader(&tar.Header{Name: item.name, Mode: 0600, Size: int64(len(item.body))}))
		_, err = tw.Write([]byte(item.body))
		require.NoError(t, err)
	}
	require.NoError(t, tw.Close())
	require.NoError(t, gz.Close())
	require.NoError(t, f.Close())
	manager, bus := newHarness(t)
	runMember := func(member string) View {
		return run(t, manager, bus, spec{kind: KindExtractMember, sources: []string{archive}, dest: dir, member: member})
	}
	require.Equal(t, StateDone, runMember("nested/first.txt").State)
	contents, err := os.ReadFile(filepath.Join(dir, "first.txt"))
	require.NoError(t, err)
	require.Equal(t, "first", string(contents))
	require.Equal(t, StateFailed, runMember("dupe.txt").State)
	require.NoFileExists(t, filepath.Join(dir, "dupe.txt"))
}
