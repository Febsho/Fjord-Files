package main

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/duxlabs-dev/dux-files/core/internal/blur"
)

var blurCmd = &cobra.Command{
	Use:   "blur",
	Short: "Background blur utilities",
}

var blurCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Report whether the compositor supports ext-background-effect-v1 blur",
	Args:  cobra.NoArgs,
	RunE: func(_ *cobra.Command, _ []string) error {
		supported, err := blur.ProbeSupport()
		if err != nil {
			return err
		}
		fmt.Println(blurVerdict(supported))
		return nil
	},
}

var blurUmbrielEnabled bool
var blurUmbrielRadius int

var blurUmbrielCmd = &cobra.Command{
	Use:   "umbriel",
	Short: "Set the Umbriel background blur for Fjord Files",
	Args:  cobra.NoArgs,
	RunE: func(_ *cobra.Command, _ []string) error {
		return blur.ConfigureUmbriel(blurUmbrielEnabled, blurUmbrielRadius)
	},
}

func blurVerdict(supported bool) string {
	if supported {
		return "supported"
	}
	return "unsupported"
}

func init() {
	blurUmbrielCmd.Flags().BoolVar(&blurUmbrielEnabled, "enabled", false, "Enable blur for Fjord Files")
	blurUmbrielCmd.Flags().IntVar(&blurUmbrielRadius, "radius", 8, "Blur radius from 0 to 100")
	blurCmd.AddCommand(blurCheckCmd)
	blurCmd.AddCommand(blurUmbrielCmd)
}
