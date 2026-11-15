package ipc

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/draw"
	"image/png"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-files/core/internal/wire"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	_ "golang.org/x/image/bmp"
	xdraw "golang.org/x/image/draw"
	_ "golang.org/x/image/tiff"
	_ "golang.org/x/image/webp"
)

const imageExportMaxPixels = 60_000_000
const imagePreviewMaxDimension = 1024
const imagePreviewMaxBytes = 8 << 20

var imageWorkerSlots = make(chan struct{}, 1)
var imageWorkerCommand = func(ctx context.Context, executable string, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, executable, args...)
}

type imageExportResult struct {
	Path   string `json:"path"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

func HandleImageExport(ctx context.Context, w *ConnWriter, req Request) {
	select {
	case imageWorkerSlots <- struct{}{}:
		defer func() { <-imageWorkerSlots }()
	case <-ctx.Done():
		wire.RespondError(w, req.ID, ctx.Err())
		return
	}
	result, err := exportImageIsolated(ctx, req.Params)
	if err != nil {
		wire.RespondError(w, req.ID, err)
		return
	}
	w.Respond(req.ID, result)
}

type imageWorkerRequest struct {
	Preview   bool `json:"preview,omitempty"`
	MaxWidth  int  `json:"maxWidth,omitempty"`
	MaxHeight int  `json:"maxHeight,omitempty"`
	X         *int `json:"x,omitempty"`
	Y         *int `json:"y,omitempty"`
	Width     *int `json:"width,omitempty"`
	Height    *int `json:"height,omitempty"`
	Angle     int  `json:"angle"`
	Mirror    bool `json:"mirror"`
}

type imageWorkerResult struct {
	Width      int  `json:"width"`
	Height     int  `json:"height"`
	FullWidth  int  `json:"fullWidth,omitempty"`
	FullHeight int  `json:"fullHeight,omitempty"`
	Sandboxed  bool `json:"sandboxed"`
}

type isolatedImagePreview struct {
	URL        string `json:"url"`
	Width      int    `json:"width"`
	Height     int    `json:"height"`
	FullWidth  int    `json:"fullWidth"`
	FullHeight int    `json:"fullHeight"`
}

func HandleImagePreview(ctx context.Context, w *ConnWriter, req Request) {
	select {
	case imageWorkerSlots <- struct{}{}:
		defer func() { <-imageWorkerSlots }()
	case <-ctx.Done():
		wire.RespondError(w, req.ID, ctx.Err())
		return
	}
	result, err := previewImageIsolated(ctx, req.Params)
	if err != nil {
		wire.RespondError(w, req.ID, err)
		return
	}
	w.Respond(req.ID, result)
}

func previewImageIsolated(ctx context.Context, values map[string]any) (isolatedImagePreview, error) {
	path := params.StringOpt(values, "path", "")
	if !filepath.IsAbs(path) {
		return isolatedImagePreview{}, errors.New("image path must be absolute")
	}
	width := params.IntOpt(values, "maxWidth", imagePreviewMaxDimension)
	height := params.IntOpt(values, "maxHeight", imagePreviewMaxDimension)
	if width < 1 || height < 1 || width > imagePreviewMaxDimension || height > imagePreviewMaxDimension {
		return isolatedImagePreview{}, errors.New("preview dimensions must be between 1 and 1024")
	}
	path = filepath.Clean(path)
	before, err := os.Lstat(path)
	if err != nil {
		return isolatedImagePreview{}, err
	}
	if !before.Mode().IsRegular() {
		return isolatedImagePreview{}, errors.New("image preview requires a regular file, not a link")
	}
	input, opened, err := openRegular(path)
	if err != nil {
		return isolatedImagePreview{}, err
	}
	defer input.Close()
	if !os.SameFile(before, opened) {
		return isolatedImagePreview{}, errors.New("image changed while opening")
	}
	if opened.Size() > 512<<20 {
		return isolatedImagePreview{}, errors.New("image file exceeds the 512 MiB preview limit")
	}
	tempDir, err := os.MkdirTemp("", "fjord-image-preview-")
	if err != nil {
		return isolatedImagePreview{}, err
	}
	defer os.RemoveAll(tempDir)
	output, err := os.OpenFile(filepath.Join(tempDir, "preview.png"), os.O_CREATE|os.O_EXCL|os.O_RDWR, 0o600)
	if err != nil {
		return isolatedImagePreview{}, err
	}
	defer output.Close()
	requestData, err := json.Marshal(imageWorkerRequest{Preview: true, MaxWidth: width, MaxHeight: height})
	if err != nil {
		return isolatedImagePreview{}, err
	}
	executable, err := os.Executable()
	if err != nil {
		return isolatedImagePreview{}, err
	}
	workerCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	command := imageWorkerCommand(workerCtx, executable, "--image-export-worker")
	command.Stdin = bytes.NewReader(requestData)
	command.ExtraFiles = []*os.File{input, output}
	var stdout, stderr cappedBuffer
	stdout.limit = 4096
	stderr.limit = 4096
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		if stderr.Len() > 0 {
			return isolatedImagePreview{}, fmt.Errorf("image preview helper: %s", strings.TrimSpace(stderr.String()))
		}
		return isolatedImagePreview{}, fmt.Errorf("image preview helper failed: %w", err)
	}
	if err := imageStillMatches(path, opened); err != nil {
		return isolatedImagePreview{}, err
	}
	if err := output.Sync(); err != nil {
		return isolatedImagePreview{}, err
	}
	if _, err := output.Seek(0, io.SeekStart); err != nil {
		return isolatedImagePreview{}, err
	}
	pngData, err := io.ReadAll(io.LimitReader(output, imagePreviewMaxBytes+1))
	if err != nil {
		return isolatedImagePreview{}, err
	}
	if len(pngData) == 0 || len(pngData) > imagePreviewMaxBytes {
		return isolatedImagePreview{}, errors.New("image preview output exceeds the 8 MiB limit")
	}
	var result imageWorkerResult
	if err := json.Unmarshal(stdout.Bytes(), &result); err != nil {
		return isolatedImagePreview{}, fmt.Errorf("invalid image preview helper response: %w", err)
	}
	if !result.Sandboxed || result.Width <= 0 || result.Height <= 0 || result.FullWidth <= 0 || result.FullHeight <= 0 || result.Width > width || result.Height > height {
		return isolatedImagePreview{}, errors.New("image preview helper returned invalid dimensions or did not confirm its sandbox")
	}
	return isolatedImagePreview{
		URL:   "data:image/png;base64," + base64.StdEncoding.EncodeToString(pngData),
		Width: result.Width, Height: result.Height,
		FullWidth: result.FullWidth, FullHeight: result.FullHeight,
	}, nil
}

// DecodeImageThumbnailIsolated returns bounded PNG pixels from the same short-
// lived, seccomp-confined worker used by the large image viewer.
func DecodeImageThumbnailIsolated(path string, bound int) (image.Image, error) {
	if bound < 1 || bound > imagePreviewMaxDimension {
		return nil, errors.New("thumbnail dimensions must be between 1 and 1024")
	}
	result, err := previewImageIsolated(context.Background(), map[string]any{
		"path": path, "maxWidth": bound, "maxHeight": bound,
	})
	if err != nil {
		return nil, err
	}
	const prefix = "data:image/png;base64,"
	encoded, ok := strings.CutPrefix(result.URL, prefix)
	if !ok {
		return nil, errors.New("isolated thumbnail worker returned an invalid image URL")
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("decode isolated thumbnail output: %w", err)
	}
	decoded, err := png.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("read isolated thumbnail PNG: %w", err)
	}
	return decoded, nil
}

func exportImageIsolated(ctx context.Context, values map[string]any) (imageExportResult, error) {
	source := params.StringOpt(values, "path", "")
	destination := params.StringOpt(values, "destination", "")
	if !filepath.IsAbs(source) || !filepath.IsAbs(destination) {
		return imageExportResult{}, errors.New("source and destination must be absolute paths")
	}
	source = filepath.Clean(source)
	destination = filepath.Clean(destination)
	if filepath.Dir(source) != filepath.Dir(destination) || filepath.Base(source) == filepath.Base(destination) {
		return imageExportResult{}, errors.New("image export must use a new name in the source folder")
	}
	if !strings.EqualFold(filepath.Ext(destination), ".png") || filepath.Base(destination) == "." {
		return imageExportResult{}, errors.New("image export destination must end in .png")
	}
	sourceInfo, err := os.Lstat(source)
	if err != nil {
		return imageExportResult{}, err
	}
	if !sourceInfo.Mode().IsRegular() {
		return imageExportResult{}, errors.New("image export requires a regular file, not a link")
	}
	input, opened, err := openRegular(source)
	if err != nil {
		return imageExportResult{}, err
	}
	defer input.Close()
	if !os.SameFile(sourceInfo, opened) {
		return imageExportResult{}, errors.New("image changed while opening")
	}
	if opened.Size() > 512<<20 {
		return imageExportResult{}, errors.New("image file exceeds the 512 MiB export limit")
	}
	temporary, err := os.CreateTemp(filepath.Dir(destination), ".fjord-image-export-*")
	if err != nil {
		return imageExportResult{}, err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	request := imageWorkerRequest{
		X: optionalImageInt(values, "x"), Y: optionalImageInt(values, "y"),
		Width: optionalImageInt(values, "width"), Height: optionalImageInt(values, "height"),
		Angle: params.IntOpt(values, "angle", 0), Mirror: params.BoolOpt(values, "mirror", false),
	}
	requestData, err := json.Marshal(request)
	if err != nil {
		_ = temporary.Close()
		return imageExportResult{}, err
	}
	executable, err := os.Executable()
	if err != nil {
		_ = temporary.Close()
		return imageExportResult{}, err
	}
	command := imageWorkerCommand(ctx, executable, "--image-export-worker")
	command.Stdin = bytes.NewReader(requestData)
	command.ExtraFiles = []*os.File{input, temporary}
	var stdout, stderr cappedBuffer
	stdout.limit = 4096
	stderr.limit = 4096
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		_ = temporary.Close()
		if stderr.Len() > 0 {
			return imageExportResult{}, fmt.Errorf("image export helper: %s", strings.TrimSpace(stderr.String()))
		}
		return imageExportResult{}, fmt.Errorf("image export helper failed: %w", err)
	}
	if err := imageStillMatches(source, opened); err != nil {
		_ = temporary.Close()
		return imageExportResult{}, err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return imageExportResult{}, err
	}
	if err := temporary.Close(); err != nil {
		return imageExportResult{}, err
	}
	var workerResult imageWorkerResult
	if err := json.Unmarshal(stdout.Bytes(), &workerResult); err != nil {
		return imageExportResult{}, fmt.Errorf("invalid image export helper response: %w", err)
	}
	if !workerResult.Sandboxed || workerResult.Width <= 0 || workerResult.Height <= 0 {
		return imageExportResult{}, errors.New("image export helper did not confirm its sandbox")
	}
	if err := os.Link(temporaryPath, destination); err != nil {
		return imageExportResult{}, err
	}
	return imageExportResult{Path: destination, Width: workerResult.Width, Height: workerResult.Height}, nil
}

func optionalImageInt(values map[string]any, key string) *int {
	if _, ok := values[key]; !ok {
		return nil
	}
	value := params.IntOpt(values, key, 0)
	return &value
}

type cappedBuffer struct {
	bytes.Buffer
	limit int
}

func (b *cappedBuffer) Write(data []byte) (int, error) {
	if len(data) > b.limit-b.Len() {
		return 0, errors.New("image export helper output limit exceeded")
	}
	return b.Buffer.Write(data)
}

func RunImageExportWorkerFromProcess() error {
	source := os.NewFile(3, "image-source")
	if source == nil {
		return errors.New("image source descriptor is missing")
	}
	defer source.Close()
	output := os.NewFile(4, "image-output")
	if output == nil {
		return errors.New("image output descriptor is missing")
	}
	defer output.Close()
	return runImageExportWorker(os.Stdin, source, output, os.Stdout)
}

func runImageExportWorker(input io.Reader, source, output *os.File, response io.Writer) error {
	var request imageWorkerRequest
	decoder := json.NewDecoder(input)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		return err
	}
	if err := lockImageWorker(); err != nil {
		return err
	}
	info, err := source.Stat()
	if err != nil {
		return err
	}
	values := map[string]any{"angle": request.Angle, "mirror": request.Mirror}
	if request.X != nil {
		values["x"] = *request.X
	}
	if request.Y != nil {
		values["y"] = *request.Y
	}
	if request.Width != nil {
		values["width"] = *request.Width
	}
	if request.Height != nil {
		values["height"] = *request.Height
	}
	var transformed *image.NRGBA
	var fullWidth, fullHeight int
	if request.Preview {
		if request.MaxWidth < 1 || request.MaxWidth > imagePreviewMaxDimension || request.MaxHeight < 1 || request.MaxHeight > imagePreviewMaxDimension {
			return errors.New("preview dimensions must be between 1 and 1024")
		}
		transformed, fullWidth, fullHeight, err = decodePreviewImage(source, info.Size(), request.MaxWidth, request.MaxHeight)
	} else {
		transformed, err = decodeAndTransformImage(source, info.Size(), values)
	}
	if err != nil {
		return err
	}
	if err := png.Encode(output, transformed); err != nil {
		return err
	}
	if err := output.Sync(); err != nil {
		return err
	}
	result := imageWorkerResult{Width: transformed.Bounds().Dx(), Height: transformed.Bounds().Dy(), FullWidth: fullWidth, FullHeight: fullHeight, Sandboxed: true}
	return json.NewEncoder(response).Encode(result)
}

func decodePreviewImage(file *os.File, size int64, maxWidth, maxHeight int) (*image.NRGBA, int, int, error) {
	full, err := decodeAndTransformImage(file, size, nil)
	if err != nil {
		return nil, 0, 0, err
	}
	width, height := full.Bounds().Dx(), full.Bounds().Dy()
	ratio := min(float64(maxWidth)/float64(width), float64(maxHeight)/float64(height), 1)
	previewWidth := max(1, int(float64(width)*ratio))
	previewHeight := max(1, int(float64(height)*ratio))
	if previewWidth == width && previewHeight == height {
		return full, width, height, nil
	}
	preview := image.NewNRGBA(image.Rect(0, 0, previewWidth, previewHeight))
	xdraw.CatmullRom.Scale(preview, preview.Bounds(), full, full.Bounds(), xdraw.Over, nil)
	return preview, width, height, nil
}

func exportImage(values map[string]any) (imageExportResult, error) {
	source := params.StringOpt(values, "path", "")
	destination := params.StringOpt(values, "destination", "")
	if !filepath.IsAbs(source) || !filepath.IsAbs(destination) {
		return imageExportResult{}, errors.New("source and destination must be absolute paths")
	}
	source = filepath.Clean(source)
	destination = filepath.Clean(destination)
	if filepath.Dir(source) != filepath.Dir(destination) || filepath.Base(source) == filepath.Base(destination) {
		return imageExportResult{}, errors.New("image export must use a new name in the source folder")
	}
	if !strings.EqualFold(filepath.Ext(destination), ".png") || filepath.Base(destination) == "." {
		return imageExportResult{}, errors.New("image export destination must end in .png")
	}

	sourceInfo, err := os.Lstat(source)
	if err != nil {
		return imageExportResult{}, err
	}
	if !sourceInfo.Mode().IsRegular() {
		return imageExportResult{}, errors.New("image export requires a regular file, not a link")
	}
	file, info, err := openRegular(source)
	if err != nil {
		return imageExportResult{}, err
	}
	defer file.Close()
	if !os.SameFile(sourceInfo, info) {
		return imageExportResult{}, errors.New("image changed while opening")
	}
	if info.Size() > 512<<20 {
		return imageExportResult{}, errors.New("image file exceeds the 512 MiB export limit")
	}
	resultImage, err := decodeAndTransformImage(file, info.Size(), values)
	if err != nil {
		return imageExportResult{}, err
	}
	if err := imageStillMatches(source, info); err != nil {
		return imageExportResult{}, err
	}

	output, err := os.CreateTemp(filepath.Dir(destination), ".fjord-image-export-*")
	if err != nil {
		return imageExportResult{}, err
	}
	temporary := output.Name()
	defer os.Remove(temporary)
	writeErr := png.Encode(output, resultImage)
	if writeErr == nil {
		writeErr = output.Sync()
	}
	closeErr := output.Close()
	if writeErr == nil {
		writeErr = closeErr
	}
	if writeErr != nil {
		return imageExportResult{}, writeErr
	}
	if err := os.Link(temporary, destination); err != nil {
		return imageExportResult{}, err
	}
	return imageExportResult{Path: destination, Width: resultImage.Bounds().Dx(), Height: resultImage.Bounds().Dy()}, nil
}

func decodeAndTransformImage(file *os.File, size int64, values map[string]any) (*image.NRGBA, error) {
	config, format, err := image.DecodeConfig(file)
	if err != nil {
		return nil, err
	}
	if config.Width <= 0 || config.Height <= 0 || int64(config.Width)*int64(config.Height) > imageExportMaxPixels {
		return nil, errors.New("image exceeds the 60 megapixel export limit")
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	decoded, actualFormat, err := image.Decode(file)
	if err != nil {
		return nil, err
	}
	if actualFormat != format || decoded.Bounds().Dx() != config.Width || decoded.Bounds().Dy() != config.Height {
		return nil, errors.New("image changed while decoding")
	}
	orientation := 1
	if format == "jpeg" {
		orientation = jpegOrientation(file, size)
	}
	oriented := orientImage(decoded, orientation)
	angle := params.IntOpt(values, "angle", 0)
	angle = ((angle % 360) + 360) % 360
	if angle%90 != 0 {
		return nil, errors.New("image rotation must be a multiple of 90 degrees")
	}
	x := params.IntOpt(values, "x", 0)
	y := params.IntOpt(values, "y", 0)
	width := params.IntOpt(values, "width", oriented.Bounds().Dx())
	height := params.IntOpt(values, "height", oriented.Bounds().Dy())
	if x < 0 || y < 0 || width <= 0 || height <= 0 || x > oriented.Bounds().Dx()-width || y > oriented.Bounds().Dy()-height {
		return nil, errors.New("crop rectangle is outside the image")
	}
	result := cropImage(oriented, image.Rect(x, y, x+width, y+height))
	result = rotateImage(result, angle)
	if params.BoolOpt(values, "mirror", false) {
		result = mirrorImage(result)
	}
	return result, nil
}

func imageStillMatches(path string, opened os.FileInfo) error {
	current, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !current.Mode().IsRegular() || !os.SameFile(current, opened) || current.Size() != opened.Size() || !current.ModTime().Equal(opened.ModTime()) {
		return errors.New("image changed during export")
	}
	return nil
}

func cropImage(source image.Image, crop image.Rectangle) *image.NRGBA {
	result := image.NewNRGBA(image.Rect(0, 0, crop.Dx(), crop.Dy()))
	draw.Draw(result, result.Bounds(), source, image.Point{X: crop.Min.X + source.Bounds().Min.X, Y: crop.Min.Y + source.Bounds().Min.Y}, draw.Src)
	return result
}

func rotateImage(source image.Image, angle int) *image.NRGBA {
	bounds := source.Bounds()
	width, height := bounds.Dx(), bounds.Dy()
	if angle == 90 || angle == 270 {
		width, height = height, width
	}
	result := image.NewNRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < bounds.Dy(); y++ {
		for x := 0; x < bounds.Dx(); x++ {
			switch angle {
			case 90:
				result.Set(width-1-y, x, source.At(bounds.Min.X+x, bounds.Min.Y+y))
			case 180:
				result.Set(width-1-x, height-1-y, source.At(bounds.Min.X+x, bounds.Min.Y+y))
			case 270:
				result.Set(y, height-1-x, source.At(bounds.Min.X+x, bounds.Min.Y+y))
			default:
				result.Set(x, y, source.At(bounds.Min.X+x, bounds.Min.Y+y))
			}
		}
	}
	return result
}

func mirrorImage(source image.Image) *image.NRGBA {
	bounds := source.Bounds()
	result := image.NewNRGBA(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	for y := 0; y < bounds.Dy(); y++ {
		for x := 0; x < bounds.Dx(); x++ {
			result.Set(bounds.Dx()-1-x, y, source.At(bounds.Min.X+x, bounds.Min.Y+y))
		}
	}
	return result
}

func orientImage(source image.Image, orientation int) *image.NRGBA {
	bounds := source.Bounds()
	width, height := bounds.Dx(), bounds.Dy()
	if orientation >= 5 && orientation <= 8 {
		width, height = height, width
	}
	result := image.NewNRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < bounds.Dy(); y++ {
		for x := 0; x < bounds.Dx(); x++ {
			dx, dy := x, y
			switch orientation {
			case 2:
				dx = width - 1 - x
			case 3:
				dx, dy = width-1-x, height-1-y
			case 4:
				dy = height - 1 - y
			case 5:
				dx, dy = y, x
			case 6:
				dx, dy = bounds.Dy()-1-y, x
			case 7:
				dx, dy = bounds.Dy()-1-y, bounds.Dx()-1-x
			case 8:
				dx, dy = y, bounds.Dx()-1-x
			}
			result.Set(dx, dy, source.At(bounds.Min.X+x, bounds.Min.Y+y))
		}
	}
	return result
}

func jpegOrientation(file *os.File, size int64) int {
	limit := size
	if limit > 4<<20 {
		limit = 4 << 20
	}
	data := make([]byte, limit)
	if _, err := file.ReadAt(data, 0); err != nil && !errors.Is(err, io.EOF) && !errors.Is(err, io.ErrUnexpectedEOF) {
		return 1
	}
	if len(data) < 4 || data[0] != 0xff || data[1] != 0xd8 {
		return 1
	}
	for offset := 2; offset+4 <= len(data); {
		if data[offset] != 0xff {
			return 1
		}
		for offset < len(data) && data[offset] == 0xff {
			offset++
		}
		if offset >= len(data) {
			return 1
		}
		if offset+2 > len(data) {
			return 1
		}
		marker := data[offset]
		offset++
		if marker == 0xda || marker == 0xd9 {
			return 1
		}
		if marker >= 0xd0 && marker <= 0xd7 || marker == 0x01 {
			continue
		}
		length := int(data[offset])<<8 | int(data[offset+1])
		if length < 2 || offset+length > len(data) {
			return 1
		}
		segment := data[offset+2 : offset+length]
		if marker == 0xe1 && len(segment) >= 14 && string(segment[:6]) == "Exif\x00\x00" {
			return parseExifOrientation(segment[6:])
		}
		offset += length
	}
	return 1
}

func parseExifOrientation(data []byte) int {
	if len(data) < 8 {
		return 1
	}
	little := string(data[:2]) == "II"
	if !little && string(data[:2]) != "MM" {
		return 1
	}
	read16 := func(offset int) uint16 {
		if little {
			return uint16(data[offset]) | uint16(data[offset+1])<<8
		}
		return uint16(data[offset])<<8 | uint16(data[offset+1])
	}
	read32 := func(offset int) uint32 {
		if little {
			return uint32(data[offset]) | uint32(data[offset+1])<<8 | uint32(data[offset+2])<<16 | uint32(data[offset+3])<<24
		}
		return uint32(data[offset])<<24 | uint32(data[offset+1])<<16 | uint32(data[offset+2])<<8 | uint32(data[offset+3])
	}
	if read16(2) != 42 {
		return 1
	}
	ifd := int(read32(4))
	if ifd < 0 || ifd+2 > len(data) {
		return 1
	}
	count := int(read16(ifd))
	for index := 0; index < count; index++ {
		entry := ifd + 2 + index*12
		if entry+12 > len(data) {
			return 1
		}
		if read16(entry) != 0x0112 || read16(entry+2) != 3 || read32(entry+4) != 1 {
			continue
		}
		orientation := int(read16(entry + 8))
		if orientation >= 1 && orientation <= 8 {
			return orientation
		}
		return 1
	}
	return 1
}
