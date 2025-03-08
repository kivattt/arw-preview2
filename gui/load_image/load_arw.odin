package load_image

import "core:os"
import "core:fmt"
import "core:mem"

read_u16_le :: proc(fileHandle: os.Handle, offset: i64) -> (res: u16, success: bool) {
	if _, err := os.seek(fileHandle, offset, os.SEEK_SET); err != nil do return

	data := []u8{0,0}
	if _, err := os.read_full(fileHandle, data); err != nil do return

	#no_bounds_check {
		return u16(data[0]) | u16(data[1]) << 8, true
	}
}

read_u32_le :: proc(fileHandle: os.Handle, offset: i64) -> (res: u32, success: bool) {
	if _, err := os.seek(fileHandle, offset, os.SEEK_SET); err != nil do return

	data := []u8{0,0,0,0}
	if _, err := os.read_full(fileHandle, data); err != nil do return

	#no_bounds_check {
		res = u32(data[0]) |
			u32(data[1]) << 8 |
			u32(data[2]) << 16 |
			u32(data[3]) << 24
	}

	return res, true
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

	firstIFDOffset, success := read_u32_le(fileHandle, 4)
	if !success do return

	if firstIFDOffset == 0 || firstIFDOffset % 2 != 0 {
		return nil, .InvalidIFDOffset
	}

	numDirEntries: u16
	numDirEntries, success = read_u16_le(fileHandle, i64(firstIFDOffset))
	if !success do return

	previewImageStart: u32 = 0
	previewImageLength: u32 = 0

	for i: u16 = 0; i < numDirEntries; i += 1 {
		offset := firstIFDOffset + 2 + u32(i * 12)

		tag, tagSuccess := read_u16_le(fileHandle, i64(offset))
		if !tagSuccess do return

		type, typeSuccess := read_u16_le(fileHandle, i64(offset) + 2)
		if !typeSuccess do return

		valueOffset, valueOffsetSuccess := read_u32_le(fileHandle, i64(offset) + 8)
		if !valueOffsetSuccess do return

		valueOffsetIsValue := type != 5

		if valueOffsetIsValue {
			if tag == 0x0201 {
				previewImageStart = valueOffset
			} else if tag == 0x0202 {
				previewImageLength = valueOffset

				imageData, success := read_data(fileHandle, i64(previewImageStart), previewImageLength)
				if !success do return

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
