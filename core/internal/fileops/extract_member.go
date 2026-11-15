package fileops

import (
	"archive/tar"
	"archive/zip"
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"syscall"

	"github.com/bodgit/sevenzip"
	"github.com/nwaples/rardecode/v2"
	"golang.org/x/sys/unix"
)

const memberExtractLimit = 512 << 20

type memberContextReader struct {
	ctx context.Context
	r   io.Reader
}

func (r memberContextReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.r.Read(p)
}

// extractMember writes only a newly created basename in the chosen directory.
func (r *runner) extractMember() error {
	s := r.job.spec
	if len(s.sources) != 1 || !filepath.IsAbs(s.dest) || !safeArchiveName(s.member) {
		return errors.New("invalid archive member request")
	}
	archive, err := os.OpenFile(s.sources[0], os.O_RDONLY|syscall.O_NONBLOCK|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return err
	}
	defer archive.Close()
	info, err := archive.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return errors.New("archive is not a regular file")
	}
	var head [262]byte
	n, _ := archive.ReadAt(head[:], 0)
	format, ok := formatByMagic(head[:n])
	if !ok && n >= 4 && string(head[:4]) == "PK\x05\x06" {
		format, ok = archiveFormat{compressNone, containerZip}, true
	}
	if !ok {
		return errUnsupportedArchive
	}
	if format.container == containerZip {
		return r.extractZipMember(archive, info.Size(), s.member, s.dest)
	}
	if format.container == container7z {
		return r.extractSevenZipMember(archive, info.Size(), s.member, s.dest)
	}
	if format.container == containerRar {
		return r.extractRarMember(archive, s.member, s.dest)
	}
	if format.container == containerTar || format.compression != compressNone {
		return r.extractTarMember(archive, format.compression, s.member, s.dest)
	}
	return errUnsupportedArchive
}

func (r *runner) extractSevenZipMember(in *os.File, size int64, member, dest string) error {
	archive, err := sevenzip.NewReaderWithPassword(in, size, "")
	if err != nil {
		return err
	}
	var match *sevenzip.File
	for _, file := range archive.File {
		if file.Name != member {
			continue
		}
		if match != nil {
			return errors.New("duplicate archive member name")
		}
		if !sevenZipMode(file).IsRegular() {
			return errors.New("member is not a regular file")
		}
		if file.UncompressedSize > memberExtractLimit {
			return errors.New("archive member exceeds extraction size limit")
		}
		match = file
	}
	if match == nil {
		return errors.New("archive member not found")
	}
	body, err := match.Open()
	if err != nil {
		return err
	}
	defer body.Close()
	return r.writeMember(dest, member, int64(match.UncompressedSize), body)
}

func (r *runner) extractRarMember(in *os.File, member, dest string) error {
	find := func(write bool) (bool, error) {
		if _, err := in.Seek(0, io.SeekStart); err != nil {
			return false, err
		}
		reader, err := rardecode.NewReader(in)
		if err != nil {
			return false, err
		}
		seen := false
		for i := 0; i < archiveListLimit; i++ {
			header, err := reader.Next()
			if errors.Is(err, io.EOF) {
				return seen, nil
			}
			if err != nil {
				return false, err
			}
			if header.HeaderEncrypted {
				return false, errors.New("cannot extract from an archive with encrypted headers")
			}
			if header.Name != member {
				continue
			}
			if seen {
				return false, errors.New("duplicate archive member name")
			}
			if !header.Mode().IsRegular() || header.Encrypted || header.UnKnownSize {
				return false, errors.New("member is not an unencrypted regular file with a known size")
			}
			if header.UnPackedSize < 0 || header.UnPackedSize > memberExtractLimit {
				return false, errors.New("archive member exceeds extraction size limit")
			}
			seen = true
			if write {
				return true, r.writeMember(dest, member, header.UnPackedSize, reader)
			}
		}
		return false, errors.New("archive contains too many entries")
	}
	found, err := find(false)
	if err != nil {
		return err
	}
	if !found {
		return errors.New("archive member not found")
	}
	_, err = find(true)
	return err
}

func (r *runner) writeMember(dest, member string, size int64, reader io.Reader) error {
	if size < 0 || size > memberExtractLimit {
		return errors.New("archive member exceeds extraction size limit")
	}
	root, err := os.OpenRoot(dest)
	if err != nil {
		return err
	}
	defer root.Close()
	// Stage in a private directory within the already-open destination.
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil {
		return err
	}
	tempName := ".fjord-extract-" + hex.EncodeToString(random[:])
	if err := root.Mkdir(tempName, 0700); err != nil {
		return err
	}
	defer func() { _ = root.Remove(tempName) }()
	temp, err := root.OpenRoot(tempName)
	if err != nil {
		return err
	}
	defer temp.Close()
	defer func() { _ = temp.Remove("content") }()
	out, err := temp.OpenFile("content", os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	name := path.Base(member)
	target := filepath.Join(dest, name)
	r.setTotals(1, size, false)
	err = r.stream(target, io.LimitReader(reader, size+1), out)
	closeErr := out.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if r.progress().BytesDone != size {
		return errors.New("unexpected archive member length")
	}
	if r.job.closed() {
		return context.Canceled
	}
	fromDir, err := temp.Open(".")
	if err != nil {
		return err
	}
	defer fromDir.Close()
	toDir, err := root.Open(".")
	if err != nil {
		return err
	}
	defer toDir.Close()
	// No check-then-rename fallback: that could overwrite a concurrent file.
	if err := unix.Renameat2(int(fromDir.Fd()), "content", int(toDir.Fd()), name, unix.RENAME_NOREPLACE); err != nil {
		return fmt.Errorf("cannot publish %s without overwriting: %w", name, err)
	}
	r.advance(target, 1, 0)
	r.noteCreated(target, false)
	return nil
}

func (r *runner) extractZipMember(in *os.File, size int64, member, dest string) error {
	archive, err := zip.NewReader(&budgetReaderAt{reader: in, remaining: zipMetadataReadLimit}, size)
	if err != nil {
		return err
	}
	var match *zip.File
	for _, file := range archive.File {
		if file.Name != member {
			continue
		}
		if match != nil {
			return errors.New("duplicate archive member name")
		}
		if !file.Mode().IsRegular() || file.Flags&zipFlagEncrypted != 0 {
			return errors.New("member is not an unencrypted regular file")
		}
		match = file
	}
	if match == nil {
		return errors.New("archive member not found")
	}
	if match.UncompressedSize64 > memberExtractLimit {
		return errors.New("archive member exceeds extraction size limit")
	}
	body, err := match.Open()
	if err != nil {
		return err
	}
	defer body.Close()
	return r.writeMember(dest, member, int64(match.UncompressedSize64), body)
}

func (r *runner) tarMember(in *os.File, compression compression, member string, visit func(io.Reader, int64) error) error {
	if _, err := in.Seek(0, io.SeekStart); err != nil {
		return err
	}
	stream, closeStream, err := openStream(in, compression)
	if err != nil {
		return err
	}
	defer closeStream()
	limited := &io.LimitedReader{R: memberContextReader{ctx: r.job.ctx, r: stream}, N: memberExtractLimit + 1}
	reader := tar.NewReader(limited)
	seen := false
	for i := 0; i < archiveListLimit; i++ {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			if limited.N <= 0 {
				return errors.New("archive exceeds scan limit")
			}
			if !seen {
				return errors.New("archive member not found")
			}
			return nil
		}
		if err != nil {
			return err
		}
		if header.Name != member {
			continue
		}
		if seen {
			return errors.New("duplicate archive member name")
		}
		if header.Typeflag != tar.TypeReg {
			return errors.New("member is not a regular file")
		}
		if header.Size < 0 || header.Size > memberExtractLimit {
			return errors.New("archive member exceeds extraction size limit")
		}
		seen = true
		if visit != nil {
			return visit(reader, header.Size)
		}
	}
	return errors.New("archive contains too many entries")
}

func (r *runner) extractTarMember(in *os.File, compression compression, member, dest string) error {
	// First pass rejects ambiguous duplicate names before any output is created.
	if err := r.tarMember(in, compression, member, nil); err != nil {
		return err
	}
	return r.tarMember(in, compression, member, func(body io.Reader, size int64) error { return r.writeMember(dest, member, size, body) })
}
