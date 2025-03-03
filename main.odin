package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:text/i18n"
import "core:thread"
import "core:sync"
import "core:time"
import rl "vendor:raylib"

WIDTH :: 1280
HEIGHT :: 720
VERSION :: "version 1"

FONT_DATA :: #load("fonts/Inter/Inter-Regular.ttf")
FONT_SIZE :: 24
MOVEMENT_SPEED :: 50
ZOOM_SPEED :: 0.25
KEY_REPEAT_MILLIS :: 50

usage :: proc(programName: string) {
	fmt.println("Usage:", programName, "[OPTIONS] [.ARW file]")
	fmt.println("Preview Sony a6000 .ARW files")
	fmt.println("")
	fmt.println("      --close-on-first-frame close on first frame drawn (startup profiling purposes)")
	fmt.println("      --verbose output debug information")
	fmt.println("  -v, --version output version information and exit")
	fmt.println("  -h, --help    display this help and exit")
}

fit_camera_to_image :: proc(camera: ^rl.Camera2D, screenWidth, screenHeight, textureWidth, textureHeight: f32) {
	camera.zoom = min(screenWidth / textureWidth, screenHeight / textureHeight)
	camera.offset = {screenWidth / 2, screenHeight / 2}
	camera.target = {textureWidth / 2, textureHeight / 2}
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	if len(os.args) < 2 {
		usage(os.args[0])
		os.exit(0)
	}

	filename: string

	hasCloseOnFirstFrameFlag := false
	hasVerboseFlag := false
	hasVersionFlag := false
	hasHelpFlag := false
	for i := 1; i < len(os.args); i += 1 {
		arg := os.args[i]
		if arg == "-v" || arg == "--version" {
			hasVersionFlag = true
		} else if arg == "--verbose" {
			hasVerboseFlag = true
		} else if arg == "-h" || arg == "--help" {
			hasHelpFlag = true
		} else if arg == "--close-on-first-frame" {
			hasCloseOnFirstFrameFlag = true
		} else {
			filename = arg
		}
	}

	if hasHelpFlag {
		usage(os.args[0])
		os.exit(0)
	}

	if hasVersionFlag {
		fmt.println("arw-preview2", VERSION)
		os.exit(0)
	}

	if filename == "" {
		usage(os.args[0])
		os.exit(0)
	}

	if !hasVerboseFlag {
		rl.SetTraceLogLevel(.ERROR)
	}

	imagePointer: ^rl.Image
	imagePointerMutex: sync.Mutex
	// TODO: Implement this
	//imageLoadErrorShouldExit := false

	defer {
		sync.lock(&imagePointerMutex)
		free(imagePointer)
		sync.unlock(&imagePointerMutex)
	}

	thread.create_and_start_with_poly_data4(
		&imagePointer,
		&imagePointerMutex,
		hasVerboseFlag,
		filename,
		proc(imagePointer: ^^rl.Image, imagePointerMutex: ^sync.Mutex, hasVerboseFlag: bool, filename: string) {
			image, logText, err := load_jpeg_image_preview_from_filename(filename)
			defer delete(logText)

			if err == .None {
				if hasVerboseFlag {
					fmt.print(logText)
				}

				sync.lock(imagePointerMutex)
				imagePointer^ = image
				sync.unlock(imagePointerMutex)
			} else {
				#partial switch err {
				case .FailedToReadFile:
					fmt.println("Failed to read file:", filename)
				case .TooSmallData:
					fmt.println("Too small file")
				case .MissingHeader:
					fmt.println("Missing header, not a little-endian TIFF file")
				case .InvalidIFDOffset:
					fmt.println("Found an IFD offset not beginning on a word boundary, or zero")
				case .InvalidValueOffset:
					fmt.println("Invalid value offset. Found a value not beginning on a word boundary")
				case .NoPreviewImage:
					fmt.println("No preview image found!")
				}

				// Signal the main thread to print the error and os.exit(1)
				//sync.atomic_store(&imageLoadErrorShouldExit, true)
				os.exit(1)
			}
		},
		init_context=context, // So we can track its memory usage
		self_cleanup=true,
	)

	texture: rl.Texture

	// .VSYNC_HINT slows down my computer when focusing other windows for some reason
	// So I just manually SetTargetFPS() to the monitor refresh rate
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(WIDTH, HEIGHT, "arw-preview2")
	defer rl.CloseWindow()
	rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()))

	theFont := rl.LoadFontFromMemory(
		".ttf",
		raw_data(FONT_DATA),
		i32(len(FONT_DATA)),
		FONT_SIZE,
		nil,
		0,
	)

	camera: rl.Camera2D
	camera.zoom = 1.0
	fpsTextStringBuilder := strings.builder_make()
	fpsTextEnabled := false
	defer strings.builder_destroy(&fpsTextStringBuilder)

	hasResized := false

	keyPressRepeatTime := time.now()
	start := time.now()

	for !rl.WindowShouldClose() {
		shouldQuit := false

		sync.lock(&imagePointerMutex)
		if imagePointer != nil {
			texture = rl.LoadTextureFromImage(imagePointer^)
			rl.UnloadImage(imagePointer^)
			imagePointer = nil
			fit_camera_to_image(&camera, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()), f32(texture.width), f32(texture.height))
			if hasCloseOnFirstFrameFlag {
				shouldQuit = true
			}
		}
		sync.unlock(&imagePointerMutex)

		// raylib doesn't respect my keybinds, so force it to also close on caps lock
		if rl.IsKeyDown(.Q) || rl.IsKeyDown(.CAPS_LOCK) {
			break
		}

		if rl.IsMouseButtonDown(.LEFT) ||
		   rl.IsMouseButtonDown(.RIGHT) ||
		   rl.IsMouseButtonDown(.MIDDLE) {
			rl.SetMouseCursor(.RESIZE_ALL)
			delta := rl.GetMouseDelta()
			delta = delta * (-1.0 / camera.zoom)
			camera.target += delta
		} else {
			rl.SetMouseCursor(.DEFAULT)
		}

		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			mouseWorldPos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
			camera.offset = rl.GetMousePosition()
			camera.target = mouseWorldPos
			scaleFactor := 1.0 + (ZOOM_SPEED * abs(wheel))
			if wheel < 0 do scaleFactor = 1.0 / scaleFactor
			camera.zoom *= scaleFactor
		}

		firstResize := false
		if rl.IsWindowResized() {
			camera.offset = {f32(rl.GetScreenWidth()) / 2, f32(rl.GetScreenHeight()) / 2}
			if !hasResized {
				hasResized = true
				firstResize = true
			}
		}


		// Fit the image size to the screen
		// We also do this on the first resize event within 60ms of startup, because Linux window managers...
		if (firstResize && time.since(start) < 60 * time.Millisecond) ||
		   rl.IsGestureDetected(.DOUBLETAP) ||
		   rl.IsKeyPressed(.ENTER) ||
		   rl.IsKeyPressed(.SPACE) {
			fit_camera_to_image(&camera, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()), f32(texture.width), f32(texture.height))
			firstResize = false
		}

		isCtrlDown := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		didZoom := false
		allowKeyRepeat := time.since(keyPressRepeatTime) > KEY_REPEAT_MILLIS * time.Millisecond
		if allowKeyRepeat {
			keyPressRepeatTime = time.now()

			left, right, up, down := false, false, false, false
			left |= rl.IsKeyDown(.A)
			right |= rl.IsKeyDown(.D)
			up |= rl.IsKeyDown(.W)
			down |= rl.IsKeyDown(.S)

			if isCtrlDown {
				left |= rl.IsKeyDown(.LEFT)
				right |= rl.IsKeyDown(.RIGHT)
				up |= rl.IsKeyDown(.UP)
				down |= rl.IsKeyDown(.DOWN)
			} else {
				if rl.IsKeyDown(.UP) {
					didZoom = true
					camera.zoom *= 1 + ZOOM_SPEED
				} else if rl.IsKeyDown(.DOWN) {
					didZoom = true
					camera.zoom *= 1.0 / (1 + ZOOM_SPEED)
				}
			}

			movementVector := [2]f32 {
				f32(int(right)) - f32(int(left)),
				f32(int(down)) - f32(int(up)),
			}
			camera.target += movementVector * (MOVEMENT_SPEED / camera.zoom)
		}

		if !didZoom {
			charPressed := rl.GetCharPressed()
			if charPressed == '+' do camera.zoom *= 1 + ZOOM_SPEED
			else if charPressed == '-' do camera.zoom *= 1.0 / (1 + ZOOM_SPEED)
		}

		if rl.IsKeyPressed(.LEFT_SHIFT) || rl.IsKeyPressed(.RIGHT_SHIFT) {
			fpsTextEnabled = !fpsTextEnabled
		}

		camera.zoom = min(10_000, camera.zoom)
		camera.zoom = max(0.01, camera.zoom)

		rl.BeginDrawing()
		rl.BeginMode2D(camera)
		rl.ClearBackground({53, 53, 53, 255})
		rl.DrawTexture(texture, 0, 0, rl.WHITE)

		if camera.zoom > 13 {
			draw_grid(texture.width, texture.height, {255, 255, 255, 40})
		}
		rl.EndMode2D()

		if fpsTextEnabled {
			buf: [16]byte
			fpsText := strconv.itoa(buf[:], int(rl.GetFPS()))
			strings.write_string(&fpsTextStringBuilder, fpsText)
			strings.write_string(&fpsTextStringBuilder, " fps")
			rl.DrawTextEx(
				theFont,
				strings.to_cstring(&fpsTextStringBuilder),
				{5, 5},
				FONT_SIZE,
				0,
				{0, 255, 0, 255},
			)
			strings.builder_reset(&fpsTextStringBuilder)
		}

		rl.EndDrawing()

		if shouldQuit {
			break
		}

		//fmt.println(track.current_memory_allocated)
	}
}
