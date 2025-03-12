package load_image

import "core:os"
import "core:fmt"
import "core:sync"
import "core:path/filepath"
import rl "vendor:raylib"
import thread "core:thread"

Image :: struct {
	imagePtr: ^rl.Image,
	fileInfo: os.File_Info,
}

IMAGE_POINTERS_LEN :: 16

// FIXME: Better struct name
ImageBuf :: struct {
	mutex: ^sync.Mutex,

	//imagePointers: [16]^rl.Image, // Remember, 2x memory usage peak
	imagePointers: [IMAGE_POINTERS_LEN]^Image, // Remember, 2x memory usage peak
	imagePointersIndex: int,

	firstImagePath: string,
	files: ^[]os.File_Info,
	filesIndex: int,
	firstImageIndexRelativeToFiles: int,

	offset: int,
	loadingImages: ^bool, // Atomic
}

init_imagebuf :: proc(imageBuf: ^ImageBuf, firstImagePath: string) {
	imageBuf.mutex = new(sync.Mutex)
	imageBuf.firstImagePath = firstImagePath
	imageBuf.loadingImages = new(bool)
}

delete_imagebuf :: proc(imageBuf: ^ImageBuf) {
	sync.lock(imageBuf.mutex)


	free(imageBuf.files)

	for imagePointer in imageBuf.imagePointers {
		if imagePointer != nil && imagePointer.imagePtr != nil {
			rl.UnloadImage(imagePointer.imagePtr^) // ~0.636ms per call
		}
	}

	free(imageBuf.loadingImages)

	sync.unlock(imageBuf.mutex)
	free(imageBuf.mutex)
}

// Need to manually lock/unlock this!
// sync.lock(imageBuf.mutex)
// ... = load_image.get_currently_selected_image(imageBuf)
// sync.unlock(imageBuf.mutex)
get_currently_selected_image :: proc(imageBuf: ^ImageBuf) -> ^rl.Image {
	return imageBuf.imagePointers[imageBuf.imagePointersIndex].imagePtr
}

load_single_image :: proc(imageBuf: ^ImageBuf, filename: string, index: int) -> (logString: string, err: ImageLoadingError) {
	if imageBuf.mutex == nil {
		panic("EPIC FAIL 2")
	}

	image, logText, loadErr := load_image_preview_from_filename(filename)
	defer delete(logText)

	if loadErr != .None {
		// Do we want to UnloadImage here?
		return logText, loadErr
	}

	fileInfo, statErr := os.stat(filename)
	if statErr != nil {
		return "Failed to stat file", .FailedToReadFile
	}

	sync.lock(imageBuf.mutex)

	if imageBuf.imagePointers[index] != nil {
		// This just calls free() in C
		//rl.UnloadImage(imageBuf.imagePointers[index]^) // ~0.636ms on my computer ITS FINEEEEE
		rl.UnloadImage(imageBuf.imagePointers[index].imagePtr^) // ~0.636ms on my computer ITS FINEEEEE
		free(imageBuf.imagePointers[index])
	}

	imageBuf.imagePointers[index] = new(Image)
	imageBuf.imagePointers[index]^ = Image{
		imagePtr = image,
		fileInfo = fileInfo,
	}
	sync.unlock(imageBuf.mutex)

	return "", .None
}

wrap :: proc(index: int, len: int) -> int {
	if index < 0 {
		return max(0, len + index)
	}
	return index % len
}

next_image :: proc(imageBuf: ^ImageBuf) {
	sync.lock(imageBuf.mutex)
	defer sync.unlock(imageBuf.mutex)

	nextIndex := wrap(imageBuf.imagePointersIndex + 1, IMAGE_POINTERS_LEN)
	if imageBuf.imagePointers[nextIndex] == nil { // TODO: Check timestamp or something
		return
	}

	imageBuf.imagePointersIndex = nextIndex

	fmt.println("next img", imageBuf.offset)
	if imageBuf.offset >= 2 {
		fmt.println("loading imgs!", imageBuf.offset)
		//try_load_images(imageBuf, imageBuf.files[fileIndexStart:4], imageBuf.imagePointersIndex)
		try_load_images(imageBuf)
	}
	imageBuf.offset += 1
}

prev_image :: proc(imageBuf: ^ImageBuf) {
	sync.lock(imageBuf.mutex)
	defer sync.unlock(imageBuf.mutex)

	nextIndex := wrap(imageBuf.imagePointersIndex - 1, IMAGE_POINTERS_LEN)
	if imageBuf.imagePointers[nextIndex] == nil {
		return
	}

	imageBuf.offset -= 1
	imageBuf.imagePointersIndex = nextIndex
}

// Doesn't lock the mutex!
// Returns -1 if none found
image_index_to_file_index :: proc(imageBuf: ^ImageBuf, index: int) -> int {
	//sync.lock(imageBuf.mutex)
	//defer sync.unlock(imageBuf.mutex)

	// Maybe filepath.clean() or something here?
	pathLookingFor, success := filepath.abs(imageBuf.imagePointers[index].fileInfo.fullpath)
	if !success {
		return -1
	}

	for file, i in imageBuf.files {
		if file.fullpath == pathLookingFor {
			return i
		}
	}

	return -1
}

AsyncLoadThreadData :: struct {
	imageBuf: ^ImageBuf,
	files: []os.File_Info,
	imageIndex: int,
}

LoadSingleImageThreadData :: struct {
	imageBuf: ^ImageBuf,
	file: os.File_Info,
	imageIndex: int,
}

try_load_images :: proc(imageBuf: ^ImageBuf) {
	if sync.atomic_load(imageBuf.loadingImages) {
		return
	}

	sync.atomic_store(imageBuf.loadingImages, true)

	if imageBuf == nil {
		panic("EPIC FAIL 1")
	}

	if imageBuf.files == nil {
		loadSuccess := load_directory(imageBuf)
		if !loadSuccess {
			return // epic fail
		}
	}

	imageIndex := image_index_to_file_index(imageBuf, imageBuf.imagePointersIndex)
	if imageIndex == -1 {
		return
	}
	fmt.println("imageIndex:", imageIndex)
	fmt.println("len(files):", len(imageBuf.files))

	data := new(AsyncLoadThreadData)
	defer free(data)
	data.imageBuf = imageBuf
	data.files = imageBuf.files[imageIndex:imageIndex+4]
	data.imageIndex = imageIndex

	thread.create_and_start_with_poly_data(
		data,
		proc(data: ^AsyncLoadThreadData) {
			threads: [4]^thread.Thread
			for i := 0; i < 4; i += 1 {
				threadData := new(LoadSingleImageThreadData)
				defer free(threadData)
				threadData.imageBuf = data.imageBuf
				//threadData.file = data.files[data.imageIndex + i]
				threadData.file = data.files[i]
				threadData.imageIndex = data.imageIndex
				threads[i] = thread.create_and_start_with_poly_data(
					threadData,
					proc(data: ^LoadSingleImageThreadData) {
						load_single_image(data.imageBuf, data.file.fullpath, data.imageIndex)
					},
					init_context = context, // So we can track its memory usage (???)
				)
			}

			//thread.join_multiple(threads[0], threads[1], threads[2], threads[3])
			thread.destroy(threads[0])
			thread.destroy(threads[1])
			thread.destroy(threads[2])
			thread.destroy(threads[3])
			sync.atomic_store(data.imageBuf.loadingImages, false)
			fmt.println("loading finished!")
		},
		init_context = context, // So we can track its memory usage (???)
		self_cleanup = true,
	)
}

trigger :: proc(imageBuf: ^ImageBuf, leftOrRight: bool) -> (success: bool) {
	sync.lock(imageBuf.mutex) // TODO: Fix the stall by using a separate mutex that only blocks our stuff
	defer sync.unlock(imageBuf.mutex)

	fmt.println("trigger!")

	if imageBuf.files == nil {
		loadSuccess := load_directory(imageBuf)
		if !loadSuccess {
			return false
		}

		for file, i in imageBuf.files {
			// FIXME: Maybe filepath.clean() or something here?
			abs, success := filepath.abs(imageBuf.firstImagePath)
			if !success {
				continue
			}
			if file.fullpath == abs {
				imageBuf.firstImageIndexRelativeToFiles = i
				imageBuf.filesIndex = i
				fmt.println(imageBuf.firstImageIndexRelativeToFiles)
			}
		}
	}

	if imageBuf.imagePointersIndex % 4 == 0 {
		for i := 1; i <= 4; i += 1 {
			offset := i
			if leftOrRight {
				offset = -i
			}

			idx := imageBuf.filesIndex + offset // % len(imageBuf.files) // FIXME
			if idx < 0 {
				idx = len(imageBuf.files) - 1 + idx
			}
			idx %= len(imageBuf.files)

			/*if idx >= len(imageBuf.files) {
				idx = len(imageBuf.files) - 1
			} else if idx < 0 {
				idx = 0
			}*/

			// TODO: Do we want a waitgroup? How do we handle errors?
			thread.create_and_start_with_poly_data3(
				imageBuf,
				idx,
				offset,
				proc(imageBuf: ^ImageBuf, idx: int, offset: int) {
					//load_single_image(imageBuf, imageBuf.files[idx].fullpath, idx)
					h := (imageBuf.imagePointersIndex + offset) % len(imageBuf.imagePointers)
					if h < 0 {
						h = len(imageBuf.imagePointers) - 1 + offset
					}
					load_single_image(imageBuf, imageBuf.files[idx].fullpath, h)
				},
				init_context=context, // So we can track its memory usage (???)
				self_cleanup=true,
			)
		}
	}

	imageBuf.filesIndex += leftOrRight ? 4 : -4
	imageBuf.filesIndex %= len(imageBuf.files)

	imageBuf.imagePointersIndex += leftOrRight ? 1 : -1
	imageBuf.imagePointersIndex %= len(imageBuf.imagePointers)
	if imageBuf.imagePointersIndex < 0 {
		imageBuf.imagePointersIndex = len(imageBuf.imagePointers) - 1 - 1
	}

	return true
}

// Needs to be manually locked
load_directory :: proc(imageBuf: ^ImageBuf) -> (success: bool) {
	fd, err := os.open(filepath.dir(imageBuf.firstImagePath))
	if err != nil {
		return false
	}
	defer os.close(fd)

	files := new([]os.File_Info)
	files^, err = os.read_dir(fd, 0)
	if err != nil {
		return false
	}

	//sync.lock(imageBuf.mutex)
	imageBuf.files = files
	//sync.unlock(imageBuf.mutex)

	return true
}
