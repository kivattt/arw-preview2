package main

import "core:fmt"
import "core:text/i18n"
import "core:mem"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

WIDTH :: 1280
HEIGHT :: 720
VERSION :: "version 1"

usage :: proc(programName: string) {
	fmt.println("Usage:", programName, "[OPTIONS] [.ARW file]")
	fmt.println("Preview Sony a6000 .ARW files")
	fmt.println("")
	fmt.println("      --verbose output ")
	fmt.println("  -v, --version output version information and exit")
}

ParseError :: enum {
	None = 0,
	TooSmallData,
	MissingHeader,
	InvalidValueOffset,
	InvalidIFDOffset,
	NoPreviewImage,
}

get_jpeg_image_preview_from_arw_data :: proc(data: ^[]u8) -> (previewImageStart, previewImageLength: u32, err: ParseError) {
	if len(data) < 8 {
		return 0, 0, .TooSmallData
	}

	if mem.compare(data[:4], {'I', 'I', 0x2a, 0x00}) != 0 {
		return 0, 0, .MissingHeader
	}

	// The data length passed to read_u32 is constant and won't error.
	firstIFDOffset, _ := i18n.read_u32(data[4:8])

	if firstIFDOffset == 0 || firstIFDOffset % 2 != 0 {
		return 0, 0, .InvalidIFDOffset
	}

	if len(data) < int(firstIFDOffset+2) {
		return 0, 0, .TooSmallData
	}
	// The data length passed to read_u16 is constant and won't error.
	numDirEntries, _ := i18n.read_u16(data[firstIFDOffset:firstIFDOffset+2])

	// TODO: Do we need to free this?
	typeToByteCount := make(map[u16]u32)
	defer delete(typeToByteCount)
	typeToByteCount[1] = 1
	typeToByteCount[2] = 2
	typeToByteCount[3] = 2
	typeToByteCount[4] = 4
	typeToByteCount[5] = 8

	for i: u16 = 0; i < numDirEntries; i += 1 {
		// FIXME: Our own read_uint16 and read_uint32 functions, and handle possible length errors here!
		offset := firstIFDOffset + 2 + u32(i*12)
		tag, _ := i18n.read_u16(data[offset:offset+2])
		type, _ := i18n.read_u16(data[offset+2:offset+2+2])
		numValues, _ := i18n.read_u32(data[offset+4:offset+4+4])
		valueOffset, _ := i18n.read_u32(data[offset+8:offset+8+4])

		valueSize := typeToByteCount[type] * numValues

		// The value offset instead contains the data when the value size is <= 4
		valueOffsetIsValue := valueSize <= 4

		if valueOffsetIsValue {
			if tag == 0x0201 {
				previewImageStart = valueOffset
			} else if tag == 0x0202 {
				previewImageLength = valueOffset
				return previewImageStart, previewImageLength, .None
			}
		} else {
			if valueOffset % 2 != 0 {
				return 0, 0, .InvalidValueOffset
			}
		}
	}

	return 0, 0, .NoPreviewImage
}

main :: proc() {
	if len(os.args) < 2 {
		usage(os.args[0])
		os.exit(0)
	}

	filename: string

	hasVerboseFlag := false
	hasVersionFlag := false
	for i := 1; i < len(os.args); i += 1 {
		arg := os.args[i]
		if arg == "-v" || arg == "--version" {
			hasVersionFlag = true
		} else if arg == "--verbose" {
			hasVerboseFlag = true
		} else {
			filename = arg
		}
	}

	if filename == "" {
		usage(os.args[0])
		os.exit(0)
	}

	if hasVersionFlag {
		fmt.println("arw-preview2", VERSION)
		os.exit(0)
	}

	if !hasVerboseFlag {
		rl.SetTraceLogLevel(.ERROR)
	}

	data, success := os.read_entire_file_from_filename(filename)
	if !success {
		fmt.println("Failed to read file:", filename)
		os.exit(1)
	}
	defer delete(data)

	previewImageStart, previewImageLength, err := get_jpeg_image_preview_from_arw_data(&data)
	switch err {
	case .None:
	case .TooSmallData:
		fmt.println("Too small file")
		os.exit(1)
	case .MissingHeader:
		fmt.println("Missing header, not a little-endian TIFF file")
		os.exit(1)
	case .InvalidIFDOffset:
		fmt.println("Found an IFD offset not beginning on a word boundary, or zero")
		os.exit(1)
	case .InvalidValueOffset:
		fmt.println("Invalid value offset. Found a value not beginning on a word boundary")
		os.exit(1)
	case .NoPreviewImage:
		fmt.println("No preview image found!")
		os.exit(1)
	}

	// .VSYNC_HINT slows down my computer when focusing other windows for some reason
	// So I just manually SetTargetFPS() to the monitor refresh rate
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(WIDTH, HEIGHT, "arw-preview2")
	defer rl.CloseWindow()

	if hasVerboseFlag {
		fmt.print("\x1b[1;32m")
		fmt.println("preview image start  :", previewImageStart)
		fmt.println("preview image length :", previewImageLength)
		fmt.print("\x1b[0m")
	}

	image := rl.LoadImageFromMemory(".jpg", &data[previewImageStart], i32(previewImageLength))
	texture := rl.LoadTextureFromImage(image)
	rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()))

	for !rl.WindowShouldClose() {
		// raylib doesn't respect my keybinds, so force it to also close on caps lock
		if rl.IsKeyDown(.Q) || rl.IsKeyDown(.CAPS_LOCK) {
			break
		}

		rl.BeginDrawing()
		rl.ClearBackground({53,53,53,255})
		rl.DrawTexture(texture, 0, 0, rl.WHITE)

		if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) || rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {
			rl.DrawFPS(0,0)
		}

		rl.EndDrawing()
	}
}
