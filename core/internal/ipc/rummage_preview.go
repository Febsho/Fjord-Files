package ipc

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-files/core/internal/wire"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"golang.org/x/sys/unix"
)

const rummageMaxDimension = 1024

var rummageSlots = make(chan struct{}, 2)

// HandleRummagePreview uses the explicitly configured Rummage protocol 4 helper.
func HandleRummagePreview(ctx context.Context, w *ConnWriter, req Request) {
	path := params.StringOpt(req.Params, "path", "")
	if !filepath.IsAbs(path) {
		wire.RespondError(w, req.ID, wire.Invalid("path is not an absolute path"))
		return
	}
	width := params.IntOpt(req.Params, "maxWidth", 1024)
	height := params.IntOpt(req.Params, "maxHeight", 1024)
	if width < 1 || height < 1 || width > rummageMaxDimension || height > rummageMaxDimension {
		wire.RespondError(w, req.ID, wire.Invalid("preview dimensions must be between 1 and 1024"))
		return
	}
	file, _, err := openRegular(path)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	defer file.Close()
	helper := os.Getenv("FJORD_RUMMAGE_PREVIEW_V4")
	if !filepath.IsAbs(helper) {
		w.RespondError(req.ID, "Rummage protocol 4 helper is not configured")
		return
	}
	preview, err := rummagePicture(ctx, helper, file, width, height)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	w.Respond(req.ID, preview)
}

type rummagePreviewResult struct {
	URL        string      `json:"url"`
	Width      int         `json:"width"`
	Height     int         `json:"height"`
	FullWidth  uint32      `json:"fullWidth"`
	FullHeight uint32      `json:"fullHeight"`
	Image      image.Image `json:"-"`
}

func rummagePicture(ctx context.Context, helper string, file *os.File, width, height int) (rummagePreviewResult, error) {
	select {
	case rummageSlots <- struct{}{}:
		defer func() { <-rummageSlots }()
	case <-ctx.Done():
		return rummagePreviewResult{}, ctx.Err()
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	pair, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_SEQPACKET|unix.SOCK_CLOEXEC, 0)
	if err != nil {
		return rummagePreviewResult{}, err
	}
	parent := os.NewFile(uintptr(pair[0]), "rummage-parent")
	child := os.NewFile(uintptr(pair[1]), "rummage-child")
	defer parent.Close()
	timeout := unix.NsecToTimeval((15 * time.Second).Nanoseconds())
	if err := unix.SetsockoptTimeval(int(parent.Fd()), unix.SOL_SOCKET, unix.SO_RCVTIMEO, &timeout); err != nil {
		child.Close()
		return rummagePreviewResult{}, err
	}
	cmd := exec.CommandContext(ctx, helper, "--idle-ms", "1000")
	cmd.ExtraFiles = []*os.File{child}
	// The reporting mode weakens the filter's response to unexpected syscalls.
	cmd.Env = withoutEnvironment(os.Environ(), "RUMMAGE_SANDBOX_REPORT")
	cmd.Env = append(cmd.Env, "RUMMAGE_SANDBOX_REPORT=0")
	if err := cmd.Start(); err != nil {
		child.Close()
		return rummagePreviewResult{}, err
	}
	child.Close()
	defer func() { parent.Close(); _ = cmd.Wait() }()
	// Closing the socket on cancellation also interrupts recvmsg.
	stop := context.AfterFunc(ctx, func() { parent.Close() })
	defer stop()
	request := make([]byte, 16)
	binary.NativeEndian.PutUint32(request[0:4], 0x4e505251)
	binary.NativeEndian.PutUint32(request[8:12], uint32(width))
	binary.NativeEndian.PutUint32(request[12:16], uint32(height))
	if err := unix.Sendmsg(int(parent.Fd()), request, unix.UnixRights(int(file.Fd())), nil, 0); err != nil {
		return rummagePreviewResult{}, fmt.Errorf("rummage request: %w", err)
	}
	packet := make([]byte, 8192)
	oob := make([]byte, unix.CmsgSpace(4*8))
	n, oobn, flags, _, err := unix.Recvmsg(int(parent.Fd()), packet, oob, unix.MSG_CMSG_CLOEXEC)
	if err != nil {
		return rummagePreviewResult{}, fmt.Errorf("rummage response: %w", err)
	}
	messages, err := unix.ParseSocketControlMessage(oob[:oobn])
	if err != nil {
		return rummagePreviewResult{}, errors.New("invalid Rummage descriptors")
	}
	var fds []int
	for _, message := range messages {
		rights, err := unix.ParseUnixRights(&message)
		if err != nil {
			continue
		}
		fds = append(fds, rights...)
	}
	defer func() {
		for _, fd := range fds {
			unix.Close(fd)
		}
	}()
	if flags&(unix.MSG_TRUNC|unix.MSG_CTRUNC) != 0 || n < 24 || binary.NativeEndian.Uint32(packet[:4]) != 0x4e505253 {
		return rummagePreviewResult{}, errors.New("invalid Rummage response")
	}
	detailLen := int(binary.NativeEndian.Uint16(packet[6:8]))
	if detailLen > 1024 || n != 24+detailLen {
		return rummagePreviewResult{}, errors.New("invalid Rummage response length")
	}
	if packet[4] != 0 {
		return rummagePreviewResult{}, errors.New("rummage could not decode the image")
	}
	w := binary.NativeEndian.Uint32(packet[8:12])
	h := binary.NativeEndian.Uint32(packet[12:16])
	if w == 0 || h == 0 || w > uint32(width) || h > uint32(height) || len(fds) != 1 {
		return rummagePreviewResult{}, errors.New("invalid Rummage image dimensions or descriptor")
	}
	seals, err := unix.FcntlInt(uintptr(fds[0]), unix.F_GET_SEALS, 0)
	const requiredSeals = unix.F_SEAL_SEAL | unix.F_SEAL_SHRINK | unix.F_SEAL_GROW | unix.F_SEAL_WRITE
	if err != nil || seals&requiredSeals != requiredSeals {
		return rummagePreviewResult{}, errors.New("unsealed Rummage image")
	}
	var stat unix.Stat_t
	if err := unix.Fstat(fds[0], &stat); err != nil || stat.Size != int64(w)*int64(h)*4 {
		return rummagePreviewResult{}, errors.New("invalid Rummage image size")
	}
	pixels := make([]byte, int(w)*int(h)*4)
	if n, err := unix.Pread(fds[0], pixels, 0); err != nil || n != len(pixels) {
		return rummagePreviewResult{}, errors.New("short Rummage image")
	}
	img := &image.NRGBA{Pix: pixels, Stride: int(w) * 4, Rect: image.Rect(0, 0, int(w), int(h))}
	var out bytes.Buffer
	if err := png.Encode(&out, img); err != nil {
		return rummagePreviewResult{}, err
	}
	return rummagePreviewResult{URL: "data:image/png;base64," + base64.StdEncoding.EncodeToString(out.Bytes()), Width: int(w), Height: int(h), FullWidth: binary.NativeEndian.Uint32(packet[16:20]), FullHeight: binary.NativeEndian.Uint32(packet[20:24]), Image: img}, nil
}

// ImageThumbnailDecoder uses the explicitly configured Rummage helper for
// cached image thumbnails, falling back to Fjord's isolated decoder when the
// helper is unavailable or does not support the source format.
func ImageThumbnailDecoder() func(path string, bound int) (image.Image, error) {
	helper := strings.TrimSpace(os.Getenv("FJORD_RUMMAGE_PREVIEW_V4"))
	if !filepath.IsAbs(helper) {
		return DecodeImageThumbnailIsolated
	}
	info, err := os.Stat(helper)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return DecodeImageThumbnailIsolated
	}
	return func(path string, bound int) (image.Image, error) {
		img, rummageErr := decodeRummageThumbnail(helper, path, bound)
		if rummageErr == nil {
			return img, nil
		}
		return DecodeImageThumbnailIsolated(path, bound)
	}
}

func decodeRummageThumbnail(helper, path string, bound int) (image.Image, error) {
	if bound < 1 || bound > rummageMaxDimension {
		return nil, errors.New("thumbnail dimensions must be between 1 and 1024")
	}
	file, _, err := openRegular(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	result, err := rummagePicture(context.Background(), helper, file, bound, bound)
	if err != nil {
		return nil, err
	}
	return result.Image, nil
}

func withoutEnvironment(env []string, name string) []string {
	filtered := make([]string, 0, len(env))
	for _, item := range env {
		key, _, _ := strings.Cut(item, "=")
		if key != name {
			filtered = append(filtered, item)
		}
	}
	return filtered
}
