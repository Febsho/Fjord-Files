package files

import (
	"image"
	"image/png"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func writeThumbnailerEntry(t *testing.T, dir, name, body string) {
	t.Helper()
	require.NoError(t, os.MkdirAll(dir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, name+".thumbnailer"), []byte(body), 0o644))
}

func writeScript(t *testing.T, path, body string) {
	t.Helper()
	require.NoError(t, os.WriteFile(path, []byte("#!/bin/sh\n"+body+"\n"), 0o755))
}

func isolatedThumbnailerDirs(t *testing.T) (home, system string) {
	t.Helper()
	home = filepath.Join(t.TempDir(), "home")
	system = filepath.Join(t.TempDir(), "system")
	t.Setenv("XDG_DATA_HOME", home)
	t.Setenv("XDG_DATA_DIRS", system)
	return filepath.Join(home, "thumbnailers"), filepath.Join(system, "thumbnailers")
}

func TestSplitShellWords(t *testing.T) {
	words, err := splitShellWords(`/usr/bin/tool -i "%i" 'a b' c\ d --flag=%s`)
	require.NoError(t, err)
	assert.Equal(t, []string{"/usr/bin/tool", "-i", "%i", "a b", "c d", "--flag=%s"}, words)

	_, err = splitShellWords(`tool "unterminated`)
	assert.Error(t, err)
}

func TestThumbnailerCommandExpandsPlaceholders(t *testing.T) {
	tool := thumbnailer{argv: []string{"/usr/bin/tool", "--in=%i", "%u", "-o", "%o", "-s", "%s", "-m", "%m", "100%%"}}
	job := thumbJob{input: "/data/my clip.mp4", output: "/tmp/out.png", size: 256, mime: "video/mp4"}
	assert.Equal(t, []string{"/usr/bin/tool", "--in=/data/my clip.mp4", "file:///data/my%20clip.mp4", "-o", "/tmp/out.png", "-s", "256", "-m", "video/mp4", "100%"}, tool.command(job))

	prefixed := thumbnailer{argv: []string{"/usr/bin/pdftoppm", "%o"}, outputPrefix: true}
	assert.Equal(t, []string{"/usr/bin/pdftoppm", "/tmp/out"}, prefixed.command(job))
}

func TestParseThumbnailerEntryReadsOnlyItsGroup(t *testing.T) {
	keys := parseThumbnailerEntry([]byte("[Other]\nExec=wrong\n# comment\n[Thumbnailer Entry]\nTryExec=tool\nExec=tool %i %o\nExec=dup\nMimeType=video/mp4;video/webm;\n"))
	assert.Equal(t, "tool %i %o", keys["Exec"])
	assert.Equal(t, "tool", keys["TryExec"])
	assert.Equal(t, "video/mp4;video/webm;", keys["MimeType"])
}

func TestLoadThumbnailersPrefersDataHomeAndSkipsMissingTools(t *testing.T) {
	homeDir, systemDir := isolatedThumbnailerDirs(t)
	bin := t.TempDir()
	writeScript(t, filepath.Join(bin, "home-tool"), "exit 0")
	writeScript(t, filepath.Join(bin, "system-tool"), "exit 0")

	writeThumbnailerEntry(t, homeDir, "home", "[Thumbnailer Entry]\nExec="+filepath.Join(bin, "home-tool")+" %i %o\nMimeType=video/mp4;\n")
	writeThumbnailerEntry(t, systemDir, "system", "[Thumbnailer Entry]\nExec="+filepath.Join(bin, "system-tool")+" %i %o\nMimeType=video/mp4;video/webm;\n")
	writeThumbnailerEntry(t, systemDir, "missing", "[Thumbnailer Entry]\nTryExec=/nonexistent/tool\nExec=/nonexistent/tool %i %o\nMimeType=application/x-missing;\n")
	writeThumbnailerEntry(t, systemDir, "absent-exec", "[Thumbnailer Entry]\nExec=/nonexistent/other %i %o\nMimeType=application/x-absent;\n")

	set := &thumbnailers{byMime: map[string]thumbnailer{}}
	set.loadDirs()

	mp4, ok := set.lookup("video/mp4")
	require.True(t, ok)
	assert.Equal(t, filepath.Join(bin, "home-tool"), mp4.argv[0])
	webm, ok := set.lookup("video/webm")
	require.True(t, ok)
	assert.Equal(t, filepath.Join(bin, "system-tool"), webm.argv[0])
	_, ok = set.lookup("application/x-missing")
	assert.False(t, ok, "TryExec that is not installed disables the entry")
	_, ok = set.lookup("application/x-absent")
	assert.False(t, ok, "an Exec binary that is not installed disables the entry")
	assert.Equal(t, []string{"video"}, set.mediaKinds())
}

func TestExternalThumbnailerRequiresSandbox(t *testing.T) {
	_, systemDir := isolatedThumbnailerDirs(t)
	marker := filepath.Join(t.TempDir(), "ran")
	script := filepath.Join(t.TempDir(), "fake-thumbnailer")
	writeScript(t, script, `touch "`+marker+`"`)
	writeThumbnailerEntry(t, systemDir, "fake", "[Thumbnailer Entry]\nExec="+script+" %i %o %s\nMimeType=video/x-fake;\n")

	cache := t.TempDir()
	svc := NewService(&fakeBus{}, cache, nil)
	t.Cleanup(svc.Close)
	svc.thumbs.bwrap = ""

	source := filepath.Join(t.TempDir(), "clip.fake")
	require.NoError(t, os.WriteFile(source, []byte("not really a video"), 0o644))
	entry, err := svc.Stat(source)
	require.NoError(t, err)
	entry.Mime = "video/x-fake"
	require.False(t, svc.thumbs.Supports(entry.Mime))
	assert.Contains(t, svc.Capabilities(), "thumbnail.sandbox.required")
	assert.NotContains(t, svc.Capabilities(), "thumbnail.video")
	_, err = svc.thumbs.Generate(entry, "normal")
	require.ErrorContains(t, err, "no thumbnailer")
	assert.NoFileExists(t, marker, "external thumbnailer must never run without Bubblewrap")
}

func TestExternalThumbnailersRunInBubblewrap(t *testing.T) {
	t.Setenv("PATH", "/usr/bin:/bin")
	if resolveExecutable("bwrap") == "" || resolveExecutable("pdftoppm") == "" || resolveExecutable("ffmpegthumbnailer") == "" {
		t.Skip("bwrap, pdftoppm, and ffmpegthumbnailer are required for the sandbox integration test")
	}
	isolatedThumbnailerDirs(t)
	cache := t.TempDir()
	svc := NewService(&fakeBus{}, cache, nil)
	t.Cleanup(svc.Close)
	require.NotEmpty(t, svc.thumbs.bwrap)
	assert.Contains(t, svc.Capabilities(), "thumbnail.sandboxed")
	for _, tc := range []struct{ path, mime, kind string }{
		{"testdata/thumbnail.pdf", "application/pdf", "pdf"},
		{"testdata/thumbnail.mp4", "video/mp4", "video"},
	} {
		t.Run(tc.mime, func(t *testing.T) {
			assert.Contains(t, svc.Capabilities(), "thumbnail."+tc.kind)
			entry, err := svc.Stat(tc.path)
			require.NoError(t, err)
			entry.Mime = tc.mime
			dst, err := svc.thumbs.Generate(entry, "normal")
			require.NoError(t, err)

			file, err := os.Open(dst)
			require.NoError(t, err)
			defer file.Close()
			config, err := png.DecodeConfig(file)
			require.NoError(t, err)
			assert.Greater(t, config.Width, 0)
			assert.Greater(t, config.Height, 0)
			assert.LessOrEqual(t, config.Width, 128)
			assert.LessOrEqual(t, config.Height, 128)
		})
	}
}

func TestUserThumbnailerOverridesNativeImageDecode(t *testing.T) {
	t.Setenv("PATH", "/usr/bin:/bin")
	homeDir, systemDir := isolatedThumbnailerDirs(t)
	userDir := t.TempDir()
	marker := filepath.Join(userDir, "marker.png")
	writeTestPNG(t, marker, 32, 16)
	user := filepath.Join(userDir, "user-tool")
	writeScript(t, user, `cp "$(dirname "$0")/marker.png" "$2"`)
	system := filepath.Join(t.TempDir(), "system-tool")
	writeScript(t, system, "exit 7")
	writeThumbnailerEntry(t, homeDir, "user", "[Thumbnailer Entry]\nExec="+user+" %i %o %s\nMimeType=image/png;\n")
	writeThumbnailerEntry(t, systemDir, "system", "[Thumbnailer Entry]\nExec="+system+" %i %o %s\nMimeType=image/png;image/jpeg;\n")

	svc := NewService(&fakeBus{}, t.TempDir(), nil)
	t.Cleanup(svc.Close)

	source := filepath.Join(t.TempDir(), "photo.png")
	writeTestPNG(t, source, 400, 200)
	entry, err := svc.Stat(source)
	require.NoError(t, err)
	require.Equal(t, "image/png", entry.Mime)

	dst, err := svc.thumbs.Generate(entry, "normal")
	require.NoError(t, err)
	if svc.thumbs.bwrap != "" {
		assert.Equal(t, image.Point{X: 32, Y: 16}, pngSize(t, dst), "the user thumbnailer runs with its read-only tool directory mounted")
	} else {
		assert.Equal(t, image.Point{X: 128, Y: 64}, pngSize(t, dst), "native images fall back to the built-in decoder when external sandboxing is unavailable")
	}

	entry.Mime = "image/jpeg"
	dst, err = svc.thumbs.Generate(entry, "large")
	require.NoError(t, err, "a system thumbnailer does not displace the native decoder")
	assert.Equal(t, image.Point{X: 256, Y: 128}, pngSize(t, dst))
}

func pngSize(t *testing.T, path string) image.Point {
	t.Helper()
	file, err := os.Open(path)
	require.NoError(t, err)
	defer file.Close()
	config, err := png.DecodeConfig(file)
	require.NoError(t, err)
	return image.Point{X: config.Width, Y: config.Height}
}

func TestExternalThumbnailerFailureAndTimeoutLeaveMarker(t *testing.T) {
	t.Setenv("PATH", "/usr/bin:/bin")
	if resolveExecutable("bwrap") == "" {
		t.Skip("bwrap is required for the sandboxed failure and timeout test")
	}
	_, systemDir := isolatedThumbnailerDirs(t)
	writeThumbnailerEntry(t, systemDir, "failing", "[Thumbnailer Entry]\nExec=/usr/bin/sh -c 'echo boom >&2; exit 3' %i %o\nMimeType=video/x-failing;\n")
	writeThumbnailerEntry(t, systemDir, "hanging", "[Thumbnailer Entry]\nExec=/usr/bin/sh -c 'sleep 30' %i %o\nMimeType=video/x-hanging;\n")

	svc := NewService(&fakeBus{}, t.TempDir(), nil)
	t.Cleanup(svc.Close)
	svc.thumbs.limit = 200 * time.Millisecond

	source := filepath.Join(t.TempDir(), "clip.bin")
	require.NoError(t, os.WriteFile(source, []byte("x"), 0o644))
	entry, err := svc.Stat(source)
	require.NoError(t, err)

	entry.Mime = "video/x-failing"
	_, err = svc.thumbs.Generate(entry, "normal")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "boom")
	assert.True(t, svc.thumbs.Failed(source, entry.MtimeMs))

	entry.Mime = "video/x-hanging"
	started := time.Now()
	_, err = svc.thumbs.Generate(entry, "normal")
	require.Error(t, err)
	assert.Less(t, time.Since(started), 5*time.Second)
}

func TestBwrapArgsBindInputReadOnlyAndOutputDir(t *testing.T) {
	args := bwrapArgs("/usr/bin/bwrap", "/home/me/clip.mkv", "/tmp/work", "/home/me/.cache", "/usr/bin")
	assert.Equal(t, "/usr/bin/bwrap", args[0])
	assert.Equal(t, "--", args[len(args)-1])
	assert.Contains(t, joinArgs(args), "--ro-bind /home/me/clip.mkv /tmp/dfiles-input.mkv")
	assert.Contains(t, joinArgs(args), "--bind /tmp/work /tmp")
	assert.Contains(t, joinArgs(args), "--unshare-all --die-with-parent")
	assert.Contains(t, joinArgs(args), "--clearenv")
	assert.NotContains(t, joinArgs(args), "--bind /home/me ")
	custom := bwrapArgs("/usr/bin/bwrap", "/home/me/clip.mkv", "/tmp/work", "/home/me/.cache", "/home/me/.local/bin")
	assert.Contains(t, joinArgs(custom), "--ro-bind /home/me/.local/bin /home/me/.local/bin")
	assert.Contains(t, joinArgs(custom), "--dir /home/me")
}

func joinArgs(args []string) string {
	out := ""
	for _, arg := range args {
		out += arg + " "
	}
	return out
}
