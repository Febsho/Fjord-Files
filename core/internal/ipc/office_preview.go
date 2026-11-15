package ipc

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-files/core/internal/wire"
	"github.com/duxlabs-dev/dux-go/ipc/params"
)

const (
	officeInputLimit   = 64 << 20
	officeOutputLimit  = 64 << 20
	officeCacheLimit   = 256 << 20
	zipOfficeMetaLimit = 8 << 20
)

var officeSlots = make(chan struct{}, 1)

type officeBudgetReaderAt struct {
	reader    io.ReaderAt
	remaining int64
}

func (r *officeBudgetReaderAt) ReadAt(p []byte, offset int64) (int, error) {
	if int64(len(p)) > r.remaining {
		return 0, errors.New("office archive metadata exceeds preview limit")
	}
	n, err := r.reader.ReadAt(p, offset)
	r.remaining -= int64(n)
	return n, err
}

type officePreviewResult struct {
	Path string `json:"path"`
}

type officeTools struct {
	bwrap     string
	converter string
	root      string
}

func officeMimeFromZip(in *os.File, size int64) string {
	if size <= 0 {
		return ""
	}
	archive, err := zip.NewReader(&officeBudgetReaderAt{reader: in, remaining: zipOfficeMetaLimit}, size)
	if err != nil {
		return ""
	}
	for _, file := range archive.File {
		switch file.Name {
		case "mimetype":
			body, err := file.Open()
			if err != nil {
				return ""
			}
			data, readErr := io.ReadAll(io.LimitReader(body, 256))
			closeErr := body.Close()
			if readErr != nil || closeErr != nil {
				return ""
			}
			switch string(data) {
			case "application/vnd.oasis.opendocument.text":
				return "application/vnd.oasis.opendocument.text"
			case "application/vnd.oasis.opendocument.spreadsheet":
				return "application/vnd.oasis.opendocument.spreadsheet"
			case "application/vnd.oasis.opendocument.presentation":
				return "application/vnd.oasis.opendocument.presentation"
			}
		case "word/document.xml":
			return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
		case "xl/workbook.xml":
			return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
		case "ppt/presentation.xml":
			return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
		}
	}
	return ""
}

func officeMime(mime string) bool {
	switch mime {
	case "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
		"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		"application/vnd.openxmlformats-officedocument.presentationml.presentation",
		"application/vnd.oasis.opendocument.text",
		"application/vnd.oasis.opendocument.spreadsheet",
		"application/vnd.oasis.opendocument.presentation":
		return true
	default:
		return false
	}
}

func officeConverter() (officeTools, bool) {
	bwrap, err := exec.LookPath("bwrap")
	if err != nil {
		return officeTools{}, false
	}
	if !filepath.IsAbs(bwrap) {
		bwrap, err = filepath.Abs(bwrap)
		if err != nil {
			return officeTools{}, false
		}
	}
	if !underOfficeRuntime(bwrap) {
		return officeTools{}, false
	}
	customRoot, rootSet := os.LookupEnv("FJORD_OFFICE_RUNTIME_ROOT")
	customConverter, converterSet := os.LookupEnv("FJORD_OFFICE_CONVERTER")
	if rootSet || converterSet {
		if !rootSet || !converterSet || !filepath.IsAbs(customRoot) || !filepath.IsAbs(customConverter) {
			return officeTools{}, false
		}
		root, err := filepath.EvalSymlinks(customRoot)
		if err != nil {
			return officeTools{}, false
		}
		executable, err := filepath.EvalSymlinks(customConverter)
		if err != nil {
			return officeTools{}, false
		}
		info, err := os.Stat(executable)
		if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0111 == 0 {
			return officeTools{}, false
		}
		rel, err := filepath.Rel(root, executable)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
			return officeTools{}, false
		}
		return officeTools{bwrap: bwrap, converter: filepath.Join("/office-runtime", rel), root: root}, true
	}
	converter, err := exec.LookPath("libreoffice")
	if err != nil {
		converter, err = exec.LookPath("soffice")
	}
	if err != nil {
		return officeTools{}, false
	}
	if !filepath.IsAbs(converter) {
		converter, err = filepath.Abs(converter)
		if err != nil {
			return officeTools{}, false
		}
	}
	if !underOfficeRuntime(converter) {
		return officeTools{}, false
	}
	return officeTools{bwrap: bwrap, converter: converter}, true
}

func underOfficeRuntime(path string) bool {
	for _, root := range []string{"/usr", "/bin", "/opt"} {
		rel, err := filepath.Rel(root, path)
		if err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

func HandleOfficePreview(ctx context.Context, w *ConnWriter, req Request) {
	path := params.StringOpt(req.Params, "path", "")
	if !filepath.IsAbs(path) {
		wire.RespondError(w, req.ID, wire.Invalid("path is not an absolute path"))
		return
	}
	tools, ok := officeConverter()
	if !ok {
		w.RespondError(req.ID, "office preview requires LibreOffice and Bubblewrap")
		return
	}
	file, info, err := openRegular(path)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	defer file.Close()
	if info.Size() > officeInputLimit {
		w.RespondError(req.ID, "Office document exceeds the 64 MiB preview limit")
		return
	}
	mime := officeMimeFromZip(file, info.Size())
	if !officeMime(mime) {
		w.RespondError(req.ID, "file is not a supported Office document")
		return
	}
	result, err := convertOffice(ctx, file, path, info, mime, tools)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	w.Respond(req.ID, result)
}

func officeCacheKey(path string, info os.FileInfo) string {
	sum := sha256.Sum256([]byte(fmt.Sprintf("%s\x00%d\x00%d", path, info.Size(), info.ModTime().UnixNano())))
	return hex.EncodeToString(sum[:])
}

func officeExtension(mime string) string {
	switch mime {
	case "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
		return ".docx"
	case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
		return ".xlsx"
	case "application/vnd.openxmlformats-officedocument.presentationml.presentation":
		return ".pptx"
	case "application/vnd.oasis.opendocument.text":
		return ".odt"
	case "application/vnd.oasis.opendocument.spreadsheet":
		return ".ods"
	case "application/vnd.oasis.opendocument.presentation":
		return ".odp"
	default:
		return ""
	}
}

func convertOffice(ctx context.Context, source *os.File, path string, info os.FileInfo, mime string, tools officeTools) (officePreviewResult, error) {
	key := officeCacheKey(path, info)
	cacheRoot, err := os.UserCacheDir()
	if err != nil {
		return officePreviewResult{}, err
	}
	cacheDir := filepath.Join(cacheRoot, "fjord-files", "office-previews")
	if err := os.MkdirAll(cacheDir, 0700); err != nil {
		return officePreviewResult{}, err
	}
	cacheInfo, err := os.Lstat(cacheDir)
	if err != nil {
		return officePreviewResult{}, err
	}
	if !cacheInfo.IsDir() || cacheInfo.Mode()&os.ModeSymlink != 0 {
		return officePreviewResult{}, errors.New("office preview cache is not a private directory")
	}
	if err := os.Chmod(cacheDir, 0700); err != nil {
		return officePreviewResult{}, err
	}
	final := filepath.Join(cacheDir, key+".pdf")
	if validOfficePDF(final) {
		return officePreviewResult{Path: final}, nil
	}
	select {
	case officeSlots <- struct{}{}:
		defer func() { <-officeSlots }()
	case <-ctx.Done():
		return officePreviewResult{}, ctx.Err()
	}
	if validOfficePDF(final) {
		return officePreviewResult{Path: final}, nil
	}
	if err := removeInvalidOfficePDF(final); err != nil {
		return officePreviewResult{}, err
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	work, err := os.MkdirTemp(cacheDir, ".office-")
	if err != nil {
		return officePreviewResult{}, err
	}
	defer os.RemoveAll(work)
	inputDir, outputDir := filepath.Join(work, "input"), filepath.Join(work, "output")
	if err := os.Mkdir(inputDir, 0700); err != nil {
		return officePreviewResult{}, err
	}
	if err := os.Mkdir(outputDir, 0700); err != nil {
		return officePreviewResult{}, err
	}
	ext := officeExtension(mime)
	input := filepath.Join(inputDir, "source"+ext)
	out, err := os.OpenFile(input, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0400)
	if err != nil {
		return officePreviewResult{}, err
	}
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		out.Close()
		return officePreviewResult{}, err
	}
	n, copyErr := io.Copy(out, io.LimitReader(source, officeInputLimit+1))
	closeErr := out.Close()
	if copyErr != nil {
		return officePreviewResult{}, copyErr
	}
	if closeErr != nil {
		return officePreviewResult{}, closeErr
	}
	if n != info.Size() || n > officeInputLimit {
		return officePreviewResult{}, errors.New("office document changed while preparing preview")
	}

	args := []string{"--die-with-parent", "--new-session", "--unshare-all"}
	for _, root := range []string{"/usr", "/etc", "/bin", "/lib", "/lib64", "/opt"} {
		if _, err := os.Stat(root); err == nil {
			args = append(args, "--ro-bind-try", root, root)
		}
	}
	if tools.root != "" {
		args = append(args, "--dir", "/office-runtime", "--ro-bind", tools.root, "/office-runtime")
	}
	args = append(args,
		"--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
		"--dir", "/input", "--dir", "/out",
		"--ro-bind", inputDir, "/input",
		"--bind", outputDir, "/out",
		"--chdir", "/tmp",
		"--clearenv",
		"--setenv", "HOME", "/tmp",
		"--setenv", "TMPDIR", "/tmp",
		"--setenv", "XDG_CONFIG_HOME", "/tmp/config",
		"--setenv", "XDG_CACHE_HOME", "/tmp/cache",
		"--setenv", "XDG_DATA_HOME", "/tmp/data",
		"--setenv", "LANG", "C.UTF-8",
		"--", tools.converter,
		"-env:UserInstallation=file:///tmp/profile",
		"--headless", "--convert-to", "pdf", "--outdir", "/out", "/input/"+filepath.Base(input),
	)
	cmd := exec.CommandContext(ctx, tools.bwrap, args...)
	stdout, stderr := &boundedOutput{}, &boundedOutput{}
	cmd.Stdout, cmd.Stderr = stdout, stderr
	if err := cmd.Run(); err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return officePreviewResult{}, errors.New("office preview timed out after 60 seconds")
		}
		detail := strings.TrimSpace(stderr.String())
		if detail == "" {
			detail = strings.TrimSpace(stdout.String())
		}
		if detail != "" {
			return officePreviewResult{}, fmt.Errorf("libreoffice conversion failed: %w: %s", err, detail)
		}
		return officePreviewResult{}, fmt.Errorf("libreoffice conversion failed: %w", err)
	}
	converted := filepath.Join(outputDir, "source.pdf")
	convertedInfo, err := os.Lstat(converted)
	if err != nil || !convertedInfo.Mode().IsRegular() || convertedInfo.Size() < 8 || convertedInfo.Size() > officeOutputLimit {
		return officePreviewResult{}, errors.New("libreoffice did not produce a valid PDF within the preview limit")
	}
	if !validOfficePDF(converted) {
		return officePreviewResult{}, errors.New("libreoffice output is not a PDF")
	}
	if err := trimOfficeCache(cacheDir, convertedInfo.Size()); err != nil {
		return officePreviewResult{}, err
	}
	if err := os.Link(converted, final); err != nil && !errors.Is(err, os.ErrExist) {
		return officePreviewResult{}, err
	}
	if !validOfficePDF(final) {
		return officePreviewResult{}, errors.New("cached office preview is invalid")
	}
	return officePreviewResult{Path: final}, nil
}

type boundedOutput struct{ bytes.Buffer }

func (b *boundedOutput) Write(p []byte) (int, error) {
	const limit = 64 << 10
	if b.Len() < limit {
		_, _ = b.Buffer.Write(p[:min(len(p), limit-b.Len())])
	}
	return len(p), nil
}

func validOfficePDF(path string) bool {
	file, _, err := openRegular(path)
	if err != nil {
		return false
	}
	defer file.Close()
	var header [5]byte
	n, err := file.ReadAt(header[:], 0)
	return n == len(header) && err == nil && string(header[:]) == "%PDF-"
}

func removeInvalidOfficePDF(path string) error {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return errors.New("office preview cache entry is not a regular file")
	}
	return os.Remove(path)
}

func trimOfficeCache(dir string, incoming int64) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	type cached struct {
		path string
		info os.FileInfo
	}
	files := make([]cached, 0, len(entries))
	var total int64
	for _, entry := range entries {
		name := strings.TrimSuffix(entry.Name(), ".pdf")
		if len(name) != sha256.Size*2 {
			continue
		}
		if _, err := hex.DecodeString(name); err != nil {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		info, err := os.Lstat(path)
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		total += info.Size()
		files = append(files, cached{path: path, info: info})
	}
	sort.Slice(files, func(i, j int) bool { return files[i].info.ModTime().Before(files[j].info.ModTime()) })
	for _, file := range files {
		if total+incoming <= officeCacheLimit {
			break
		}
		if err := os.Remove(file.path); err != nil {
			return err
		}
		total -= file.info.Size()
	}
	if total+incoming > officeCacheLimit {
		return errors.New("office preview cache is full")
	}
	return nil
}
