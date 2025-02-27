package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

draw_grid :: proc(width, height: i32, color: rl.Color) {
	rlgl.Begin(rlgl.LINES)
	rlgl.Color4f(f32(color[0]) / 255, f32(color[1]) / 255, f32(color[2]) / 255, f32(color[3]) / 255)

	for i: i32 = 0; i <= width; i += 1 {
		rlgl.Vertex3f(f32(i), 0, 0)
		rlgl.Vertex3f(f32(i), 0, f32(height))
	}

	for i: i32 = 0; i <= height; i += 1 {
		rlgl.Vertex3f(0, 0, f32(i))
		rlgl.Vertex3f(f32(width), 0, f32(i))
	}
	rlgl.End()
}
