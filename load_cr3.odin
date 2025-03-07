package main

import "core:os"
import "core:mem"

read_u32_be :: proc(data: ^[]u8, pos: u32) -> (res: u32) {
	#no_bounds_check { 	// Just for fun
		return u32(data[pos + 3]) |
			u32(data[pos + 2]) << 8 |
			u32(data[pos + 1]) << 16 |
			u32(data[pos]) << 24
	}
}

// Remember to delete the returned previewImage
get_jpeg_image_preview_from_cr3_file :: proc(
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

	header := []u8{0,0,0,0}
	if _, err := os.read_full(fileHandle, header); err != nil do return


	// FIXME: Sketchy shit cause CR3 doesn't have a real ass header
	if mem.compare(header, {0, 0, 0, 24}) != 0 {
		return nil, .MissingHeader
	}

	sizeAndTypeData := make([]u8, 8) // 4 byte size + 4 byte type
	defer delete(sizeAndTypeData)

	offset: i64 = 0
	os.seek(fileHandle, offset, os.SEEK_SET)
	for {
		if _, err := os.read_full(fileHandle, sizeAndTypeData); err != nil do return

		size := read_u32_be(&sizeAndTypeData, 0)
		type := read_u32_be(&sizeAndTypeData, 4)

		if type == 0x75756964 { // "uuid"
			extendedTypeData := make([]u8, 16)
			defer delete(extendedTypeData)

			if _, err := os.read_full(fileHandle, extendedTypeData); err != nil do return

			// PreviewImage UUID magic number
			if mem.compare(extendedTypeData, {0xea, 0xf4, 0x2b, 0x5e, 0x1c, 0x98, 0x4b, 0x88, 0xb9, 0xfb, 0xb7, 0xdc, 0x40, 0x6e, 0x4d, 0x16}) == 0 {
				previewImageStart := offset + 56

				if _, err := os.seek(fileHandle, previewImageStart - 4, os.SEEK_SET); err != nil do return
				previewImageLengthData := make([]u8, 4)
				defer delete(previewImageLengthData)

				if _, err := os.read_full(fileHandle, previewImageLengthData); err != nil do return

				previewImageLength := read_u32_be(&previewImageLengthData, 0)

				imageData := make([]u8, previewImageLength)
				if _, err := os.read_full(fileHandle, imageData); err != nil {
					delete(imageData)
					return
				}

				return imageData, .None
			}
		}

		offset += i64(size)
		if offset >= fileSize {
			break
		}
		os.seek(fileHandle, offset, os.SEEK_SET)
	}

	return nil, .NoPreviewImage
}
