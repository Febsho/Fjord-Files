package ipc

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestExportImageCropsRotatesAndMirrorsWithoutOverwriting(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source.png")
	destination := filepath.Join(dir, "edited.png")
	input := image.NewNRGBA(image.Rect(0, 0, 2, 3))
	colors := []color.NRGBA{
		{R: 255, A: 255}, {G: 255, A: 255},
		{B: 255, A: 255}, {R: 255, G: 255, A: 255},
		{R: 255, B: 255, A: 255}, {G: 255, B: 255, A: 255},
	}
	for index, pixel := range colors {
		input.SetNRGBA(index%2, index/2, pixel)
	}
	file, err := os.Create(source)
	require.NoError(t, err)
	require.NoError(t, png.Encode(file, input))
	require.NoError(t, file.Close())

	result, err := exportImage(map[string]any{
		"path": source, "destination": destination,
		"x": 0, "y": 1, "width": 2, "height": 2,
		"angle": 90, "mirror": true,
	})
	require.NoError(t, err)
	require.Equal(t, imageExportResult{Path: destination, Width: 2, Height: 2}, result)
	output, err := os.Open(destination)
	require.NoError(t, err)
	decoded, err := png.Decode(output)
	require.NoError(t, err)
	require.NoError(t, output.Close())
	require.Equal(t, colors[2], color.NRGBAModel.Convert(decoded.At(0, 0)).(color.NRGBA))
	require.Equal(t, colors[4], color.NRGBAModel.Convert(decoded.At(1, 0)).(color.NRGBA))
	require.Equal(t, colors[3], color.NRGBAModel.Convert(decoded.At(0, 1)).(color.NRGBA))
	require.Equal(t, colors[5], color.NRGBAModel.Convert(decoded.At(1, 1)).(color.NRGBA))

	before, err := os.ReadFile(destination)
	require.NoError(t, err)
	_, err = exportImage(map[string]any{"path": source, "destination": destination})
	require.Error(t, err)
	after, err := os.ReadFile(destination)
	require.NoError(t, err)
	require.Equal(t, before, after)
}

func TestExportImageRejectsUnsafeDestinationsAndCrop(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source.png")
	input := image.NewNRGBA(image.Rect(0, 0, 1, 1))
	file, err := os.Create(source)
	require.NoError(t, err)
	require.NoError(t, png.Encode(file, input))
	require.NoError(t, file.Close())

	for _, values := range []map[string]any{
		{"path": source, "destination": source},
		{"path": source, "destination": filepath.Join(dir, "outside.jpg")},
		{"path": source, "destination": filepath.Join(dir, "outside.png"), "x": 1, "y": 0, "width": 1, "height": 1},
	} {
		_, err := exportImage(values)
		require.Error(t, err)
	}

	link := filepath.Join(dir, "linked.png")
	require.NoError(t, os.Symlink(source, link))
	_, err = exportImage(map[string]any{"path": link, "destination": filepath.Join(dir, "linked-export.png")})
	require.Error(t, err)
}

func TestParseExifOrientation(t *testing.T) {
	tiff := make([]byte, 22)
	copy(tiff, []byte("II"))
	binary.LittleEndian.PutUint16(tiff[2:], 42)
	binary.LittleEndian.PutUint32(tiff[4:], 8)
	binary.LittleEndian.PutUint16(tiff[8:], 1)
	binary.LittleEndian.PutUint16(tiff[10:], 0x0112)
	binary.LittleEndian.PutUint16(tiff[12:], 3)
	binary.LittleEndian.PutUint32(tiff[14:], 1)
	binary.LittleEndian.PutUint16(tiff[18:], 6)
	require.Equal(t, 6, parseExifOrientation(tiff))
	require.Equal(t, 1, parseExifOrientation(bytes.Repeat([]byte{0}, 8)))
}

func TestOrientImageRotatesDimensions(t *testing.T) {
	source := image.NewNRGBA(image.Rect(0, 0, 2, 3))
	for orientation := 1; orientation <= 8; orientation++ {
		result := orientImage(source, orientation)
		if orientation >= 5 {
			require.Equal(t, image.Point{X: 3, Y: 2}, result.Bounds().Size())
		} else {
			require.Equal(t, image.Point{X: 2, Y: 3}, result.Bounds().Size())
		}
	}
}

func TestImageExportWorkerSubprocess(t *testing.T) {
	if os.Getenv("DFILES_IMAGE_EXPORT_TEST_WORKER") == "1" {
		if err := RunImageExportWorkerFromProcess(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	dir := t.TempDir()
	sourcePath := filepath.Join(dir, "worker-source.png")
	inputImage := image.NewNRGBA(image.Rect(0, 0, 2, 3))
	inputImage.SetNRGBA(0, 0, color.NRGBA{R: 255, A: 255})
	inputImage.SetNRGBA(1, 0, color.NRGBA{G: 255, A: 255})
	inputFile, err := os.Create(sourcePath)
	require.NoError(t, err)
	require.NoError(t, png.Encode(inputFile, inputImage))
	require.NoError(t, inputFile.Close())
	inputFile, err = os.Open(sourcePath)
	require.NoError(t, err)
	defer inputFile.Close()
	outputFile, err := os.CreateTemp(dir, ".worker-output-")
	require.NoError(t, err)
	defer os.Remove(outputFile.Name())

	command := exec.Command(os.Args[0], "-test.run=^TestImageExportWorkerSubprocess$")
	command.Env = append(os.Environ(), "DFILES_IMAGE_EXPORT_TEST_WORKER=1")
	command.ExtraFiles = []*os.File{inputFile, outputFile}
	command.Stdin = bytes.NewBufferString(`{"angle":90,"mirror":false}`)
	var stdout, stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	err = command.Run()
	require.NoError(t, err, stderr.String())
	var result imageWorkerResult
	require.NoError(t, json.Unmarshal(stdout.Bytes(), &result))
	require.Equal(t, imageWorkerResult{Width: 3, Height: 2, Sandboxed: true}, result)
	require.NoError(t, outputFile.Sync())
	_, err = outputFile.Seek(0, io.SeekStart)
	require.NoError(t, err)
	decoded, err := png.Decode(outputFile)
	require.NoError(t, err)
	require.Equal(t, image.Point{X: 3, Y: 2}, decoded.Bounds().Size())
}

func TestExportImageIsolatedEndToEnd(t *testing.T) {
	originalCommand := imageWorkerCommand
	imageWorkerCommand = func(ctx context.Context, _ string, _ ...string) *exec.Cmd {
		command := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestImageExportWorkerSubprocess$")
		command.Env = append(os.Environ(), "DFILES_IMAGE_EXPORT_TEST_WORKER=1")
		return command
	}
	defer func() { imageWorkerCommand = originalCommand }()
	dir := t.TempDir()
	source := filepath.Join(dir, "original.png")
	destination := filepath.Join(dir, "copy.png")
	input := image.NewNRGBA(image.Rect(0, 0, 2, 1))
	input.SetNRGBA(0, 0, color.NRGBA{R: 255, A: 255})
	input.SetNRGBA(1, 0, color.NRGBA{B: 255, A: 255})
	file, err := os.Create(source)
	require.NoError(t, err)
	require.NoError(t, png.Encode(file, input))
	require.NoError(t, file.Close())

	result, err := exportImageIsolated(context.Background(), map[string]any{"path": source, "destination": destination, "angle": 90})
	require.NoError(t, err)
	require.Equal(t, imageExportResult{Path: destination, Width: 1, Height: 2}, result)
	output, err := os.Open(destination)
	require.NoError(t, err)
	decoded, err := png.Decode(output)
	require.NoError(t, err)
	require.NoError(t, output.Close())
	require.Equal(t, image.Point{X: 1, Y: 2}, decoded.Bounds().Size())
	require.Equal(t, color.NRGBA{R: 255, A: 255}, color.NRGBAModel.Convert(decoded.At(0, 0)).(color.NRGBA))
	require.Equal(t, color.NRGBA{B: 255, A: 255}, color.NRGBAModel.Convert(decoded.At(0, 1)).(color.NRGBA))

	preview, err := previewImageIsolated(context.Background(), map[string]any{"path": source, "maxWidth": 1, "maxHeight": 1})
	require.NoError(t, err)
	require.Equal(t, 1, preview.Width)
	require.Equal(t, 1, preview.Height)
	require.Equal(t, 2, preview.FullWidth)
	require.Equal(t, 1, preview.FullHeight)
	previewPNG, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(preview.URL, "data:image/png;base64,"))
	require.NoError(t, err)
	previewImage, err := png.Decode(bytes.NewReader(previewPNG))
	require.NoError(t, err)
	require.Equal(t, image.Point{X: 1, Y: 1}, previewImage.Bounds().Size())

	thumbnail, err := DecodeImageThumbnailIsolated(source, 1)
	require.NoError(t, err)
	require.Equal(t, image.Point{X: 1, Y: 1}, thumbnail.Bounds().Size())
}

func TestImagePreviewRejectsInvalidPathsAndDimensions(t *testing.T) {
	for _, values := range []map[string]any{
		{"path": "relative"},
		{"path": "/tmp/image.png", "maxWidth": 1025},
		{"path": "/tmp/image.png", "maxHeight": 0},
	} {
		_, err := previewImageIsolated(context.Background(), values)
		require.Error(t, err)
	}

	link := filepath.Join(t.TempDir(), "image.png")
	require.NoError(t, os.Symlink("/tmp/image.png", link))
	_, err := previewImageIsolated(context.Background(), map[string]any{"path": link})
	require.Error(t, err)
}
