package ipc

import (
	"context"
	"encoding/base64"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-go/files"
)

func TestRummagePictureIntegration(t *testing.T) {
	helper := os.Getenv("FJORD_TEST_RUMMAGE_HELPER")
	if helper == "" {
		t.Skip("set FJORD_TEST_RUMMAGE_HELPER to test the real protocol 4 helper")
	}
	t.Setenv("RUMMAGE_SANDBOX_REPORT", "1")
	t.Setenv("FJORD_RUMMAGE_PREVIEW_V4", helper)
	encoders := map[string]func(*os.File, image.Image) error{
		"png":  func(out *os.File, img image.Image) error { return png.Encode(out, img) },
		"jpeg": func(out *os.File, img image.Image) error { return jpeg.Encode(out, img, &jpeg.Options{Quality: 90}) },
	}
	for extension, encode := range encoders {
		t.Run(extension, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "test."+extension)
			output, err := os.Create(path)
			if err != nil {
				t.Fatal(err)
			}
			img := image.NewNRGBA(image.Rect(0, 0, 2, 1))
			img.SetNRGBA(0, 0, color.NRGBA{R: 200, A: 128})
			img.SetNRGBA(1, 0, color.NRGBA{G: 255, A: 255})
			if err := encode(output, img); err != nil {
				output.Close()
				t.Fatal(err)
			}
			if err := output.Close(); err != nil {
				t.Fatal(err)
			}
			file, err := os.Open(path)
			if err != nil {
				t.Fatal(err)
			}
			defer file.Close()
			result, err := rummagePicture(context.Background(), helper, file, 8, 8)
			if err != nil {
				t.Fatal(err)
			}
			if result.Width != 2 || result.Height != 1 || result.FullWidth != 2 || result.FullHeight != 1 {
				t.Fatalf("wrong dimensions: %+v", result)
			}
			if result.Image == nil || result.Image.Bounds().Size() != image.Pt(2, 1) {
				t.Fatalf("wrong decoded thumbnail image: %v", result.Image)
			}
			thumbnail, err := decodeRummageThumbnail(helper, path, 1)
			if err != nil {
				t.Fatal(err)
			}
			if thumbnail.Bounds().Size() != image.Pt(1, 1) {
				t.Fatalf("wrong thumbnail bounds: %v", thumbnail.Bounds())
			}
			cachedThumbnail, err := ImageThumbnailDecoder()(path, 1)
			if err != nil {
				t.Fatal(err)
			}
			if cachedThumbnail.Bounds().Size() != image.Pt(1, 1) {
				t.Fatalf("wrong configured thumbnail bounds: %v", cachedThumbnail.Bounds())
			}
			fileService := files.NewService(nil, t.TempDir(), nil)
			defer fileService.Close()
			fileService.SetIsolatedImageThumbnailer(ImageThumbnailDecoder())
			response := routeAndRead(t, Request{ID: 1, Method: "files.thumbnail", Params: map[string]any{"paths": []any{path}, "size": "normal"}}, Deps{Files: fileService})
			thumbnailResult, ok := response["result"].(map[string]any)
			if !ok {
				t.Fatalf("thumbnail request failed: %v", response)
			}
			thumbnailItem := thumbnailResult["results"].([]any)[0].(map[string]any)
			cachePath, _ := thumbnailItem["thumbnail"].(string)
			if cachePath == "" {
				t.Fatalf("thumbnail was not written to cache: %v", thumbnailItem)
			}
			cachedFile, err := os.Open(cachePath)
			if err != nil {
				t.Fatal(err)
			}
			config, err := png.DecodeConfig(cachedFile)
			cachedFile.Close()
			if err != nil {
				t.Fatal(err)
			}
			if config.Width > 128 || config.Height > 128 {
				t.Fatalf("cached thumbnail is out of bounds: %+v", config)
			}
			encoded, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(result.URL, "data:image/png;base64,"))
			if err != nil {
				t.Fatal(err)
			}
			decoded, err := png.Decode(strings.NewReader(string(encoded)))
			if err != nil {
				t.Fatal(err)
			}
			if extension == "png" {
				r, _, _, a := decoded.At(0, 0).RGBA()
				if a != 32896 || r < 25000 || r > 26000 {
					t.Fatalf("wrong pixel %d %d", r, a)
				}
			}
		})
	}
}

func TestWithoutEnvironmentReplacesInheritedSetting(t *testing.T) {
	env := withoutEnvironment([]string{"PATH=/bin", "RUMMAGE_SANDBOX_REPORT=1", "HOME=/tmp", "RUMMAGE_SANDBOX_REPORT=1"}, "RUMMAGE_SANDBOX_REPORT")
	env = append(env, "RUMMAGE_SANDBOX_REPORT=0")
	count := 0
	for _, entry := range env {
		if strings.HasPrefix(entry, "RUMMAGE_SANDBOX_REPORT=") {
			count++
			if entry != "RUMMAGE_SANDBOX_REPORT=0" {
				t.Fatalf("unexpected inherited value: %q", entry)
			}
		}
	}
	if count != 1 {
		t.Fatalf("expected one setting, got %d: %v", count, env)
	}
}

func TestRummagePreviewRejectsInvalidInput(t *testing.T) {
	out := routeAndRead(t, Request{ID: 1, Method: "files.rummagePreview", Params: map[string]any{"path": "relative"}}, Deps{})
	if out["error"] == nil {
		t.Fatal("relative path accepted")
	}
}
