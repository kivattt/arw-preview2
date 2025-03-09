package gui

import "core:os"
import "core:fmt"
import "core:mem"
import "core:time"
import "core:sync"
import "core:thread"
import rl "vendor:raylib"
import "load_image"
import "core:path/filepath"

WIDTH :: 1280
HEIGHT :: 720
FONT_SIZE :: 24
MOVEMENT_SPEED :: 50
ZOOM_SPEED :: 0.25
KEY_REPEAT_MILLIS :: 50
FRAME_TIME_DURATION_MILLIS :: 800
TEXT_DROPSHADOW_OFFSET :: 1
TEXT_DROPSHADOW_ALPHA :: 100

Gui :: struct {
	camera: rl.Camera2D,
	texture: rl.Texture,
	frameTimeTimer: time.Time,
	frameTimeMin: f64,
	frameTimeMax: f64,
	frameTimeAvg: f64,

	frameTimeMinText: cstring,
	frameTimeMaxText: cstring,
	frameTimeAvgText: cstring,

	framesElapsed: int,
	lastNFramesElapsed: int,

	fpsTextEnabled: bool,
	font: rl.Font,

	hasResized: bool,
	startTime: time.Time,
	keyPressRepeatTime: time.Time,

	imageBuf: load_image.ImageBuf,
}

@(private)
init_gui :: proc(gui: ^Gui, fontData: []u8) {
	gui.font = rl.LoadFontFromMemory(
		".ttf",
		raw_data(fontData),
		i32(len(fontData)),
		FONT_SIZE,
		nil,
		0,
	)

	gui.camera.zoom = 1.0
	gui.frameTimeTimer = time.now()
	gui.frameTimeMin = max(f64)
	gui.frameTimeMax = 0
	gui.frameTimeAvg = 0
	gui.startTime = time.now()
	gui.keyPressRepeatTime = time.now()
}

ImageLoadThreadData :: struct {
	imageBuf: ^load_image.ImageBuf,
	/*imagePointer: ^^rl.Image,
	imagePointerMutex: ^sync.Mutex,*/
	imageLoadErrorShouldExit: ^bool,
	hasVerboseFlag: bool,
	filename: string,
}

@(private)
handle_inputs :: proc(gui: ^Gui) -> (exit: bool) {
	// raylib doesn't respect my keybinds, so force it to also close on caps lock
	if rl.IsKeyDown(.Q) || rl.IsKeyDown(.CAPS_LOCK) {
		return true
	}

	if rl.IsMouseButtonDown(.LEFT) ||
	   rl.IsMouseButtonDown(.RIGHT) ||
	   rl.IsMouseButtonDown(.MIDDLE) {
		rl.SetMouseCursor(.RESIZE_ALL)
		delta := rl.GetMouseDelta()
		delta = delta * (-1.0 / gui.camera.zoom)
		gui.camera.target += delta
	} else {
		rl.SetMouseCursor(.DEFAULT)
	}

	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		mouseWorldPos := rl.GetScreenToWorld2D(rl.GetMousePosition(), gui.camera)
		gui.camera.offset = rl.GetMousePosition()
		gui.camera.target = mouseWorldPos
		scaleFactor := 1.0 + (ZOOM_SPEED * abs(wheel))
		if wheel < 0 do scaleFactor = 1.0 / scaleFactor
		gui.camera.zoom *= scaleFactor
	}

	firstResize := false
	if rl.IsWindowResized() {
		gui.camera.offset = {f32(rl.GetScreenWidth()) / 2, f32(rl.GetScreenHeight()) / 2}
		if !gui.hasResized {
			gui.hasResized = true
			firstResize = true
		}
	}

	// Fit the image size to the screen
	// We also do this on the first resize event within 60ms of startup, because Linux window managers...
	if (firstResize && time.since(gui.startTime) < 60 * time.Millisecond) ||
	   rl.IsGestureDetected(.DOUBLETAP) ||
	   rl.IsKeyPressed(.ENTER) ||
	   rl.IsKeyPressed(.SPACE) {
		fit_camera_to_image(&gui.camera, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()), f32(gui.texture.width), f32(gui.texture.height))
		firstResize = false
	}

	isCtrlDown := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	didZoom := false
	allowKeyRepeat := time.since(gui.keyPressRepeatTime) > KEY_REPEAT_MILLIS * time.Millisecond
	if allowKeyRepeat {
		gui.keyPressRepeatTime = time.now()

		left, right, up, down := false, false, false, false
		left |= rl.IsKeyDown(.A)
		right |= rl.IsKeyDown(.D)
		up |= rl.IsKeyDown(.W)
		down |= rl.IsKeyDown(.S)

		if isCtrlDown {
			left |= rl.IsKeyDown(.LEFT) | rl.IsKeyDown(.H)
			right |= rl.IsKeyDown(.RIGHT) | rl.IsKeyDown(.L)
			up |= rl.IsKeyDown(.UP) | rl.IsKeyDown(.K)
			down |= rl.IsKeyDown(.DOWN) | rl.IsKeyDown(.J)
		} else {
			if rl.IsKeyDown(.UP) || rl.IsKeyDown(.K) {
				didZoom = true
				gui.camera.zoom *= 1 + ZOOM_SPEED
			} else if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.J) {
				didZoom = true
				gui.camera.zoom *= 1.0 / (1 + ZOOM_SPEED)
			}

			if rl.IsKeyPressed(.LEFT) {
				load_image.trigger(&gui.imageBuf, false)
			} else if rl.IsKeyPressed(.RIGHT) {
				load_image.trigger(&gui.imageBuf, true)
			}
		}

		movementVector := [2]f32 {
			f32(int(right)) - f32(int(left)),
			f32(int(down)) - f32(int(up)),
		}
		gui.camera.target += movementVector * (MOVEMENT_SPEED / gui.camera.zoom)
	}

	if !didZoom {
		charPressed := rl.GetCharPressed()
		if charPressed == '+' do gui.camera.zoom *= 1 + ZOOM_SPEED
		else if charPressed == '-' do gui.camera.zoom *= 1.0 / (1 + ZOOM_SPEED)
	}

	if rl.IsKeyPressed(.LEFT_SHIFT) || rl.IsKeyPressed(.RIGHT_SHIFT) {
		gui.fpsTextEnabled = !gui.fpsTextEnabled
	}

	gui.camera.zoom = min(10_000, gui.camera.zoom)
	gui.camera.zoom = max(0.01, gui.camera.zoom)

	return false
}

@(private)
fit_camera_to_image :: proc(camera: ^rl.Camera2D, screenWidth, screenHeight, textureWidth, textureHeight: f32) {
	camera.zoom = min(screenWidth / textureWidth, screenHeight / textureHeight)
	camera.offset = {screenWidth / 2, screenHeight / 2}
	camera.target = {textureWidth / 2, textureHeight / 2}
}

@(private)
draw :: proc(gui: ^Gui) {
	rl.BeginMode2D(gui.camera)
	rl.ClearBackground({53, 53, 53, 255})
	rl.DrawTexture(gui.texture, 0, 0, rl.WHITE)

	if gui.camera.zoom > 13 {
		draw_grid(gui.texture.width, gui.texture.height, {255, 255, 255, 40})
	}
	rl.EndMode2D()

	gui.framesElapsed += 1
	frameTimeMillis := f64(rl.GetFrameTime()) * 1000
	gui.frameTimeMin = frameTimeMillis < gui.frameTimeMin ? frameTimeMillis : gui.frameTimeMin
	gui.frameTimeMax = frameTimeMillis > gui.frameTimeMax ? frameTimeMillis : gui.frameTimeMax
	gui.frameTimeAvg += frameTimeMillis / f64(gui.lastNFramesElapsed)

	if time.since(gui.frameTimeTimer) > FRAME_TIME_DURATION_MILLIS * time.Millisecond {
		gui.frameTimeTimer = time.now()

		gui.frameTimeMinText = fmt.ctprintf("min: %.3fms", gui.frameTimeMin)
		gui.frameTimeMaxText = fmt.ctprintf("max: %.3fms", gui.frameTimeMax)
		gui.frameTimeAvgText = fmt.ctprintf("avg: %.3fms", gui.frameTimeAvg)

		gui.frameTimeMin = max(f64)
		gui.frameTimeMax = 0
		gui.frameTimeAvg = 0

		gui.lastNFramesElapsed = gui.framesElapsed
		gui.framesElapsed = 0
	}

	if gui.fpsTextEnabled {
		fps := rl.GetFPS()

		// Dropshadow
		rl.DrawTextEx(gui.font, fmt.ctprintf("%v fps", fps), {5 + TEXT_DROPSHADOW_OFFSET, 5 + TEXT_DROPSHADOW_OFFSET,}, FONT_SIZE, 0, {0, 0, 0, TEXT_DROPSHADOW_ALPHA})
		rl.DrawTextEx(gui.font, gui.frameTimeMinText, {f32(rl.GetScreenWidth()) - 530 + TEXT_DROPSHADOW_OFFSET, 5 + TEXT_DROPSHADOW_OFFSET}, FONT_SIZE, 0, {0,0,0,TEXT_DROPSHADOW_ALPHA})
		rl.DrawTextEx(gui.font, gui.frameTimeMaxText, {f32(rl.GetScreenWidth()) - 340 + TEXT_DROPSHADOW_OFFSET, 5 + TEXT_DROPSHADOW_OFFSET}, FONT_SIZE, 0, {0,0,0,TEXT_DROPSHADOW_ALPHA})
		rl.DrawTextEx(gui.font, gui.frameTimeAvgText, {f32(rl.GetScreenWidth()) - 150 + TEXT_DROPSHADOW_OFFSET, 5 + TEXT_DROPSHADOW_OFFSET}, FONT_SIZE, 0, {0,0,0,TEXT_DROPSHADOW_ALPHA})

		rl.DrawTextEx(gui.font, fmt.ctprintf("%v fps", fps), {5, 5}, FONT_SIZE, 0, {200, 200, 200, 255})
		rl.DrawTextEx(gui.font, gui.frameTimeMinText, {f32(rl.GetScreenWidth()) - 530, 5}, FONT_SIZE, 0, {66, 245, 72, 255})
		rl.DrawTextEx(gui.font, gui.frameTimeMaxText, {f32(rl.GetScreenWidth()) - 340, 5}, FONT_SIZE, 0, {245, 93, 66, 255})
		rl.DrawTextEx(gui.font, gui.frameTimeAvgText, {f32(rl.GetScreenWidth()) - 150, 5}, FONT_SIZE, 0, {66, 173, 245, 255})
	}
}


Args :: struct {
	closeOnFirstFrame: bool,
	verbose: bool,
	filename: string,
}

run :: proc(gui: ^Gui, fontData: []u8, args: Args) -> (exitCode: int) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)


	if !args.verbose {
		rl.SetTraceLogLevel(.ERROR)
	}

	/*imagePointer: ^rl.Image
	imagePointerMutex: sync.Mutex*/
	imageLoadErrorShouldExit := false
	load_image.init_imagebuf(&gui.imageBuf, filepath.dir(args.filename))
	defer load_image.delete_imagebuf(&gui.imageBuf)

	/*defer {
		sync.lock(&imagePointerMutex)
		t := time.now()
		free(imagePointer)
		fmt.println("freeing imagepointer took:", time.since(t))
		sync.unlock(&imagePointerMutex)
	}*/

	threadData := ImageLoadThreadData{
		//imagePointer = &imagePointer,
		//imagePointerMutex = &imagePointerMutex,
		imageBuf = &gui.imageBuf,
		imageLoadErrorShouldExit = &imageLoadErrorShouldExit,
		hasVerboseFlag = args.verbose,
		filename = args.filename,
	}

	thread.create_and_start_with_poly_data(
		threadData,
		proc(threadData: ImageLoadThreadData) {
			logText, err := load_image.load_single_image(threadData.imageBuf, threadData.filename, 0)

			//image, logText, err := load_image.load_image_preview_from_filename(threadData.filename)
			//defer delete(logText)

			if err == .None {
				if threadData.hasVerboseFlag {
					fmt.print(logText)
				}

				/*sync.lock(threadData.imagePointerMutex)
				threadData.imagePointer^ = image
				sync.unlock(threadData.imagePointerMutex)*/
			} else {
				// FIXME: Hand the error string over to the main thread for printing
				#partial switch err {
				case .FailedToReadFile:
					fmt.println("Failed to read file:", threadData.filename)
				case .TooSmallData:
					fmt.println("Too small file")
				case .MissingHeader:
					fmt.println("Missing header")
				case .InvalidIFDOffset:
					fmt.println("Found an IFD offset not beginning on a word boundary, or zero")
				case .InvalidValueOffset:
					fmt.println("Invalid value offset. Found a value not beginning on a word boundary")
				case .NoPreviewImage:
					fmt.println("No preview image found!")
				}

				// Signal the main thread to os.exit(1)
				sync.atomic_store(threadData.imageLoadErrorShouldExit, true)
			}
		},
		init_context=context, // So we can track its memory usage
		self_cleanup=true,
	)

	// .VSYNC_HINT slows down my computer when focusing other windows for some reason
	// So I just manually SetTargetFPS() to the monitor refresh rate
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(WIDTH, HEIGHT, "arw-preview2")
	defer rl.CloseWindow()
	rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()))

	init_gui(gui, fontData)

	for !rl.WindowShouldClose() {
		shouldQuit := false

		if sync.atomic_load(threadData.imageLoadErrorShouldExit) {
			exitCode = 1
			break
		}

		sync.lock(gui.imageBuf.mutex)
		imagePointer := load_image.get_currently_selected_image(&gui.imageBuf)
		if imagePointer != nil {
			gui.texture = rl.LoadTextureFromImage(imagePointer^)
			rl.UnloadImage(imagePointer^)

			gui.imageBuf.imagePointers[0] = nil // yolo
			//imagePointer = nil
			fit_camera_to_image(&gui.camera, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()), f32(gui.texture.width), f32(gui.texture.height))
			if args.closeOnFirstFrame {
				shouldQuit = true
			}
		}
		sync.unlock(gui.imageBuf.mutex)

		shouldQuit |= handle_inputs(gui)
		if shouldQuit {
			break
		}

		rl.BeginDrawing()
		draw(gui)
		rl.EndDrawing()

		//fmt.println(track.current_memory_allocated)
	}

	return exitCode
}
