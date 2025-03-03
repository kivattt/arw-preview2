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

get_jpeg_image_preview_offsets_from_image_data :: proc(
	data: ^[]u8
) -> (
	previewImageStart, previewImageLength: u32,
	err: ImageLoadingError,
) {
	if len(data) < 8 {
		return 0, 0, .TooSmallData
	}

	if mem.compare(data[:4], {'I', 'I', 0x2a, 0x00}) == 0 {
		return get_jpeg_image_preview_offsets_from_arw_data(data)
	} else {
		return get_jpeg_image_preview_offsets_from_cr3_data(data)
	}
}

// Remember to delete the logString return value once you're done with it!
load_jpeg_image_preview_from_filename :: proc(filename: string) -> (image: ^rl.Image, logString: string, err: ImageLoadingError) {
	// I don't think we use the default temp allocator in this function, but the docs say to do this.
	defer runtime.default_temp_allocator_destroy(cast(^runtime.Default_Temp_Allocator)context.temp_allocator.data)
	data, success := os.read_entire_file_from_filename(filename)
	if !success {
		return nil, "", .FailedToReadFile
	}
	defer delete(data)

	// TODO: Turn the return value of get_jpeg_image_preview_offsets_from_image_data() into a slice
	previewImageStart: u32
	previewImageLength: u32
	previewImageStart, previewImageLength, err = get_jpeg_image_preview_offsets_from_image_data(
		&data,
	)

	if err != .None {
		return nil, "", err
	}

	image = new(rl.Image)
	image^ = rl.LoadImageFromMemory(
		".jpg",
		&data[previewImageStart],
		i32(previewImageLength),
	)

	logBuilder := strings.builder_make()
	strings.write_string(&logBuilder, "\x1b[1;32m")
	fmt.sbprintln(&logBuilder, "preview image start  :", previewImageStart)
	fmt.sbprintln(&logBuilder, "preview image length :", previewImageLength)
	strings.write_string(&logBuilder, "\x1b[0m")
	logText := strings.clone(strings.to_string(logBuilder))
	strings.builder_destroy(&logBuilder)
	return image, logText, .None
}
