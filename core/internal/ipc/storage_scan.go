package ipc

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-files/core/internal/wire"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"golang.org/x/sys/unix"
)

const storageEntryLimit = 100000
const storageDepthLimit = 64
const storageTopLimit = 20

type storageItem struct {
	Path string `json:"path"`
	Size int64  `json:"size"`
}
type storageResult struct {
	Root        string        `json:"root"`
	TotalSize   int64         `json:"totalSize"`
	Files       []storageItem `json:"files"`
	Directories []storageItem `json:"directories"`
	Visited     int           `json:"visited"`
	Skipped     int           `json:"skipped"`
	Truncated   bool          `json:"truncated"`
}

var storageScans = struct {
	sync.Mutex
	cancel map[string]context.CancelFunc
}{cancel: make(map[string]context.CancelFunc)}
var storageSlots = make(chan struct{}, 2)
var errStorageLimit = errors.New("storage scan entry limit reached")

func storageScanManaged(ctx context.Context, path, id string) (storageResult, error) {
	if id == "" || len(id) > 96 {
		return storageResult{}, errors.New("invalid scan ID")
	}
	ctx, cancel := context.WithCancel(ctx)
	storageScans.Lock()
	if _, exists := storageScans.cancel[id]; exists || len(storageScans.cancel) >= 16 {
		storageScans.Unlock()
		cancel()
		return storageResult{}, errors.New("scan ID already in use or too many pending scans")
	}
	storageScans.cancel[id] = cancel
	storageScans.Unlock()
	defer func() { storageScans.Lock(); delete(storageScans.cancel, id); storageScans.Unlock(); cancel() }()
	select {
	case storageSlots <- struct{}{}:
		defer func() { <-storageSlots }()
	case <-ctx.Done():
		return storageResult{}, ctx.Err()
	}
	ctx, timeout := context.WithTimeout(ctx, 30*time.Second)
	defer timeout()
	return storageScan(ctx, path, storageEntryLimit)
}

func cancelStorageScan(id string) bool {
	storageScans.Lock()
	defer storageScans.Unlock()
	cancel, ok := storageScans.cancel[id]
	if ok {
		cancel()
	}
	return ok
}

func storageScan(ctx context.Context, root string, limit int) (storageResult, error) {
	result := storageResult{Root: root, Files: []storageItem{}, Directories: []storageItem{}}
	if !filepath.IsAbs(root) || limit < 1 {
		return result, errors.New("absolute directory path required")
	}
	fd, err := unix.Open(root, unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return result, err
	}
	rootFile := os.NewFile(uintptr(fd), root)
	defer rootFile.Close()
	var rootStat unix.Stat_t
	if err := unix.Fstat(fd, &rootStat); err != nil {
		return result, err
	}
	var rootMount unix.Statx_t
	if err := unix.Statx(fd, "", unix.AT_EMPTY_PATH|unix.AT_SYMLINK_NOFOLLOW, unix.STATX_MNT_ID, &rootMount); err != nil || rootMount.Mask&unix.STATX_MNT_ID == 0 {
		return result, errors.New("storage scan requires filesystem mount identifiers")
	}
	type inode struct {
		dev uint64
		ino uint64
	}
	seen := make(map[inode]bool)
	dirs := make(map[string]int64)
	var walk func(*os.File, string, string, int) error
	walk = func(dir *os.File, display, branch string, depth int) error {
		for {
			if err := ctx.Err(); err != nil {
				return err
			}
			names, err := dir.Readdirnames(128)
			for _, name := range names {
				if err := ctx.Err(); err != nil {
					return err
				}
				if result.Visited >= limit {
					return errStorageLimit
				}
				result.Visited++
				var st unix.Stat_t
				if err := unix.Fstatat(int(dir.Fd()), name, &st, unix.AT_SYMLINK_NOFOLLOW); err != nil {
					result.Skipped++
					continue
				}
				var mount unix.Statx_t
				if err := unix.Statx(int(dir.Fd()), name, unix.AT_SYMLINK_NOFOLLOW, unix.STATX_MNT_ID, &mount); err != nil || mount.Mask&unix.STATX_MNT_ID == 0 {
					result.Skipped++
					continue
				}
				if st.Dev != rootStat.Dev || mount.Mnt_id != rootMount.Mnt_id {
					result.Skipped++
					continue
				}
				child := filepath.Join(display, name)
				if st.Mode&unix.S_IFMT == unix.S_IFDIR {
					if depth >= storageDepthLimit {
						result.Skipped++
						continue
					}
					sub, err := unix.Openat2(int(dir.Fd()), name, &unix.OpenHow{
						Flags:   unix.O_RDONLY | unix.O_DIRECTORY | unix.O_NOFOLLOW | unix.O_CLOEXEC,
						Resolve: unix.RESOLVE_NO_XDEV | unix.RESOLVE_NO_SYMLINKS,
					})
					if errors.Is(err, unix.ENOSYS) || errors.Is(err, unix.EINVAL) {
						return errors.New("storage scan requires openat2 mount protection")
					}
					if err != nil {
						result.Skipped++
						continue
					}
					var opened unix.Stat_t
					if unix.Fstat(sub, &opened) != nil || opened.Dev != st.Dev || opened.Ino != st.Ino {
						unix.Close(sub)
						result.Skipped++
						continue
					}
					nextBranch := branch
					if depth == 0 {
						nextBranch = child
						dirs[child] = 0
					}
					file := os.NewFile(uintptr(sub), child)
					err = walk(file, child, nextBranch, depth+1)
					file.Close()
					if err != nil {
						return err
					}
				} else if st.Mode&unix.S_IFMT == unix.S_IFREG {
					key := inode{uint64(st.Dev), st.Ino}
					if seen[key] {
						continue
					}
					seen[key] = true
					if st.Size < 0 {
						result.Skipped++
						continue
					}
					if st.Size > math.MaxInt64-result.TotalSize {
						result.TotalSize = math.MaxInt64
						result.Skipped++
					} else {
						result.TotalSize += st.Size
					}
					if branch != "" {
						if st.Size > math.MaxInt64-dirs[branch] {
							dirs[branch] = math.MaxInt64
							result.Skipped++
						} else {
							dirs[branch] += st.Size
						}
					}
					result.Files = append(result.Files, storageItem{Path: child, Size: st.Size})
					sort.Slice(result.Files, func(i, j int) bool { return result.Files[i].Size > result.Files[j].Size })
					if len(result.Files) > storageTopLimit {
						result.Files = result.Files[:storageTopLimit]
					}
				} else {
					result.Skipped++
				}
			}
			if err == io.EOF {
				return nil
			}
			if err != nil {
				result.Skipped++
				return nil
			}
		}
	}
	err = walk(rootFile, root, "", 0)
	if errors.Is(err, errStorageLimit) {
		result.Truncated = true
	} else if err != nil {
		return result, err
	}
	for path, size := range dirs {
		result.Directories = append(result.Directories, storageItem{Path: path, Size: size})
	}
	sort.Slice(result.Directories, func(i, j int) bool { return result.Directories[i].Size > result.Directories[j].Size })
	if len(result.Directories) > storageTopLimit {
		result.Directories = result.Directories[:storageTopLimit]
	}
	return result, nil
}

func HandleStorage(ctx context.Context, w *ConnWriter, req Request) {
	switch req.Method {
	case "storage.scan":
		result, err := storageScanManaged(ctx, params.StringOpt(req.Params, "path", ""), params.StringOpt(req.Params, "scanId", ""))
		if err != nil {
			wire.RespondError(w, req.ID, err)
			return
		}
		w.Respond(req.ID, result)
	case "storage.projects":
		result, err := storageProjectsManaged(ctx, params.StringOpt(req.Params, "path", ""), params.StringOpt(req.Params, "scanId", ""))
		if err != nil {
			wire.RespondError(w, req.ID, err)
			return
		}
		w.Respond(req.ID, result)
	case "storage.cancel":
		w.Respond(req.ID, map[string]bool{"cancelled": cancelStorageScan(params.StringOpt(req.Params, "scanId", ""))})
	default:
		wire.RespondError(w, req.ID, fmt.Errorf("unknown storage method: %s", req.Method))
	}
}
