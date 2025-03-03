package main

import "core:mem"

read_u16_le :: proc(data: ^[]u8, pos: u32) -> (res: u16, success: bool) {
	if int(pos) + 1 >= len(data) {
		return 0, false
	}

	#no_bounds_check { 	// Just for fun
		return u16(data[pos]) | u16(data[pos + 1]) << 8, true
	}
}

read_u32_le :: proc(data: ^[]u8, pos: u32) -> (res: u32, success: bool) {
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

get_jpeg_image_preview_offsets_from_arw_data :: proc(
	data: ^[]u8,
) -> (
	previewImage: []u8,
	err: ImageLoadingError,
) {
	err = .TooSmallData

	if len(data) < 8 {
		return
	}

	if mem.compare(data[:4], {'I', 'I', 0x2a, 0x00}) != 0 {
		return nil, .MissingHeader
	}

	firstIFDOffset, firstIFDOffsetSuccess := read_u32_le(data, 4)
	if !firstIFDOffsetSuccess do return

	if firstIFDOffset == 0 || firstIFDOffset % 2 != 0 {
		return nil, .InvalidIFDOffset
	}

	numDirEntries, numDirEntriesSuccess := read_u16_le(data, firstIFDOffset)
	if !numDirEntriesSuccess do return

	previewImageStart: u32 = 0
	previewImageLength: u32 = 0

	for i: u16 = 0; i < numDirEntries; i += 1 {
		offset := firstIFDOffset + 2 + u32(i * 12)

		tag, tagSuccess := read_u16_le(data, offset)
		if !tagSuccess do return

		type, typeSuccess := read_u16_le(data, offset + 2)
		if !typeSuccess do return

		valueOffset, valueOffsetSuccess := read_u32_le(data, offset + 8)
		if !valueOffsetSuccess do return

		valueOffsetIsValue := type != 5

		if valueOffsetIsValue {
			if tag == 0x0201 {
				previewImageStart = valueOffset
			} else if tag == 0x0202 {
				previewImageLength = valueOffset
				return data[previewImageStart:previewImageStart + previewImageLength], .None
			}
		} else {
			if valueOffset % 2 != 0 {
				return nil, .InvalidValueOffset
			}
		}
	}

	return nil, .NoPreviewImage
}
