// Builds opt-in diagnostic geometry without changing simulation state.
module sim

import math

// Diagnostic lines use the existing tunnel line stream. They are presentation
// only: enabling them must never advance RNGs or alter collision decisions.
pub struct DebugViewOptions {
pub:
	boundaries bool
	slices     bool
	enemies    bool
	collisions bool
	exhaust    bool
}

pub fn (options DebugViewOptions) any() bool {
	return options.boundaries || options.slices || options.enemies || options.collisions
		|| options.exhaust
}

pub fn (simulation &Simulation) render_debug_view_vertices(camera_angle f32,
	start_distance f32, ring_count int, options DebugViewOptions) []CourseVertex {
	if !options.any() || ring_count < 2 || simulation.course.slices.len == 0 {
		return []CourseVertex{}
	}
	count := int_min(ring_count, 100)
	mut vertices := []CourseVertex{cap: count * 160}
	if options.boundaries || options.slices {
		for ring in 0 .. count {
			distance := start_distance + f32(ring)
			frame := simulation.course_frame_at(distance)
			if options.boundaries && !frame.slice.full && ring + 1 < count {
				next := simulation.course_frame_at(distance + 1)
				if !next.slice.full {
					for edge in 0 .. 2 {
						angle := if edge == 0 { frame.slice.left } else { frame.slice.right }
						next_angle := if edge == 0 { next.slice.left } else { next.slice.right }
						append_debug_line(mut vertices, debug_course_point(frame, angle,
							camera_angle, 2.95), debug_course_point(next, next_angle, camera_angle,
							2.95))
					}
				}
			}
			if options.slices && ring % 8 == 0 {
				for segment in 0 .. 48 {
					first := f32(segment) * f32(math.pi * 2) / 48
					second := f32(segment + 1) * f32(math.pi * 2) / 48
					middle := (first + second) * 0.5
					if course_side(middle, frame.slice) == 0 {
						append_debug_line(mut vertices, debug_course_point(frame, first,
							camera_angle, 4.9), debug_course_point(frame, second, camera_angle,
							4.9))
					}
				}
			}
		}
	}
	if options.collisions {
		simulation.append_debug_collision(mut vertices, simulation.ship.angle,
			simulation.ship.relative_depth, simulation.ship_collision, camera_angle)
	}
	if options.exhaust {
		for offset in ship_shape_rocket_offsets(0, 1) {
			simulation.append_debug_exhaust(mut vertices, wrap_angle(simulation.ship.angle + offset),
				simulation.ship.relative_depth - 0.15, camera_angle)
		}
	}
	mut shown := 0
	for enemy in simulation.enemies {
		if !enemy.alive || shown >= 24 || enemy.position.y < start_distance
			|| enemy.position.y > start_distance + f32(count) {
			continue
		}
		shown++
		if options.enemies {
			simulation.append_debug_cross(mut vertices, enemy.position.x, enemy.position.y,
				camera_angle, 6.9)
		}
		if options.collisions || options.exhaust {
			spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
			if options.collisions {
				size := if spec.collision_size.x > 0 && spec.collision_size.y > 0 {
					spec.collision_size
				} else {
					ship_shape_collision(enemy.kind, spec.shape_seed)
				}
				simulation.append_debug_collision(mut vertices, enemy.position.x,
					enemy.position.y, size, camera_angle)
			}
			if options.exhaust {
				for offset in ship_shape_rocket_offsets(spec.kind, spec.shape_seed) {
					simulation.append_debug_exhaust(mut vertices, wrap_angle(enemy.position.x + offset),
						enemy.position.y - 0.15, camera_angle)
				}
			}
		}
	}
	return vertices
}

fn debug_course_point(frame CourseRenderFrame, angle f32, camera_angle f32,
	brightness f32) CourseVertex {
	mut inner := frame
	inner.radius -= 0.03
	x, y := course_surface_xy(inner, angle, camera_angle)
	return CourseVertex{
		x: x
		y: y
		z: course_render_depth_base + frame.distance * course_render_depth_scale
		brightness: brightness
	}
}

fn append_debug_line(mut vertices []CourseVertex, first CourseVertex, second CourseVertex) {
	vertices << first
	vertices << second
}

fn (simulation &Simulation) append_debug_cross(mut vertices []CourseVertex, angle f32,
	depth f32, camera_angle f32, brightness f32) {
	frame := simulation.course_frame_at(depth)
	before := simulation.course_frame_at(depth - 0.24)
	after := simulation.course_frame_at(depth + 0.24)
	append_debug_line(mut vertices, debug_course_point(frame, angle - 0.035, camera_angle,
		brightness), debug_course_point(frame, angle + 0.035, camera_angle, brightness))
	append_debug_line(mut vertices, debug_course_point(before, angle, camera_angle, brightness),
		debug_course_point(after, angle, camera_angle, brightness))
}

fn (simulation &Simulation) append_debug_collision(mut vertices []CourseVertex,
	angle f32, depth f32, size Vec2, camera_angle f32) {
	slice := simulation.course.slice_at(simulation.ship.course_position + depth)
	angle_radius := size.x / f32_max(slice.rad / 21 * 3, 0.001)
	depth_radius := size.y
	near_frame := simulation.course_frame_at(depth - depth_radius)
	far_frame := simulation.course_frame_at(depth + depth_radius)
	for side in [f32(-1), f32(1)] {
		edge_angle := angle + side * angle_radius
		append_debug_line(mut vertices, debug_course_point(near_frame, edge_angle, camera_angle,
			2.95), debug_course_point(far_frame, edge_angle, camera_angle, 2.95))
	}
	for frame in [near_frame, far_frame] {
		append_debug_line(mut vertices, debug_course_point(frame, angle - angle_radius,
			camera_angle, 2.95), debug_course_point(frame, angle + angle_radius, camera_angle,
			2.95))
	}
}

fn (simulation &Simulation) append_debug_exhaust(mut vertices []CourseVertex,
	angle f32, depth f32, camera_angle f32) {
	before := simulation.course_frame_at(depth - 0.16)
	after := simulation.course_frame_at(depth + 0.16)
	append_debug_line(mut vertices, debug_course_point(before, angle - 0.025, camera_angle,
		4.9), debug_course_point(after, angle + 0.025, camera_angle, 4.9))
	append_debug_line(mut vertices, debug_course_point(before, angle + 0.025, camera_angle,
		4.9), debug_course_point(after, angle - 0.025, camera_angle, 4.9))
}
