//go:build linux && !amd64 && !arm64

package ipc

func imageWorkerSyscalls() (uint32, []uint32) {
	return 0, nil
}
