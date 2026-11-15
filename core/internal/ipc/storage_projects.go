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
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

const storageProjectLimit = 500

var storageProjectMarkers = map[string]string{
	".git":             "Git",
	"go.mod":           "Go",
	"Cargo.toml":       "Rust",
	"package.json":     "Node.js",
	"pyproject.toml":   "Python",
	"requirements.txt": "Python",
	"CMakeLists.txt":   "CMake",
	"meson.build":      "Meson",
	"pom.xml":          "Maven",
	"build.gradle":     "Gradle",
	"build.gradle.kts": "Gradle",
	"composer.json":    "PHP",
	"Gemfile":          "Ruby",
	"mix.exs":          "Elixir",
	"deno.json":        "Deno",
	"deno.jsonc":       "Deno",
}

var generatedProjectDirs = map[string]bool{
	".git": true, "node_modules": true, "target": true, "build": true,
	"dist": true, "out": true, ".cache": true, ".venv": true,
	"venv": true, "vendor": true, ".sweep-trash": true,
}

type storageProject struct {
	Path           string   `json:"path"`
	Name           string   `json:"name"`
	Kinds          []string `json:"kinds"`
	Size           int64    `json:"size"`
	LastActivityMs *int64   `json:"lastActivityMs,omitempty"`
}

type storageProjectsResult struct {
	Root              string           `json:"root"`
	Projects          []storageProject `json:"projects"`
	Visited           int              `json:"visited"`
	Skipped           int              `json:"skipped"`
	Truncated         bool             `json:"truncated"`
	ProjectsTruncated bool             `json:"projectsTruncated"`
}

func storageProjectsManaged(ctx context.Context, path, id string) (storageProjectsResult, error) {
	if id == "" || len(id) > 96 {
		return storageProjectsResult{}, errors.New("invalid scan ID")
	}
	ctx, cancel := context.WithCancel(ctx)
	storageScans.Lock()
	if _, exists := storageScans.cancel[id]; exists || len(storageScans.cancel) >= 16 {
		storageScans.Unlock()
		cancel()
		return storageProjectsResult{}, errors.New("scan ID already in use or too many pending scans")
	}
	storageScans.cancel[id] = cancel
	storageScans.Unlock()
	defer func() { storageScans.Lock(); delete(storageScans.cancel, id); storageScans.Unlock(); cancel() }()
	select {
	case storageSlots <- struct{}{}:
		defer func() { <-storageSlots }()
	case <-ctx.Done():
		return storageProjectsResult{}, ctx.Err()
	}
	ctx, timeout := context.WithTimeout(ctx, 30*time.Second)
	defer timeout()
	return storageProjectsScan(ctx, path, storageEntryLimit)
}

func storageProjectsScan(ctx context.Context, root string, limit int) (storageProjectsResult, error) {
	result := storageProjectsResult{Root: root, Projects: []storageProject{}}
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
		return result, errors.New("project scan requires filesystem mount identifiers")
	}
	type inode struct{ dev, ino uint64 }
	type projectState struct {
		value  storageProject
		latest int64
	}
	projects := make([]projectState, 0, 32)
	seen := make(map[inode]struct{})
	var walk func(*os.File, string, int, []int, bool) error
	walk = func(dir *os.File, display string, depth int, ancestors []int, generated bool) error {
		markerKinds := map[string]bool{}
		preflight := 0
		for {
			if err := ctx.Err(); err != nil {
				return err
			}
			batch, err := dir.Readdirnames(128)
			for _, name := range batch {
				if kind, ok := storageProjectMarkers[name]; ok {
					markerKinds[kind] = true
				}
			}
			preflight += len(batch)
			if err == io.EOF {
				break
			}
			if err != nil {
				result.Skipped++
				break
			}
			if preflight > limit-result.Visited {
				break
			}
		}
		if _, err := dir.Seek(0, io.SeekStart); err != nil {
			return fmt.Errorf("rewind project directory: %w", err)
		}
		if len(markerKinds) > 0 {
			if len(projects) >= storageProjectLimit {
				result.ProjectsTruncated = true
			} else {
				kinds := make([]string, 0, len(markerKinds))
				for kind := range markerKinds {
					kinds = append(kinds, kind)
				}
				sort.Strings(kinds)
				projects = append(projects, projectState{value: storageProject{
					Path: display, Name: filepath.Base(display), Kinds: kinds,
				}})
				ancestors = append(append([]int(nil), ancestors...), len(projects)-1)
			}
		}
		for {
			if err := ctx.Err(); err != nil {
				return err
			}
			names, readErr := dir.Readdirnames(128)
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
						return errors.New("project scan requires openat2 mount protection")
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
					file := os.NewFile(uintptr(sub), child)
					err = walk(file, child, depth+1, ancestors, generated || generatedProjectDirs[name])
					file.Close()
					if err != nil {
						return err
					}
					continue
				}
				if st.Mode&unix.S_IFMT != unix.S_IFREG || st.Size < 0 {
					result.Skipped++
					continue
				}
				key := inode{uint64(st.Dev), st.Ino}
				if _, exists := seen[key]; exists {
					continue
				}
				seen[key] = struct{}{}
				for _, index := range ancestors {
					project := &projects[index]
					if st.Size > math.MaxInt64-project.value.Size {
						project.value.Size = math.MaxInt64
						result.Skipped++
					} else {
						project.value.Size += st.Size
					}
					if !generated {
						modified := st.Mtim.Sec*1000 + st.Mtim.Nsec/1e6
						if modified > project.latest {
							project.latest = modified
						}
					}
				}
			}
			if readErr == io.EOF {
				return nil
			}
			if readErr != nil {
				result.Skipped++
				return nil
			}
		}
	}
	err = walk(rootFile, root, 0, nil, false)
	if errors.Is(err, errStorageLimit) {
		result.Truncated = true
	} else if err != nil {
		return result, err
	}
	for _, state := range projects {
		if state.latest > 0 {
			state.value.LastActivityMs = &state.latest
		}
		result.Projects = append(result.Projects, state.value)
	}
	sort.Slice(result.Projects, func(i, j int) bool {
		a, b := result.Projects[i].LastActivityMs, result.Projects[j].LastActivityMs
		if a == nil || b == nil {
			if (a == nil) != (b == nil) {
				return b == nil
			}
		} else if *a != *b {
			return *a < *b
		}
		if result.Projects[i].Size != result.Projects[j].Size {
			return result.Projects[i].Size > result.Projects[j].Size
		}
		return strings.ToLower(result.Projects[i].Path) < strings.ToLower(result.Projects[j].Path)
	})
	return result, nil
}
