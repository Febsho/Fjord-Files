package main

import (
	"fmt"
	"os"

	"github.com/duxlabs-dev/dux-files/core/internal/ipc"
	"github.com/duxlabs-dev/dux-files/core/internal/qtbaseembed"
	"github.com/duxlabs-dev/dux-go/log"
	"github.com/duxlabs-dev/dux-go/qtbase"
)

var (
	Version   = "dev"
	BuildTime = "unknown"
	Commit    = "unknown"
)

func main() {
	if len(os.Args) == 2 && (os.Args[1] == "--version" || os.Args[1] == "-V") {
		fmt.Printf("fjord-files %s (commit %s, built %s)\n", Version, Commit, BuildTime)
		return
	}
	if len(os.Args) == 2 && os.Args[1] == "--image-export-worker" {
		if err := ipc.RunImageExportWorkerFromProcess(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	log.SetEnvPrefix("DFILES")
	qtbase.MaybeRunAndExit(qtbaseembed.Extract)
	if err := rootCmd.Execute(); err != nil {
		log.Errorf("%v", err)
		os.Exit(1)
	}
}
