package main

import "core:mem"

read_u16_be :: proc(data: ^[]u8, pos: u32) -> (res: u16, success: bool) {
	if int(pos) + 1 >= len(data) {
		return 0, false
	}

	#no_bounds_check { 	// Just for fun
		return u16(data[pos + 1]) | u16(data[pos]) << 8, true
	}
}

read_u32_be :: proc(data: ^[]u8, pos: u32) -> (res: u32, success: bool) {
	if int(pos) + 3 >= len(data) {
		return 0, false
	}

	#no_bounds_check { 	// Just for fun
		return u32(data[pos + 3]) |
			u32(data[pos + 2]) << 8 |
			u32(data[pos + 1]) << 16 |
			u32(data[pos]) << 24,
			true
	}
}

get_jpeg_image_preview_offsets_from_cr3_data :: proc(
	data: ^[]u8,
) -> (
	previewImageStart, previewImageLength: u32,
	err: ImageLoadingError,
) {
	previewImageStart = 0
	previewImageLength = 0
	err = .TooSmallData

	// FIXME: Sketchy shit cause CR3 doesn't have a real ass header
	if mem.compare(data[:4], {0, 0, 0, 24}) != 0 {
		return 0, 0, .MissingHeader
	}

	offset: u32 = 0
	for {
		size, sizeSuccess := read_u32_be(data, offset)
		if !sizeSuccess {
			return
		}
		type, typeSuccess := read_u32_be(data, offset+4)
		if !typeSuccess {
			return
		}

		if type == 0x75756964 { // "uuid"
			extendedType := data[offset + 8:offset + 8 + 16]
			if mem.compare(extendedType, {0xea, 0xf4, 0x2b, 0x5e, 0x1c, 0x98, 0x4b, 0x88, 0xb9, 0xfb, 0xb7, 0xdc, 0x40, 0x6e, 0x4d, 0x16}) == 0 {
				previewImageStart = offset + 56
				previewImageLength, success := read_u32_be(data, previewImageStart - 4)
				if !success do return

				return previewImageStart, previewImageLength, .None
			}
		}

		offset += size
		if int(offset) >= len(data) {
			break
		}
	}

	return 0, 0, .NoPreviewImage
}
