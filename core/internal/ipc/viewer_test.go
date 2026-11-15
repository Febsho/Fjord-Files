package ipc

import (
	"archive/zip"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"github.com/duxlabs-dev/dux-files/core/internal/mimeapps"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDetectViewerUsesContent(t *testing.T) {
	tarHead := make([]byte, 512)
	copy(tarHead[257:], []byte("ustar"))
	detector := mimeapps.NewDetector(mimeapps.LoadDB(nil))
	dir := t.TempDir()
	for _, tc := range []struct {
		name   string
		data   []byte
		viewer string
	}{
		{"renamed.txt", tarHead, "archive"},
		{"picture.txt", []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR"), "image"},
		{"notes.png", []byte("hello world\n"), "text"},
		{"notes.zip", []byte("hello world\n"), "text"},
		{"image.zip", []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR"), "image"},
		{"unknown.pdf", []byte{0, 1, 2, 3, 4}, ""},
		{"empty", nil, "text"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(dir, tc.name)
			require.NoError(t, os.WriteFile(path, tc.data, 0600))
			result, err := detectViewer(path, detector)
			require.NoError(t, err)
			assert.Equal(t, tc.viewer, result.Viewer)
		})
	}
	_, err := detectViewer(filepath.Join(dir, "missing"), detector)
	require.Error(t, err)
	_, err = detectViewer(dir, detector)
	require.Error(t, err)
	fifo := filepath.Join(dir, "fifo")
	require.NoError(t, syscall.Mkfifo(fifo, 0600))
	_, err = detectViewer(fifo, detector)
	require.Error(t, err)
}

func TestDetectViewerRecognizesOfficeByArchiveContents(t *testing.T) {
	detector := mimeapps.NewDetector(mimeapps.LoadDB(nil))
	path := filepath.Join(t.TempDir(), "wrong-extension.zip")
	f, err := os.Create(path)
	require.NoError(t, err)
	archive := zip.NewWriter(f)
	content, err := archive.Create("word/document.xml")
	require.NoError(t, err)
	_, err = content.Write([]byte("<document/>"))
	require.NoError(t, err)
	require.NoError(t, archive.Close())
	require.NoError(t, f.Close())
	result, err := detectViewer(path, detector)
	require.NoError(t, err)
	assert.Equal(t, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", result.Mime)
	_, available := officeConverter()
	if available {
		assert.Equal(t, "office", result.Viewer)
	} else {
		assert.Empty(t, result.Viewer)
	}
}

func TestOfficeMimeFromZip(t *testing.T) {
	for _, tc := range []struct {
		name, member, want string
	}{
		{"word", "word/document.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
		{"sheet", "xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"},
		{"slides", "ppt/presentation.xml", "application/vnd.openxmlformats-officedocument.presentationml.presentation"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "document.zip")
			f, err := os.Create(path)
			require.NoError(t, err)
			archive := zip.NewWriter(f)
			member, err := archive.Create(tc.member)
			require.NoError(t, err)
			_, err = member.Write([]byte("xml"))
			require.NoError(t, err)
			require.NoError(t, archive.Close())
			require.NoError(t, f.Close())
			f, err = os.Open(path)
			require.NoError(t, err)
			info, err := f.Stat()
			require.NoError(t, err)
			assert.Equal(t, tc.want, officeMimeFromZip(f, info.Size()))
			require.NoError(t, f.Close())
		})
	}
}

func TestUnderOfficeRuntime(t *testing.T) {
	assert.True(t, underOfficeRuntime("/usr/bin/libreoffice"))
	assert.True(t, underOfficeRuntime("/opt/libreoffice/program/soffice"))
	assert.False(t, underOfficeRuntime("/home/user/.cache/codex/soffice"))
	assert.False(t, underOfficeRuntime("/usr-local/bin/soffice"))
}
