package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

draw_grid :: proc(x, y: f32, width, height: int) {
	rlgl.Begin(rlgl.LINES)
	rlgl.Color3f(0.5, 0.5, 0.5)

	for i := 0; i < width; i += 1 {
		rlgl.Vertex3f(x + f32(i), 0, y)
		rlgl.Vertex3f(x + f32(i), 0, y + f32(height)/2)
	}
	rlgl.End()
}
