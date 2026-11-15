package fileops

import (
	"archive/tar"
	"archive/zip"
	"errors"
	"io"
	"os"
	"path"
	"strings"

	"github.com/bodgit/sevenzip"
	"github.com/cavaliergopher/cpio"
	"github.com/nwaples/rardecode/v2"
)

const archiveListLimit = 10000
const archiveScanLimit = 128 << 20
const zipMetadataReadLimit = 4 << 20

type budgetReaderAt struct {
	reader    io.ReaderAt
	remaining int64
}

func (r *budgetReaderAt) ReadAt(p []byte, offset int64) (int, error) {
	if int64(len(p)) > r.remaining {
		return 0, errors.New("zip metadata exceeds preview limit")
	}
	n, err := r.reader.ReadAt(p, offset)
	r.remaining -= int64(n)
	return n, err
}

type ArchiveEntry struct {
	Path string `json:"path"`
	Size int64  `json:"size"`
	Dir  bool   `json:"dir"`
}
type ArchiveListing struct {
	Entries   []ArchiveEntry `json:"entries"`
	Truncated bool           `json:"truncated"`
}

// BrowsableArchive checks the bytes rather than trusting a filename. Compressed
// streams are treated as potential TAR archives and verified while reading.
func BrowsableArchive(head []byte) bool {
	format, ok := formatByMagic(head)
	if !ok {
		return len(head) >= 4 && string(head[:4]) == "PK\x05\x06"
	}
	return format.container == containerTar || format.container == containerZip || format.container == container7z || format.container == containerRar || format.container == containerCpio || format.compression != compressNone
}

func safeArchiveName(name string) bool {
	if name == "" || len(name) > 4096 || strings.ContainsAny(name, "\\\x00") || strings.HasPrefix(name, "/") {
		return false
	}
	for _, part := range strings.Split(name, "/") {
		if part == ".." {
			return false
		}
	}
	return path.Clean(name) != "."
}

// ListArchive only reads metadata. It never creates files or follows archive links.
func ListArchive(in *os.File, _ string) (ArchiveListing, error) {
	result := ArchiveListing{Entries: []ArchiveEntry{}}
	info, err := in.Stat()
	if err != nil {
		return result, err
	}
	if info.Size() > archiveScanLimit {
		return result, errors.New("archive exceeds preview size limit")
	}
	var head [262]byte
	n, _ := in.ReadAt(head[:], 0)
	format, ok := formatByMagic(head[:n])
	if !ok && n >= 4 && string(head[:4]) == "PK\x05\x06" {
		format, ok = archiveFormat{compressNone, containerZip}, true
	}
	if ok && format.compression != compressNone && format.container == containerNone {
		format.container = containerTar
	}
	if !ok {
		return result, errUnsupportedArchive
	}
	add := func(name string, size int64, dir bool) {
		if safeArchiveName(name) {
			result.Entries = append(result.Entries, ArchiveEntry{Path: strings.TrimSuffix(name, "/"), Size: size, Dir: dir})
		}
	}
	if format.container == containerZip {
		zr, err := zip.NewReader(&budgetReaderAt{reader: in, remaining: zipMetadataReadLimit}, info.Size())
		if err != nil {
			return result, err
		}
		for i, f := range zr.File {
			if i >= archiveListLimit {
				result.Truncated = true
				break
			}
			if f.Mode().IsRegular() || f.FileInfo().IsDir() {
				add(f.Name, int64(f.UncompressedSize64), f.FileInfo().IsDir())
			}
		}
		return result, nil
	}
	if format.container == container7z {
		reader, err := sevenzip.NewReaderWithPassword(in, info.Size(), "")
		if err != nil {
			return result, err
		}
		for i, f := range reader.File {
			if i >= archiveListLimit {
				result.Truncated = true
				break
			}
			mode := sevenZipMode(f)
			if mode.IsRegular() || mode.IsDir() {
				add(f.Name, int64(f.UncompressedSize), mode.IsDir())
			}
		}
		return result, nil
	}
	if format.container == containerRar {
		reader, err := rardecode.NewReader(in)
		if err != nil {
			return result, err
		}
		for i := 0; ; i++ {
			if i >= archiveListLimit {
				result.Truncated = true
				break
			}
			header, err := reader.Next()
			if err == io.EOF {
				break
			}
			if err != nil {
				return result, err
			}
			if header.HeaderEncrypted {
				return result, errors.New("cannot preview an archive with encrypted headers")
			}
			mode := header.Mode()
			if mode.IsRegular() || mode.IsDir() {
				add(header.Name, header.UnPackedSize, mode.IsDir())
			}
		}
		return result, nil
	}
	if format.container == containerCpio {
		reader := cpio.NewReader(in)
		for i := 0; ; i++ {
			if i >= archiveListLimit {
				result.Truncated = true
				break
			}
			header, err := reader.Next()
			if err == io.EOF {
				break
			}
			if err != nil {
				return result, err
			}
			switch header.Mode & cpio.ModeType {
			case cpio.TypeReg:
				add(header.Name, header.Size, false)
			case cpio.TypeDir:
				add(header.Name, header.Size, true)
			}
		}
		return result, nil
	}
	if format.container != containerTar {
		return result, errUnsupportedArchive
	}
	if _, err := in.Seek(0, io.SeekStart); err != nil {
		return result, err
	}
	stream, closeStream, err := openStream(in, format.compression)
	if err != nil {
		return result, err
	}
	defer closeStream()
	limited := &io.LimitedReader{R: stream, N: archiveScanLimit + 1}
	tr := tar.NewReader(limited)
	for i := 0; ; i++ {
		if i >= archiveListLimit {
			result.Truncated = true
			break
		}
		h, err := tr.Next()
		if err == io.EOF {
			if limited.N <= 0 {
				result.Truncated = true
			}
			break
		}
		if err != nil {
			if limited.N <= 0 {
				result.Truncated = true
				break
			}
			return result, err
		}
		if h.Typeflag == tar.TypeReg || h.Typeflag == tar.TypeDir {
			add(h.Name, h.Size, h.Typeflag == tar.TypeDir)
		}
		if limited.N <= 0 {
			result.Truncated = true
			break
		}
	}
	return result, nil
}
