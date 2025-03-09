package main

import "core:os"
import "core:fmt"
import "gui"

VERSION :: "version 1"
FONT_DATA :: #load("fonts/Inter/Inter-Regular.ttf")

usage :: proc(programName: string) {
	fmt.println("Usage:", programName, "[OPTIONS] [.ARW file]")
	fmt.println("Preview Sony a6000 .ARW files")
	fmt.println("")
	fmt.println("      --close-on-first-frame close on first frame drawn (startup profiling purposes)")
	fmt.println("      --verbose output debug information")
	fmt.println("  -v, --version output version information and exit")
	fmt.println("  -h, --help    display this help and exit")
}

main :: proc() {
	if len(os.args) < 2 {
		usage(os.args[0])
		os.exit(0)
	}

	guiArgs: gui.Args

	version := false
	help := false
	for i := 1; i < len(os.args); i += 1 {
		arg := os.args[i]
		if arg == "-v" || arg == "--version" {
			version = true
		} else if arg == "-h" || arg == "--help" {
			help = true
		} else if arg == "--verbose" {
			guiArgs.verbose = true
		} else if arg == "--close-on-first-frame" {
			guiArgs.closeOnFirstFrame = true
		} else {
			guiArgs.filename = arg
		}
	}

	if help {
		usage(os.args[0])
		os.exit(0)
	}

	if version {
		fmt.println("arw-preview2", VERSION)
		os.exit(0)
	}

	if guiArgs.filename == "" {
		usage(os.args[0])
		os.exit(0)
	}

	theGui: gui.Gui
	exitCode := gui.run(&theGui, FONT_DATA, guiArgs)
	os.exit(exitCode)

}
