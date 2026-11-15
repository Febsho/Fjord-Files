package fileops

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestListArchiveRejectsUnsafeEntriesAndLinks(t *testing.T) {
	for _, kind := range []string{"zip", "tar"} {
		t.Run(kind, func(t *testing.T) {
			file, err := os.Create(filepath.Join(t.TempDir(), "test."+kind))
			require.NoError(t, err)
			if kind == "zip" {
				w := zip.NewWriter(file)
				for _, name := range []string{"folder/good.txt", "../escape", "/absolute", `a\..\escape`} {
					_, err = w.Create(name)
					require.NoError(t, err)
				}
				require.NoError(t, w.Close())
			} else {
				w := tar.NewWriter(file)
				for _, h := range []*tar.Header{{Name: "folder/good.txt", Mode: 0644}, {Name: "../escape", Mode: 0644}, {Name: "link", Typeflag: tar.TypeSymlink, Linkname: "/etc"}} {
					require.NoError(t, w.WriteHeader(h))
				}
				require.NoError(t, w.Close())
			}
			result, err := ListArchive(file, file.Name())
			require.NoError(t, err)
			require.Equal(t, []ArchiveEntry{{Path: "folder/good.txt"}}, result.Entries)
			require.NoError(t, file.Close())
		})
	}
}

func TestZipMetadataBudget(t *testing.T) {
	f, err := os.Create(filepath.Join(t.TempDir(), "oversized.zip"))
	require.NoError(t, err)
	defer f.Close()
	w := zip.NewWriter(f)
	for i := 0; i < 1100; i++ {
		_, err = w.Create(fmt.Sprintf("%04d-%s", i, strings.Repeat("a", 4000)))
		require.NoError(t, err)
	}
	require.NoError(t, w.Close())
	_, err = ListArchive(f, f.Name())
	require.ErrorContains(t, err, "metadata exceeds preview limit")
}

func TestListCompressedTarUsesContent(t *testing.T) {
	f, err := os.Create(filepath.Join(t.TempDir(), "renamed.txt"))
	require.NoError(t, err)
	defer f.Close()
	compressed := gzip.NewWriter(f)
	archive := tar.NewWriter(compressed)
	require.NoError(t, archive.WriteHeader(&tar.Header{Name: "folder/note.txt", Mode: 0644, Size: 3}))
	_, err = archive.Write([]byte("abc"))
	require.NoError(t, err)
	require.NoError(t, archive.Close())
	require.NoError(t, compressed.Close())
	result, err := ListArchive(f, f.Name())
	require.NoError(t, err)
	require.Equal(t, []ArchiveEntry{{Path: "folder/note.txt", Size: 3}}, result.Entries)
}

func TestListSevenZipArchive(t *testing.T) {
	sevenZip, err := exec.LookPath("7z")
	if err != nil {
		t.Skip("7z is needed to create a real 7-Zip fixture")
	}
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "safe"), 0700))
	require.NoError(t, os.WriteFile(filepath.Join(root, "safe", "note.txt"), []byte("hello"), 0600))
	archivePath := filepath.Join(root, "sample.7z")
	cmd := exec.Command(sevenZip, "a", "-t7z", "-mx=0", archivePath, "safe/note.txt")
	cmd.Dir = root
	output, err := cmd.CombinedOutput()
	require.NoError(t, err, string(output))

	archive, err := os.Open(archivePath)
	require.NoError(t, err)
	defer archive.Close()
	var head [8]byte
	n, err := archive.ReadAt(head[:], 0)
	require.NoError(t, err)
	require.True(t, BrowsableArchive(head[:n]))
	listing, err := ListArchive(archive, archivePath)
	require.NoError(t, err)
	require.False(t, listing.Truncated)
	require.Contains(t, listing.Entries, ArchiveEntry{Path: "safe/note.txt", Size: 5})
}

func TestListRarArchive(t *testing.T) {
	archive, err := os.Open(filepath.Join("testdata", "libarchive.rar"))
	require.NoError(t, err)
	defer archive.Close()
	var head [8]byte
	n, err := archive.ReadAt(head[:], 0)
	require.NoError(t, err)
	require.True(t, BrowsableArchive(head[:n]))
	listing, err := ListArchive(archive, archive.Name())
	require.NoError(t, err)
	require.False(t, listing.Truncated)
	require.Contains(t, listing.Entries, ArchiveEntry{Path: "test.txt", Size: 20})
	require.Contains(t, listing.Entries, ArchiveEntry{Path: "testdir/test.txt", Size: 20})
	for _, entry := range listing.Entries {
		require.NotEqual(t, "testlink", entry.Path, "symbolic links are omitted from archive previews")
	}
}

func TestListCpioArchive(t *testing.T) {
	archive, err := os.Open(filepath.Join("testdata", "sample.cpio"))
	require.NoError(t, err)
	defer archive.Close()
	var head [8]byte
	n, err := archive.ReadAt(head[:], 0)
	require.NoError(t, err)
	require.True(t, BrowsableArchive(head[:n]))
	listing, err := ListArchive(archive, archive.Name())
	require.NoError(t, err)
	require.False(t, listing.Truncated)
	require.Contains(t, listing.Entries, ArchiveEntry{Path: "sample/README.md", Size: 5})
	require.Contains(t, listing.Entries, ArchiveEntry{Path: "sample/src/main.go", Size: 12})
	for _, entry := range listing.Entries {
		require.NotEqual(t, "sample/link", entry.Path, "symbolic links are omitted from archive previews")
	}
}
