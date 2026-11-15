package ipc

import (
	"context"
	"io"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-files/core/internal/fileops"
	"github.com/duxlabs-dev/dux-files/core/internal/mimeapps"
	"github.com/duxlabs-dev/dux-files/core/internal/wire"
	"github.com/duxlabs-dev/dux-go/ipc/params"
)

type viewerResult struct {
	Mime   string `json:"mime"`
	Viewer string `json:"viewer"`
}

type viewerRule struct {
	id      string
	matches func(string) bool
}

var internalViewers = []viewerRule{
	{"pdf", func(m string) bool { return m == "application/pdf" }},
	{"image", func(m string) bool { return strings.HasPrefix(m, "image/") }},
	{"media", func(m string) bool { return strings.HasPrefix(m, "audio/") || strings.HasPrefix(m, "video/") }},
	{"office", officeMime},
	{"text", func(m string) bool {
		switch m {
		case "application/json", "application/xml", "application/javascript", "application/x-shellscript", "application/yaml":
			return true
		}
		return strings.HasPrefix(m, "text/") || strings.HasSuffix(m, "+xml") || strings.HasSuffix(m, "+json")
	}},
}

func viewerFor(mime string) string {
	for _, viewer := range internalViewers {
		if viewer.matches(mime) {
			return viewer.id
		}
	}
	return ""
}

func HandleViewerFor(_ context.Context, w *ConnWriter, req Request, deps Deps) {
	path := params.StringOpt(req.Params, "path", "")
	if !filepath.IsAbs(path) {
		wire.RespondError(w, req.ID, wire.Invalid("path is not an absolute path"))
		return
	}
	if deps.Apps == nil {
		w.RespondError(req.ID, "application service unavailable")
		return
	}
	result, err := detectViewer(path, deps.Apps.Detector())
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	w.Respond(req.ID, result)
}

func detectViewer(path string, detector *mimeapps.Detector) (viewerResult, error) {
	file, info, err := openRegular(path)
	if err != nil {
		return viewerResult{}, err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, int64(min(max(detector.SniffExtent(), 262), 256*1024))))
	if err != nil {
		return viewerResult{}, err
	}
	mime := detector.SniffData(data)
	if mime == "application/zip" {
		if officeType := officeMimeFromZip(file, info.Size()); officeType != "" {
			mime = officeType
		}
	}
	viewer := viewerFor(mime)
	if viewer == "office" {
		if _, available := officeConverter(); !available {
			viewer = ""
		}
	}
	if fileops.BrowsableArchive(data) && !officeMime(mime) {
		viewer = "archive"
	}
	return viewerResult{Mime: mime, Viewer: viewer}, nil
}

func HandleArchiveList(_ context.Context, w *ConnWriter, req Request) {
	path := params.StringOpt(req.Params, "path", "")
	if !filepath.IsAbs(path) {
		wire.RespondError(w, req.ID, wire.Invalid("path is not an absolute path"))
		return
	}
	f, _, err := openRegular(path)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	defer f.Close()
	result, err := fileops.ListArchive(f, path)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	w.Respond(req.ID, result)
}
