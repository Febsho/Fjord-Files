//go:build linux && amd64

package ipc

import "golang.org/x/sys/unix"

func imageWorkerSyscalls() (uint32, []uint32) {
	return unix.AUDIT_ARCH_X86_64, []uint32{
		unix.SYS_OPEN, unix.SYS_OPENAT, unix.SYS_OPENAT2, unix.SYS_CREAT,
		unix.SYS_UNLINK, unix.SYS_UNLINKAT, unix.SYS_RENAME, unix.SYS_RENAMEAT, unix.SYS_RENAMEAT2,
		unix.SYS_LINK, unix.SYS_LINKAT, unix.SYS_SYMLINK, unix.SYS_SYMLINKAT,
		unix.SYS_SOCKET, unix.SYS_SOCKETPAIR, unix.SYS_CONNECT, unix.SYS_BIND, unix.SYS_LISTEN,
		unix.SYS_ACCEPT, unix.SYS_ACCEPT4, unix.SYS_SENDTO, unix.SYS_RECVFROM,
		unix.SYS_EXECVE, unix.SYS_EXECVEAT, unix.SYS_PTRACE, unix.SYS_MOUNT, unix.SYS_UMOUNT2,
		unix.SYS_CHROOT, unix.SYS_PIVOT_ROOT, unix.SYS_SETNS, unix.SYS_UNSHARE,
		unix.SYS_BPF, unix.SYS_PERF_EVENT_OPEN, unix.SYS_USERFAULTFD, unix.SYS_OPEN_BY_HANDLE_AT,
		unix.SYS_PIDFD_GETFD, unix.SYS_IO_URING_SETUP, unix.SYS_IO_URING_ENTER, unix.SYS_IO_URING_REGISTER,
	}
}
