package ipc

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/duxlabs-dev/dux-files/core/internal/wire"
	"github.com/duxlabs-dev/dux-go/ipc/params"
)

const editorMaxBytes = 256 * 1024

type editorDocument struct {
	Text     string `json:"text"`
	Revision string `json:"revision"`
	Path     string `json:"path,omitempty"`
}

func editorRead(path string) (editorDocument, os.FileInfo, error) {
	if !filepath.IsAbs(path) {
		return editorDocument{}, nil, errors.New("path is not an absolute path")
	}
	info, err := os.Lstat(path)
	if err != nil {
		return editorDocument{}, nil, err
	}
	if !info.Mode().IsRegular() {
		return editorDocument{}, nil, errors.New("editing requires a regular file, not a link")
	}
	f, opened, err := openRegular(path)
	if err != nil {
		return editorDocument{}, nil, err
	}
	defer f.Close()
	if !os.SameFile(info, opened) {
		return editorDocument{}, nil, errors.New("file changed while opening")
	}
	data, err := io.ReadAll(io.LimitReader(f, editorMaxBytes+1))
	if err != nil {
		return editorDocument{}, nil, err
	}
	if len(data) > editorMaxBytes {
		return editorDocument{}, nil, errors.New("file is too large to edit")
	}
	if bytes.ContainsAny(data, "\x00\r") || !utf8.Valid(data) || bytes.Contains(data, []byte("\u2028")) || bytes.Contains(data, []byte("\u2029")) {
		return editorDocument{}, nil, errors.New("file is not supported UTF-8 text (only LF line endings are supported)")
	}
	sum := sha256.Sum256(data)
	return editorDocument{Text: string(data), Revision: hex.EncodeToString(sum[:])}, opened, nil
}

func editorSave(path, revision, text string) (editorDocument, error) {
	if len(text) > editorMaxBytes || !utf8.ValidString(text) || strings.ContainsAny(text, "\x00\r\u2028\u2029") {
		return editorDocument{}, errors.New("text is invalid or too large to save")
	}
	current, _, err := editorRead(path)
	if err != nil {
		return editorDocument{}, err
	}
	if revision == "" || current.Revision != revision {
		return editorDocument{}, errors.New("file changed on disk; save cancelled")
	}
	var file *os.File
	var target string
	for i := 0; i < 10000; i++ {
		target = path + ".edited"
		if i > 0 {
			target = fmt.Sprintf("%s.edited.%d", path, i)
		}
		file, err = os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if errors.Is(err, os.ErrExist) {
			continue
		}
		if err != nil {
			return editorDocument{}, err
		}
		break
	}
	if file == nil {
		return editorDocument{}, errors.New("could not find an unused name for edited file")
	}
	if _, err = io.WriteString(file, text); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return editorDocument{}, fmt.Errorf("could not finish saving %s: %w", target, err)
	}
	sum := sha256.Sum256([]byte(text))
	return editorDocument{Text: text, Revision: hex.EncodeToString(sum[:]), Path: target}, nil
}

func editorRevision(path string) (string, error) {
	document, _, err := editorRead(path)
	if err != nil {
		return "", err
	}
	return document.Revision, nil
}

func HandleTextEditor(_ context.Context, w *ConnWriter, req Request) {
	path := params.StringOpt(req.Params, "path", "")
	var result editorDocument
	var err error
	switch req.Method {
	case "files.textRead":
		result, _, err = editorRead(path)
	case "files.textRevision":
		var revision string
		revision, err = editorRevision(path)
		if err == nil {
			w.Respond(req.ID, map[string]string{"revision": revision})
			return
		}
	case "files.textSave":
		text, ok := req.Params["text"].(string)
		if !ok {
			err = fmt.Errorf("text must be a string")
			break
		}
		result, err = editorSave(path, params.StringOpt(req.Params, "revision", ""), text)
	}
	if err != nil {
		wire.RespondError(w, req.ID, err)
		return
	}
	w.Respond(req.ID, result)
}
