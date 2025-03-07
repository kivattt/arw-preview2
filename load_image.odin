package main

import "core:fmt"
import "base:runtime"
import "core:mem"
import "core:strings"
import "core:os"
import rl "vendor:raylib"

ImageLoadingError :: enum {
	None = 0,
	FailedToReadFile,
	TooSmallData,
	MissingHeader,
	InvalidValueOffset,
	InvalidIFDOffset,
	NoPreviewImage,
}

// Remember to delete the returned previewImage
get_jpeg_image_preview_from_filename :: proc(filename: string) -> (previewImage: []u8, err: ImageLoadingError) {
	fileHandle, fileErr := os.open(filename)
	if fileErr != nil {
		return nil, .FailedToReadFile
	}
	defer os.close(fileHandle)

	fileSize, fileSizeErr := os.file_size(fileHandle)
	if fileSizeErr != nil {
		return nil, .FailedToReadFile
	}

	if fileSize < 4 {
		return nil, .TooSmallData
	}

	header := []u8{0,0,0,0}
	_, readErr := os.read_at_least(fileHandle, header, 4)
	if readErr != nil {
		return nil, .FailedToReadFile
	}

	if _, seekErr := os.seek(fileHandle, 0, os.SEEK_SET); seekErr != nil {
		return nil, .FailedToReadFile
	}

	if mem.compare(header, {'I', 'I', 0x2a, 0x00}) == 0 {
		return get_jpeg_image_preview_from_arw_file(fileHandle)
	} else {
		return get_jpeg_image_preview_from_cr3_file(fileHandle)
	}
}

// Remember to delete the logString return value once you're done with it!
load_image_preview_from_filename :: proc(filename: string) -> (image: ^rl.Image, logString: string, err: ImageLoadingError) {
	// I don't think we use the default temp allocator in this function, but the docs say to do this.
	defer runtime.default_temp_allocator_destroy(cast(^runtime.Default_Temp_Allocator)context.temp_allocator.data)

	previewImage: []u8
	previewImage, err = get_jpeg_image_preview_from_filename(
		filename
	)
	defer delete(previewImage)

	if err != .None {
		return nil, "", err
	}

	image = new(rl.Image)
	image^ = rl.LoadImageFromMemory(
		".jpg",
		raw_data(previewImage),
		i32(len(previewImage)),
	)

	logBuilder := strings.builder_make()
	// FIXME: Output the image offsets and stuff, would prob have to go all the way down the call chain
/*	strings.write_string(&logBuilder, "\x1b[1;32m")
	fmt.sbprintln(&logBuilder, "preview image start  :", mem.ptr_sub(&previewImage[0], &data[0]))
	fmt.sbprintln(&logBuilder, "preview image length :", len(previewImage))
	strings.write_string(&logBuilder, "\x1b[0m")*/

	logText := strings.clone(strings.to_string(logBuilder))
	strings.builder_destroy(&logBuilder)
	return image, logText, .None
}

// Remember to delete the returned data when success = true
read_data :: proc(fileHandle: os.Handle, offset: i64, numBytes: u32) -> (data: []u8, success: bool) {
	if _, err := os.seek(fileHandle, offset, os.SEEK_SET); err != nil do return

	data = make([]u8, numBytes)
	if _, err := os.read_full(fileHandle, data); err != nil {
		delete(data)
		data = nil
		return
	}

	return data, true
}
