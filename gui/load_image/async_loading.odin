package load_image

import "core:os"
import "core:sync"
import rl "vendor:raylib"
import thread "core:thread"

// FIXME: Better struct name
ImageBuf :: struct {
	mutex: ^sync.Mutex,

	imagePointers: [16]^rl.Image, // Remember, 2x memory usage peak
	imagePointersIndex: int,

	directoryPath: string,
	files: ^[]os.File_Info,
	filesIndex: int,
}

init_imagebuf :: proc(imageBuf: ^ImageBuf, directoryPath: string) {
	imageBuf.mutex = new(sync.Mutex)
	imageBuf.directoryPath = directoryPath
}

delete_imagebuf :: proc(imageBuf: ^ImageBuf) {
	sync.lock(imageBuf.mutex)
	defer sync.unlock(imageBuf.mutex)

	free(imageBuf.files)

	for imagePointer in imageBuf.imagePointers {
		if imagePointer != nil {
			rl.UnloadImage(imagePointer^) // ~0.636ms per call
		}
	}
}

// Need to manually lock/unlock this!
// sync.lock(imageBuf.mutex)
// ... = load_image.get_currently_selected_image(imageBuf)
// sync.unlock(imageBuf.mutex)
get_currently_selected_image :: proc(imageBuf: ^ImageBuf) -> ^rl.Image {
	return imageBuf.imagePointers[imageBuf.imagePointersIndex]
}

load_single_image :: proc(imageBuf: ^ImageBuf, filename: string, index: int) -> (logString: string, err: ImageLoadingError) {
	image, logText, loadErr := load_image_preview_from_filename(filename)
	defer delete(logText)

	if loadErr != .None {
		// Do we want to UnloadImage here?
		return logText, loadErr
	}

	sync.lock(imageBuf.mutex)

	// This just calls free() in C
	if imageBuf.imagePointers[index] != nil {
		rl.UnloadImage(imageBuf.imagePointers[index]^) // ~0.636ms on my computer ITS FINEEEEE
	}

	imageBuf.imagePointers[index] = image
	sync.unlock(imageBuf.mutex)

	return "", .None
}

trigger :: proc(imageBuf: ^ImageBuf, leftOrRight: bool) -> (success: bool) {
	sync.lock(imageBuf.mutex)
	defer sync.unlock(imageBuf.mutex) //

	if imageBuf.files == nil {
		loadSuccess := load_directory(imageBuf)
		if !loadSuccess {
			return false
		}
	}

	for i := 1; i <= 4; i += 1 {
		offset := i
		if leftOrRight {
			offset *= -1
		}

		idx := (imageBuf.filesIndex + offset) // % len(imageBuf.files) // FIXME
		if idx >= len(imageBuf.files) {
			idx = len(imageBuf.files) - 1
		} else if idx < 0 {
			idx = 0
		}

		// TODO: Do we want a waitgroup? How do we handle errors?
		thread.create_and_start_with_poly_data2(
			imageBuf,
			idx,
			proc(imageBuf: ^ImageBuf, idx: int) {
				load_single_image(imageBuf, imageBuf.files[idx].fullpath, imageBuf.imagePointersIndex)
			},
			init_context=context, // So we can track its memory usage (???)
			self_cleanup=true,
		)
	}
	imageBuf.filesIndex += 4

	return true
}

// Needs to be manually locked
load_directory :: proc(imageBuf: ^ImageBuf) -> (success: bool) {
	fd, err := os.open(imageBuf.directoryPath)
	if err != nil {
		return false
	}
	defer os.close(fd)

	files: []os.File_Info
	files, err = os.read_dir(fd, 0)
	if err != nil {
		return false
	}

	//sync.lock(imageBuf.mutex)
	imageBuf.files = &files
	//sync.unlock(imageBuf.mutex)

	return true
}
