package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

draw_grid :: proc(width, height: i32) {
	rlgl.Begin(rlgl.LINES)
	rlgl.Color3f(0.5, 0.5, 0.5)

	for i: i32 = 0; i < width; i += 1 {
		rlgl.Vertex3f(f32(i), 0, 0)
		rlgl.Vertex3f(f32(i), 0, f32(height))
	}

	for i: i32 = 0; i < height; i += 1 {
		rlgl.Vertex3f(0, 0, f32(i))
		rlgl.Vertex3f(f32(width), 0, f32(i))
	}
	rlgl.End()
}
