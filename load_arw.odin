package main

import "core:os"
import "core:mem"

read_u16_le :: proc(data: ^[]u8, pos: u32) -> (res: u16) {
	#no_bounds_check { 	// Just for fun
		return u16(data[pos]) | u16(data[pos + 1]) << 8
	}
}

read_u32_le :: proc(data: ^[]u8, pos: u32) -> (res: u32) {
	#no_bounds_check { 	// Just for fun
		return u32(data[pos]) |
			u32(data[pos + 1]) << 8 |
			u32(data[pos + 2]) << 16 |
			u32(data[pos + 3]) << 24
	}
}

// Remember to delete the returned previewImage
get_jpeg_image_preview_from_arw_file :: proc(
	fileHandle: os.Handle
) -> (
	previewImage: []u8,
	err: ImageLoadingError,
) {
	err = .TooSmallData

	fileSize, fileSizeErr := os.file_size(fileHandle)
	if fileSizeErr != nil {
		return nil, .FailedToReadFile
	}

	if fileSize < 8 do return

	if _, err := os.seek(fileHandle, 4, os.SEEK_SET); err != nil do return
	firstIFDOffsetData := make([]u8, 4)
	defer delete(firstIFDOffsetData)
	if _, err := os.read_full(fileHandle, firstIFDOffsetData); err != nil do return

	firstIFDOffset := read_u32_le(&firstIFDOffsetData, 0)

	if firstIFDOffset == 0 || firstIFDOffset % 2 != 0 {
		return nil, .InvalidIFDOffset
	}

	if _, err := os.seek(fileHandle, i64(firstIFDOffset), os.SEEK_SET); err != nil do return
	numDirEntriesData := make([]u8, 2)
	defer delete(numDirEntriesData)
	if _, err := os.read_full(fileHandle, numDirEntriesData); err != nil do return

	numDirEntries := read_u16_le(&numDirEntriesData, 0)

	previewImageStart: u32 = 0
	previewImageLength: u32 = 0

	for i: u16 = 0; i < numDirEntries; i += 1 {
		offset := firstIFDOffset + 2 + u32(i * 12)

		if _, err := os.seek(fileHandle, i64(offset), os.SEEK_SET); err != nil do return
		tagAndTypeAndValueOffsetData := make([]u8, 12)
		defer delete(tagAndTypeAndValueOffsetData)
		if _, err := os.read_full(fileHandle, tagAndTypeAndValueOffsetData); err != nil do return

		tag := read_u16_le(&tagAndTypeAndValueOffsetData, 0)
		type := read_u16_le(&tagAndTypeAndValueOffsetData, 2)
		valueOffset := read_u32_le(&tagAndTypeAndValueOffsetData, 8)

		valueOffsetIsValue := type != 5

		if valueOffsetIsValue {
			if tag == 0x0201 {
				previewImageStart = valueOffset
			} else if tag == 0x0202 {
				previewImageLength = valueOffset

				if _, err := os.seek(fileHandle, i64(previewImageStart), os.SEEK_SET); err != nil do return
				imageData := make([]u8, previewImageLength)
				if _, err := os.read_full(fileHandle, imageData); err != nil do return

				return imageData, .None
			}
		} else {
			if valueOffset % 2 != 0 {
				return nil, .InvalidValueOffset
			}
		}
	}

	return nil, .NoPreviewImage
}
