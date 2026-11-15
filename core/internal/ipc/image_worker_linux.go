//go:build linux && (amd64 || arm64)

package ipc

import (
	"fmt"
	"runtime"
	"unsafe"

	"golang.org/x/sys/unix"
)

func lockImageWorker() error {
	arch, blocked := imageWorkerSyscalls()
	if arch == 0 {
		return fmt.Errorf("image export helper is unsupported on %s", runtime.GOARCH)
	}
	if err := unix.Setrlimit(unix.RLIMIT_CPU, &unix.Rlimit{Cur: 180, Max: 180}); err != nil {
		return fmt.Errorf("set image export CPU limit: %w", err)
	}
	if err := unix.Setrlimit(unix.RLIMIT_FSIZE, &unix.Rlimit{Cur: 512 << 20, Max: 512 << 20}); err != nil {
		return fmt.Errorf("set image export output limit: %w", err)
	}
	if err := unix.Prctl(unix.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0); err != nil {
		return fmt.Errorf("set no-new-privileges: %w", err)
	}
	filters := []unix.SockFilter{
		{Code: unix.BPF_LD | unix.BPF_W | unix.BPF_ABS, K: 4},
		{Code: unix.BPF_JMP | unix.BPF_JEQ | unix.BPF_K, Jt: 1, K: arch},
		{Code: unix.BPF_RET | unix.BPF_K, K: unix.SECCOMP_RET_KILL_PROCESS},
		{Code: unix.BPF_LD | unix.BPF_W | unix.BPF_ABS, K: 0},
	}
	for _, number := range blocked {
		filters = append(filters,
			unix.SockFilter{Code: unix.BPF_JMP | unix.BPF_JEQ | unix.BPF_K, Jf: 1, K: number},
			unix.SockFilter{Code: unix.BPF_RET | unix.BPF_K, K: unix.SECCOMP_RET_ERRNO | uint32(unix.EACCES)},
		)
	}
	filters = append(filters, unix.SockFilter{Code: unix.BPF_RET | unix.BPF_K, K: unix.SECCOMP_RET_ALLOW})
	program := unix.SockFprog{Len: uint16(len(filters)), Filter: &filters[0]}
	runtime.LockOSThread()
	_, _, errno := unix.Syscall(unix.SYS_SECCOMP, unix.SECCOMP_SET_MODE_FILTER, unix.SECCOMP_FILTER_FLAG_TSYNC, uintptr(unsafe.Pointer(&program)))
	runtime.KeepAlive(filters)
	runtime.KeepAlive(&program)
	if errno != 0 {
		return fmt.Errorf("install image export seccomp filter: %w", errno)
	}
	if fd, err := unix.Openat(unix.AT_FDCWD, "/", unix.O_RDONLY, 0); err == nil {
		_ = unix.Close(fd)
		return fmt.Errorf("image export sandbox still permits filesystem access")
	}
	if fd, err := unix.Socket(unix.AF_INET, unix.SOCK_STREAM, 0); err == nil {
		_ = unix.Close(fd)
		return fmt.Errorf("image export sandbox still permits network access")
	}
	return nil
}
