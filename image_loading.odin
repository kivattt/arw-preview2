package main

import "core:fmt"
import "base:runtime"
import "core:mem"
import "core:strings"
import "core:os"
import rl "vendor:raylib"

read_u16 :: proc(data: ^[]u8, pos: u32) -> (res: u16, success: bool) {
	if int(pos) + 1 >= len(data) {
		return 0, false
	}

	#no_bounds_check { 	// Just for fun
		return u16(data[pos]) | u16(data[pos + 1]) << 8, true
	}
}

read_u32 :: proc(data: ^[]u8, pos: u32) -> (res: u32, success: bool) {
	if int(pos) + 3 >= len(data) {
		return 0, false
	}

	#no_bounds_check { 	// Just for fun
		return u32(data[pos]) |
			u32(data[pos + 1]) << 8 |
			u32(data[pos + 2]) << 16 |
			u32(data[pos + 3]) << 24,
			true
	}
}

ImageLoadingError :: enum {
	None = 0,
	FailedToReadFile,
	TooSmallData,
	MissingHeader,
	InvalidValueOffset,
	InvalidIFDOffset,
	NoPreviewImage,
}

get_jpeg_image_preview_offsets_from_arw_data :: proc(
	data: ^[]u8,
) -> (
	previewImageStart, previewImageLength: u32,
	err: ImageLoadingError,
) {
	previewImageStart = 0
	previewImageLength = 0
	err = .TooSmallData

	if len(data) < 8 {
		return
	}

	if mem.compare(data[:4], {'I', 'I', 0x2a, 0x00}) != 0 {
		return 0, 0, .MissingHeader
	}

	firstIFDOffset, firstIFDOffsetSuccess := read_u32(data, 4)
	if !firstIFDOffsetSuccess do return

	if firstIFDOffset == 0 || firstIFDOffset % 2 != 0 {
		return 0, 0, .InvalidIFDOffset
	}

	numDirEntries, numDirEntriesSuccess := read_u16(data, firstIFDOffset)
	if !numDirEntriesSuccess do return

	for i: u16 = 0; i < numDirEntries; i += 1 {
		offset := firstIFDOffset + 2 + u32(i * 12)

		tag, tagSuccess := read_u16(data, offset)
		if !tagSuccess do return

		type, typeSuccess := read_u16(data, offset + 2)
		if !typeSuccess do return

		valueOffset, valueOffsetSuccess := read_u32(data, offset + 8)
		if !valueOffsetSuccess do return

		valueOffsetIsValue := type != 5

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

load_jpeg_image_preview_from_filename :: proc(filename: string) -> (image: ^rl.Image, logString: string, err: ImageLoadingError) {
	// I don't think we use the default temp allocator in this function, but the docs say to do this.
	defer runtime.default_temp_allocator_destroy(cast(^runtime.Default_Temp_Allocator)context.temp_allocator.data)

	data, success := os.read_entire_file_from_filename(filename)
	if !success {
		return nil, "", .FailedToReadFile
	}
	defer delete(data)

	// TODO: Turn the return value of get_jpeg_image_preview_offsets_from_arw_data() into a slice
	previewImageStart: u32
	previewImageLength: u32
	previewImageStart, previewImageLength, err = get_jpeg_image_preview_offsets_from_arw_data(
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
	strings.builder_destroy(&logBuilder)
	return image, strings.to_string(logBuilder), .None
}
