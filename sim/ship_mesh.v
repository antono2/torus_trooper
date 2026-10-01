module sim

import math

struct ShipMeshVec3 {
	x f32
	y f32
	z f32
}

fn (a ShipMeshVec3) add(b ShipMeshVec3) ShipMeshVec3 {
	return ShipMeshVec3{a.x + b.x, a.y + b.y, a.z + b.z}
}

fn (a ShipMeshVec3) subtract(b ShipMeshVec3) ShipMeshVec3 {
	return ShipMeshVec3{a.x - b.x, a.y - b.y, a.z - b.z}
}

fn (a ShipMeshVec3) multiply(value f32) ShipMeshVec3 {
	return ShipMeshVec3{a.x * value, a.y * value, a.z * value}
}

fn (a ShipMeshVec3) dot(b ShipMeshVec3) f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

fn (a ShipMeshVec3) cross(b ShipMeshVec3) ShipMeshVec3 {
	return ShipMeshVec3{
		x: a.y * b.z - a.z * b.y
		y: a.z * b.x - a.x * b.z
		z: a.x * b.y - a.y * b.x
	}
}

fn (a ShipMeshVec3) normalized() ShipMeshVec3 {
	length := f32(math.sqrt(f64(a.dot(a))))
	return if length > 0.000001 { a.multiply(1 / length) } else { ShipMeshVec3{ z: 1 } }
}

fn (point ShipMeshVec3) rotate_x(angle f32) ShipMeshVec3 {
	cosine := f32(math.cos(angle))
	sine := f32(math.sin(angle))
	return ShipMeshVec3{
		x: point.x
		y: point.y * cosine - point.z * sine
		z: point.y * sine + point.z * cosine
	}
}

fn (point ShipMeshVec3) rotate_y(angle f32) ShipMeshVec3 {
	cosine := f32(math.cos(angle))
	sine := f32(math.sin(angle))
	return ShipMeshVec3{
		x: point.x * cosine + point.z * sine
		y: point.y
		z: -point.x * sine + point.z * cosine
	}
}

fn (point ShipMeshVec3) rotate_z(angle f32) ShipMeshVec3 {
	cosine := f32(math.cos(angle))
	sine := f32(math.sin(angle))
	return ShipMeshVec3{
		x: point.x * cosine - point.y * sine
		y: point.x * sine + point.y * cosine
		z: point.z
	}
}

struct ShipMeshFrame {
	center  ShipMeshVec3
	lateral ShipMeshVec3
	normal  ShipMeshVec3
	forward ShipMeshVec3
}

fn (simulation &Simulation) ship_mesh_frame(angle f32, relative_depth f32, camera_angle f32,
	radial_offset f32, bank f32) ShipMeshFrame {
	mut frame := simulation.course_frame_at(relative_depth)
	mut previous_frame := simulation.course_frame_at(relative_depth - 0.5)
	mut next_frame := simulation.course_frame_at(relative_depth + 0.5)
	frame.radius = frame.radius / source_tunnel_radius_ratio + radial_offset
	previous_frame.radius = previous_frame.radius / source_tunnel_radius_ratio + radial_offset
	next_frame.radius = next_frame.radius / source_tunnel_radius_ratio + radial_offset
	x, y := course_surface_xy(frame, angle, camera_angle)
	previous_x, previous_y := course_surface_xy(previous_frame, angle, camera_angle)
	next_x, next_y := course_surface_xy(next_frame, angle, camera_angle)
	center := ShipMeshVec3{
		x: x
		y: y
		z: course_render_depth_base + relative_depth * course_render_depth_scale
	}
	// The V renderer currently expresses course bends by moving successive ring
	// centers. Use a centered one-slice tangent so the long nose and engine pods
	// do not magnify a slice-boundary direction change when they approach the
	// camera. Build a stable wall normal, then apply bank strictly as a roll
	// around the resulting longitudinal direction.
	forward := ShipMeshVec3{
		x: next_x - previous_x
		y: next_y - previous_y
		z: course_render_depth_scale
	}.normalized()
	raw_normal := ShipMeshVec3{
		x: x - frame.center_x
		y: y - frame.center_y
	}
	mut normal := raw_normal.subtract(forward.multiply(raw_normal.dot(forward))).normalized()
	mut lateral := normal.cross(forward).normalized()
	bank_cosine := f32(math.cos(bank))
	bank_sine := f32(math.sin(bank))
	banked_lateral := lateral.multiply(bank_cosine).subtract(normal.multiply(bank_sine))
	banked_normal := lateral.multiply(bank_sine).add(normal.multiply(bank_cosine))
	lateral = banked_lateral
	normal = banked_normal
	return ShipMeshFrame{
		center: center
		lateral: lateral
		normal: normal
		forward: forward
	}
}

fn transform_structure_vertex(vertex ShipMeshVec3, structure ShipStructureGeometry) ShipMeshVec3 {
	mut scaled := if structure.shape == .rocket {
		ShipMeshVec3{
			x: vertex.x * structure.width * structure.x_reverse
			y: vertex.y * structure.width
			z: vertex.z * structure.height
		}
	} else {
		ShipMeshVec3{
			x: vertex.x * structure.width * structure.x_reverse
			y: vertex.y * structure.height
			z: vertex.z
		}
	}
	rotation_z := structure.rotation_z_degrees * f32(math.pi) / 180
	cos_z := f32(math.cos(rotation_z))
	sin_z := f32(math.sin(rotation_z))
	scaled = ShipMeshVec3{
		x: scaled.x * cos_z - scaled.y * sin_z
		y: scaled.x * sin_z + scaled.y * cos_z
		z: scaled.z
	}
	rotation_x := -structure.rotation_x_degrees * f32(math.pi) / 180
	cos_x := f32(math.cos(rotation_x))
	sin_x := f32(math.sin(rotation_x))
	return ShipMeshVec3{
		x: scaled.x + structure.position.x
		y: scaled.y * cos_x - scaled.z * sin_x + structure.position.y
		z: scaled.y * sin_x + scaled.z * cos_x
	}
}

// Return the furthest source-model point toward the tunnel wall after the
// ship's bank. Panels are contained by this transformed corner box; rockets
// use every endpoint present in their four-sided source mesh.
fn ship_structure_outward_extent(structure ShipStructureGeometry, bank f32) f32 {
	bank_sine := f32(math.sin(-bank))
	bank_cosine := f32(math.cos(-bank))
	mut extent := f32(0)
	if structure.shape == .rocket {
		for side in 0 .. 4 {
			angle := f32(side) * f32(math.pi) / 2 + f32(math.pi) / 4
			for edge_angle in [angle - 0.3, angle + 0.3] {
				for z in [f32(-0.5), f32(0.5)] {
					point := transform_structure_vertex(ShipMeshVec3{
						x: f32(math.sin(edge_angle))
						y: f32(math.cos(edge_angle))
						z: z
					}, structure)
					extent = f32_max(extent, point.x * bank_sine + point.y * bank_cosine)
				}
			}
		}
		return extent
	}
	for x in [f32(-0.5), f32(0.5)] {
		for y in [f32(0), f32(0.1)] {
			for z in [f32(-0.5), f32(0.5)] {
				point := transform_structure_vertex(ShipMeshVec3{ x: x, y: y, z: z }, structure)
				extent = f32_max(extent, point.x * bank_sine + point.y * bank_cosine)
			}
		}
	}
	return extent
}

fn ship_geometry_outward_extent(geometry ShipGeometry, bank f32) f32 {
	mut extent := f32(0)
	for structure in geometry.structures {
		extent = f32_max(extent, ship_structure_outward_extent(structure, bank))
	}
	return extent * course_render_height_scale
}

fn ship_geometry_surface_clearance(geometry ShipGeometry, bank f32, scale f32,
	baseline f32) f32 {
	// Size 1 retains the source-matched placement. For larger configured hulls,
	// offset the center by precisely the additional outward extent so scaling
	// cannot push more of the hull through the course surface.
	extra_scale := f32_max(scale, 1) - 1
	return baseline + ship_geometry_outward_extent(geometry, bank) * extra_scale
}

fn player_ship_surface_clearance(scale f32) f32 {
	geometry := generate_ship_geometry(0, 1, false)
	// The player silhouette is assembled from segmented
	// panels. Reserve its widest bank-independent radius so it cannot bob into
	// the course as the player steers.
	mut radial_extent := f32(0)
	for structure in geometry.structures {
		for bank in [f32(0), f32(math.pi) * 0.25, f32(math.pi) * 0.5, f32(math.pi) * 0.75] {
			radial_extent = f32_max(radial_extent, ship_structure_outward_extent(structure, bank))
		}
	}
	return ship_render_surface_clearance + radial_extent * course_render_height_scale * (f32_max(scale, 1) - 1)
}

fn player_ship_depth_clearance(scale f32) f32 {
	// Convert the additional model-local tail length to course slices. This
	// keeps oversized tuning configurations behind the camera guard instead of
	// letting their rear cross the projection plane and jump vertically.
	return (f32_max(scale, 1) - 1) * f32(1.35) / source_tunnel_slice_depth
}

fn ship_structure_color(index int) TunnelColor {
	return match int_max(0, int_min(7, index)) {
		0 { TunnelColor{ r: 1, g: 1, b: 1 } }
		1 { TunnelColor{ r: 0.5, g: 0.5, b: 0.5 } }
		2 { TunnelColor{ r: 0.95, g: 0.16, b: 0.12 } }
		3 { TunnelColor{ r: 0.18, g: 0.82, b: 0.28 } }
		4 { TunnelColor{ r: 0.18, g: 0.4, b: 1 } }
		5 { TunnelColor{ r: 0.95, g: 0.7, b: 0.12 } }
		6 { TunnelColor{ r: 0.85, g: 0.2, b: 0.9 } }
		else { TunnelColor{ r: 0.08, g: 0.72, b: 0.95 } }
	}
}

fn actor_ship_vertex(frame ShipMeshFrame, model ShipMeshVec3, scale f32) ShipMeshVec3 {
	radial_scale := course_render_height_scale * scale
	longitudinal_scale := course_render_longitudinal_scale * scale
	return frame.center.add(frame.lateral.multiply(model.x * radial_scale)).add(frame.normal.multiply(model.y * radial_scale)).add(frame.forward.multiply(model.z * longitudinal_scale))
}

fn append_ship_triangle(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	a ShipMeshVec3, b ShipMeshVec3, c ShipMeshVec3, scale f32, color TunnelColor,
	alpha f32) {
	world_a := actor_ship_vertex(frame, a, scale)
	world_b := actor_ship_vertex(frame, b, scale)
	world_c := actor_ship_vertex(frame, c, scale)
	normal := world_b.subtract(world_a).cross(world_c.subtract(world_a)).normalized()
	light_direction := ShipMeshVec3{ x: -0.35, y: 0.65, z: -0.68 }.normalized()
	face_light := 0.42 + 0.58 * f32(math.abs(normal.dot(light_direction)))
	for point in [world_a, world_b, world_c] {
		vertices << CourseFillVertex{
			x: point.x
			y: point.y
			z: point.z
			r: color.r * face_light
			g: color.g * face_light
			b: color.b * face_light
			a: alpha
		}
	}
}

fn append_ship_quad(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	a ShipMeshVec3, b ShipMeshVec3, c ShipMeshVec3, d ShipMeshVec3, scale f32,
	color TunnelColor, alpha f32) {
	append_ship_triangle(mut vertices, frame, a, b, c, scale, color, alpha)
	append_ship_triangle(mut vertices, frame, a, c, d, scale, color, alpha)
}

struct ShipHullSection {
	x           f32
	y           f32
	z           f32
	half_width  f32
	half_height f32
}

fn brighter_ship_color(color TunnelColor, amount f32) TunnelColor {
	return TunnelColor{
		r: color.r + (1 - color.r) * amount
		g: color.g + (1 - color.g) * amount
		b: color.b + (1 - color.b) * amount
	}
}

fn darker_ship_color(color TunnelColor, amount f32) TunnelColor {
	return TunnelColor{
		r: color.r * (1 - amount)
		g: color.g * (1 - amount)
		b: color.b * (1 - amount)
	}
}

fn ship_nose_color(color TunnelColor) TunnelColor {
	// Lift the nose/canopy enough to reveal the shape without replacing the
	// ship's seeded hue with the former near-white cyan accent.
	return brighter_ship_color(color, 0.12)
}

fn ship_exhaust_color(color TunnelColor) TunnelColor {
	return TunnelColor{
		r: color.r * 0.2 + 0.72
		g: color.g * 0.12 + 0.12
		b: color.b * 0.12 + 0.08
	}
}

fn hull_section_corners(section ShipHullSection) []ShipMeshVec3 {
	return [
		ShipMeshVec3{ x: section.x - section.half_width, y: section.y - section.half_height, z: section.z },
		ShipMeshVec3{ x: section.x + section.half_width, y: section.y - section.half_height, z: section.z },
		ShipMeshVec3{ x: section.x + section.half_width, y: section.y + section.half_height, z: section.z },
		ShipMeshVec3{ x: section.x - section.half_width, y: section.y + section.half_height, z: section.z },
	]
}

fn append_tapered_hull(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	sections []ShipHullSection, scale f32, color TunnelColor, alpha f32) {
	if sections.len < 2 {
		return
	}
	first := hull_section_corners(sections[0])
	append_ship_quad(mut vertices, frame, first[3], first[2], first[1], first[0], scale, ship_exhaust_color(color), alpha)
	for index in 0 .. sections.len - 1 {
		a := hull_section_corners(sections[index])
		b := hull_section_corners(sections[index + 1])
		append_ship_quad(mut vertices, frame, a[0], b[0], b[1], a[1], scale, darker_ship_color(color, 0.16), alpha)
		append_ship_quad(mut vertices, frame, a[3], a[2], b[2], b[3], scale, brighter_ship_color(color, 0.2), alpha)
		append_ship_quad(mut vertices, frame, a[0], a[3], b[3], b[0], scale, color, alpha)
		append_ship_quad(mut vertices, frame, a[1], b[1], b[2], a[2], scale, color, alpha)
	}
	last := hull_section_corners(sections.last())
	append_ship_quad(mut vertices, frame, last[0], last[1], last[2], last[3], scale, ship_nose_color(color), alpha)
}

// Use an octagonal cross-section for compact interceptors. At gameplay scale
// it reads as a smooth, rounded fuselage while retaining inexpensive flat
// faces and enough highlights to make its volume visible.
fn append_round_hull(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	sections []ShipHullSection, scale f32, color TunnelColor, alpha f32) {
	if sections.len < 2 {
		return
	}
	sides := 8
	for section_index in 0 .. sections.len - 1 {
		current := sections[section_index]
		next := sections[section_index + 1]
		for side in 0 .. sides {
			angle_a := f32(side) * f32(math.pi) * 2 / sides
			angle_b := f32(side + 1) * f32(math.pi) * 2 / sides
			a0 := ShipMeshVec3{
				x: current.x + f32(math.cos(angle_a)) * current.half_width
				y: current.y + f32(math.sin(angle_a)) * current.half_height
				z: current.z
			}
			a1 := ShipMeshVec3{
				x: current.x + f32(math.cos(angle_b)) * current.half_width
				y: current.y + f32(math.sin(angle_b)) * current.half_height
				z: current.z
			}
			b0 := ShipMeshVec3{
				x: next.x + f32(math.cos(angle_a)) * next.half_width
				y: next.y + f32(math.sin(angle_a)) * next.half_height
				z: next.z
			}
			b1 := ShipMeshVec3{
				x: next.x + f32(math.cos(angle_b)) * next.half_width
				y: next.y + f32(math.sin(angle_b)) * next.half_height
				z: next.z
			}
			section_color := if side >= sides / 2 {
				darker_ship_color(color, 0.12)
			} else {
				brighter_ship_color(color, 0.1)
			}
			append_ship_quad(mut vertices, frame, a0, b0, b1, a1, scale, section_color, alpha)
		}
	}
}

fn append_hull_wing(mut vertices []CourseFillVertex, frame ShipMeshFrame, side f32,
	root_width f32, span f32, front_z f32, tip_z f32, rear_z f32, thickness f32,
	scale f32, color TunnelColor, alpha f32) {
	root_front := ShipMeshVec3{ x: side * root_width, y: 0, z: front_z }
	tip := ShipMeshVec3{ x: side * span, y: 0, z: tip_z }
	root_rear := ShipMeshVec3{ x: side * root_width, y: 0, z: rear_z }
	bottom_offset := ShipMeshVec3{ y: -thickness }
	top_offset := ShipMeshVec3{ y: thickness }
	a0 := root_front.add(bottom_offset)
	b0 := tip.add(bottom_offset)
	c0 := root_rear.add(bottom_offset)
	a1 := root_front.add(top_offset)
	b1 := tip.add(top_offset)
	c1 := root_rear.add(top_offset)
	append_ship_triangle(mut vertices, frame, a1, b1, c1, scale, brighter_ship_color(color, 0.24), alpha)
	append_ship_triangle(mut vertices, frame, c0, b0, a0, scale, darker_ship_color(color, 0.2), alpha)
	append_ship_quad(mut vertices, frame, a0, b0, b1, a1, scale, color, alpha)
	append_ship_quad(mut vertices, frame, b0, c0, c1, b1, scale, color, alpha)
	append_ship_quad(mut vertices, frame, c0, a0, a1, c1, scale, color, alpha)
}

fn append_boss_radial_spike(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	angle f32, scale f32, color TunnelColor, alpha f32) {
	radial := ShipMeshVec3{ x: f32(math.cos(angle)), y: f32(math.sin(angle)) }
	tangent := ShipMeshVec3{ x: -radial.y, y: radial.x }
	center := radial.multiply(0.58).add(ShipMeshVec3{ z: -0.15 })
	width := tangent.multiply(0.2)
	depth := ShipMeshVec3{ z: 0.34 }
	a := center.add(width).add(depth)
	b := center.subtract(width).add(depth)
	c := center.subtract(width).subtract(depth)
	d := center.add(width).subtract(depth)
	tip := radial.multiply(2.35).add(ShipMeshVec3{ z: 0.5 })
	append_ship_triangle(mut vertices, frame, a, b, tip, scale, brighter_ship_color(color, 0.16), alpha)
	append_ship_triangle(mut vertices, frame, b, c, tip, scale, color, alpha)
	append_ship_triangle(mut vertices, frame, c, d, tip, scale, darker_ship_color(color, 0.18), alpha)
	append_ship_triangle(mut vertices, frame, d, a, tip, scale, color, alpha)
	append_ship_quad(mut vertices, frame, d, c, b, a, scale, darker_ship_color(color, 0.2), alpha)
}

fn readable_hull_dimensions(kind int) (f32, f32) {
	return match kind {
		-1 { f32(1.35), f32(0.32) }
		0 { f32(0.82), f32(0.25) }
		1 { f32(1.5), f32(0.4) }
		else { f32(2.85), f32(0.62) }
	}
}

fn readable_hull_surface_clearance(kind int, scale f32, baseline f32) f32 {
	half_width, half_height := readable_hull_dimensions(kind)
	// Reserve the largest possible radial extent for every bank angle. The
	// former angle-dependent offset prevented clipping, but visibly moved a
	// scaled hull toward and away from the tunnel center while it rolled.
	outward_extent := f32_max(half_width, half_height)
	extra_scale := f32_max(scale, 1) - 1
	return baseline + outward_extent * course_render_height_scale * extra_scale
}

// New high-resolution visual hulls deliberately use +Z as the nose and -Z as
// the exhaust. Their asymmetry makes course direction and the enemy reversal
// visible from any oblique view; simulation collision and seeded colors remain
// sourced from procedural ShipShape data.
fn append_readable_ship_hull(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	kind int, source_color int, damaged bool, scale f32, foreground bool) {
	base_color := ship_structure_color(if damaged { 0 } else { source_color })
	// High transparency blended the bright track through the hull and washed
	// even saturated palette entries toward white.
	alpha := if foreground { f32(-0.96) } else { f32(0.94) }
	match kind {
		-1 {
			append_tapered_hull(mut vertices, frame, [
				ShipHullSection{ z: -1.35, half_width: 0.2, half_height: 0.1 },
				ShipHullSection{ z: -0.45, half_width: 0.34, half_height: 0.15 },
				ShipHullSection{ z: 0.35, half_width: 0.28, half_height: 0.12 },
				ShipHullSection{ z: 1.75, half_width: 0.035, half_height: 0.025 },
			], scale, base_color, alpha)
			for side in [f32(-1), f32(1)] {
				append_hull_wing(mut vertices, frame, side, 0.26, 1.35, 0.55, -0.05, -1.05, 0.035, scale, base_color, alpha)
				append_tapered_hull(mut vertices, frame, [
					ShipHullSection{ x: side * 0.53, z: -1.28, half_width: 0.12, half_height: 0.1 },
					ShipHullSection{ x: side * 0.53, z: -0.42, half_width: 0.17, half_height: 0.12 },
					ShipHullSection{ x: side * 0.53, z: 0.5, half_width: 0.025, half_height: 0.025 },
				], scale, darker_ship_color(base_color, 0.1), alpha)
			}
			append_tapered_hull(mut vertices, frame, [
				ShipHullSection{ y: 0.16, z: -0.3, half_width: 0.16, half_height: 0.07 },
				ShipHullSection{ y: 0.2, z: 0.25, half_width: 0.14, half_height: 0.09 },
				ShipHullSection{ y: 0.14, z: 0.86, half_width: 0.025, half_height: 0.02 },
			], scale, ship_nose_color(base_color), alpha)
		}
		0 {
			append_round_hull(mut vertices, frame, [
				ShipHullSection{ z: -0.92, half_width: 0.14, half_height: 0.1 },
				ShipHullSection{ z: -0.5, half_width: 0.29, half_height: 0.18 },
				ShipHullSection{ z: 0.05, half_width: 0.34, half_height: 0.21 },
				ShipHullSection{ z: 0.62, half_width: 0.24, half_height: 0.16 },
				ShipHullSection{ z: 1.16, half_width: 0.035, half_height: 0.03 },
			], scale, base_color, alpha)
			for side in [f32(-1), f32(1)] {
				append_hull_wing(mut vertices, frame, side, 0.24, 0.7, 0.3, 0.02, -0.55, 0.045, scale, base_color, alpha)
			}
			append_round_hull(mut vertices, frame, [
				ShipHullSection{ y: 0.17, z: -0.24, half_width: 0.13, half_height: 0.07 },
				ShipHullSection{ y: 0.2, z: 0.22, half_width: 0.12, half_height: 0.075 },
				ShipHullSection{ y: 0.15, z: 0.62, half_width: 0.025, half_height: 0.02 },
			], scale, ship_nose_color(base_color), alpha)
		}
		1 {
			append_tapered_hull(mut vertices, frame, [
				ShipHullSection{ z: -1.4, half_width: 0.3, half_height: 0.14 },
				ShipHullSection{ z: -0.4, half_width: 0.5, half_height: 0.22 },
				ShipHullSection{ z: 0.45, half_width: 0.38, half_height: 0.17 },
				ShipHullSection{ z: 1.95, half_width: 0.05, half_height: 0.035 },
			], scale, base_color, alpha)
			for side in [f32(-1), f32(1)] {
				append_hull_wing(mut vertices, frame, side, 0.38, 1.5, 0.72, 0.02, -1.15, 0.05, scale, base_color, alpha)
				append_tapered_hull(mut vertices, frame, [
					ShipHullSection{ x: side * 0.7, z: -1.32, half_width: 0.19, half_height: 0.15 },
					ShipHullSection{ x: side * 0.7, z: -0.3, half_width: 0.25, half_height: 0.18 },
					ShipHullSection{ x: side * 0.7, z: 0.78, half_width: 0.035, half_height: 0.03 },
				], scale, darker_ship_color(base_color, 0.12), alpha)
			}
			append_tapered_hull(mut vertices, frame, [
				ShipHullSection{ y: 0.23, z: -0.3, half_width: 0.2, half_height: 0.09 },
				ShipHullSection{ y: 0.27, z: 0.42, half_width: 0.16, half_height: 0.11 },
				ShipHullSection{ y: 0.18, z: 1.05, half_width: 0.025, half_height: 0.02 },
			], scale, ship_nose_color(base_color), alpha)
		}
		else {
			append_tapered_hull(mut vertices, frame, [
				ShipHullSection{ z: -1.8, half_width: 0.5, half_height: 0.25 },
				ShipHullSection{ z: -0.55, half_width: 0.86, half_height: 0.4 },
				ShipHullSection{ z: 0.55, half_width: 0.62, half_height: 0.3 },
				ShipHullSection{ z: 3.15, half_width: 0.035, half_height: 0.025 },
			], scale, base_color, alpha)
			for side in [f32(-1), f32(1)] {
				append_hull_wing(mut vertices, frame, side, 0.62, 2.85, 1.35, 0.45, -1.65, 0.07, scale, base_color, alpha)
				append_tapered_hull(mut vertices, frame, [
					ShipHullSection{ x: side * 1.18, z: -1.65, half_width: 0.28, half_height: 0.22 },
					ShipHullSection{ x: side * 1.18, z: -0.4, half_width: 0.42, half_height: 0.3 },
					ShipHullSection{ x: side * 1.18, z: 2.65, half_width: 0.035, half_height: 0.025 },
				], scale, darker_ship_color(base_color, 0.08), alpha)
				append_hull_wing(mut vertices, frame, side, 0.72, 2.45, -0.45, -0.95, -1.8, 0.06, scale, darker_ship_color(base_color, 0.12), alpha)
			}
			append_boss_radial_spike(mut vertices, frame, f32(math.pi) * 0.27, scale, base_color, alpha)
			append_boss_radial_spike(mut vertices, frame, f32(math.pi) * 0.73, scale, base_color, alpha)
			append_tapered_hull(mut vertices, frame, [
				ShipHullSection{ y: 0.4, z: -0.45, half_width: 0.3, half_height: 0.12 },
				ShipHullSection{ y: 0.45, z: 0.5, half_width: 0.24, half_height: 0.15 },
				ShipHullSection{ y: 0.3, z: 2.25, half_width: 0.025, half_height: 0.02 },
			], scale, ship_nose_color(base_color), alpha)
		}
	}
}

fn append_panel_volume(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	structure ShipStructureGeometry, points []ShipMeshVec3, scale f32, color TunnelColor,
	alpha f32) {
	if points.len != 4 {
		return
	}
	front := points.map(transform_structure_vertex(it, structure))
	back := points.map(transform_structure_vertex(ShipMeshVec3{ x: it.x, y: 0.1, z: it.z }, structure))
	append_ship_quad(mut vertices, frame, front[0], front[1], front[2], front[3], scale, color, alpha)
	// The source fills only the front panel and outlines its shallow rear face.
	// Keep subdued back/edge faces for readable volume without letting several
	// translucent layers merge into a different, blocky silhouette.
	append_ship_quad(mut vertices, frame, back[3], back[2], back[1], back[0], scale, color, alpha * 0.18)
	for edge in 0 .. 4 {
		next := (edge + 1) % 4
		append_ship_quad(mut vertices, frame, front[edge], back[edge], back[next], front[next], scale, color, alpha * 0.28)
	}
}

fn append_ship_structure(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	structure ShipStructureGeometry, scale f32, foreground bool) {
	color := ship_structure_color(structure.color)
	base_alpha := if structure.color == 0 { f32(1) } else { f32(0.5) }
	alpha := if foreground { -base_alpha } else { base_alpha }
	if structure.shape == .rocket {
		for side in 0 .. 4 {
			angle := f32(side) * f32(math.pi) / 2 + f32(math.pi) / 4
			a := ShipMeshVec3{ x: f32(math.sin(angle - 0.3)), y: f32(math.cos(angle - 0.3)), z: -0.5 }
			b := ShipMeshVec3{ x: f32(math.sin(angle + 0.3)), y: f32(math.cos(angle + 0.3)), z: -0.5 }
			c := ShipMeshVec3{ x: f32(math.sin(angle + 0.3)), y: f32(math.cos(angle + 0.3)), z: 0.5 }
			d := ShipMeshVec3{ x: f32(math.sin(angle - 0.3)), y: f32(math.cos(angle - 0.3)), z: 0.5 }
			append_ship_quad(mut vertices, frame, transform_structure_vertex(a, structure), transform_structure_vertex(b, structure), transform_structure_vertex(c, structure), transform_structure_vertex(d, structure), scale, color, alpha)
		}
		return
	}
	divisions := int_max(1, structure.division_count)
	for index in 0 .. divisions {
		mut points := []ShipMeshVec3{cap: 4}
		match structure.shape {
			.square {
				x11 := -0.5 + f32(index) / f32(divisions)
				x12 := x11 + 0.8 / f32(divisions)
				x21 := -0.5 + 0.8 * f32(index) / f32(divisions)
				x22 := x21 + 0.64 / f32(divisions)
				points = [ShipMeshVec3{ x: x21, z: -0.5 }, ShipMeshVec3{ x: x22, z: -0.5 },
					ShipMeshVec3{ x: x12, z: 0.5 }, ShipMeshVec3{ x: x11, z: 0.5 }]
			}
			.wing {
				x1 := -0.5 + f32(index) / f32(divisions)
				x2 := x1 + 0.8 / f32(divisions)
				points = [ShipMeshVec3{ x: x1, z: x1 }, ShipMeshVec3{ x: x2, z: x2 },
					ShipMeshVec3{ x: x2, z: 0.5 }, ShipMeshVec3{ x: x1, z: 0.5 }]
			}
			.triangle {
				x1 := -0.5 + f32(index) / f32(divisions)
				x2 := x1 + 0.8 / f32(divisions)
				z1 := -0.5 + f32(math.abs(f64(index - divisions / 2))) * 2 / f32(divisions)
				z2 := -0.5 + f32(math.abs(f64(f32(index) + 0.8 - f32(divisions) / 2))) * 2 / f32(divisions)
				points = [ShipMeshVec3{ x: x1, z: z1 }, ShipMeshVec3{ x: x2, z: z2 },
					ShipMeshVec3{ x: x2, z: 0.5 }, ShipMeshVec3{ x: x1, z: 0.5 }]
			}
			.rocket {}
		}
		append_panel_volume(mut vertices, frame, structure, points, scale, color, alpha)
	}
}

fn append_source_player_hull(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	scale f32, foreground bool) {
	geometry := generate_ship_geometry(0, 1, false)
	for structure in geometry.structures {
		append_ship_structure(mut vertices, frame, structure, scale, foreground)
	}
}

fn append_readable_ship_geometry(mut vertices []CourseFillVertex, simulation &Simulation,
	kind int, source_color int, damaged bool, angle f32, depth f32, bank f32,
	radial_offset f32, scale f32, camera_angle f32, foreground bool) {
	frame := simulation.ship_mesh_frame(angle, depth, camera_angle, radial_offset, bank)
	append_readable_ship_hull(mut vertices, frame, kind, source_color, damaged, scale, foreground)
}

pub struct ShipMeshPreview {
pub:
	kind     int
	x        f32
	y        f32
	z        f32
	scale    f32
	selected bool
}

// render_ship_mesh_previews places the asymmetric player/enemy hulls directly
// in tuning-scene world space. Unlike the old billboard references, these
// retain their panel thickness while the inspection camera orbits them.
pub fn render_ship_mesh_previews(previews []ShipMeshPreview) []CourseFillVertex {
	return render_ship_mesh_previews_with_models(previews, ShipModelCatalog{})
}

pub fn render_ship_mesh_previews_with_models(previews []ShipMeshPreview, catalog ShipModelCatalog) []CourseFillVertex {
	mut vertices := []CourseFillVertex{cap: previews.len * 4096}
	for preview in previews {
		geometry_kind := if preview.kind < 0 { 0 } else { int_min(preview.kind, 2) }
		seed := match preview.kind {
			-1 { 1 }
			0 { 25_308 }
			1 { 41_719 }
			else { 62_047 }
		}
		geometry := generate_ship_geometry(geometry_kind, seed, false)
		frame := ShipMeshFrame{
			center: ShipMeshVec3{ x: preview.x, y: preview.y, z: preview.z }
			lateral: ShipMeshVec3{ x: 1 }
			normal: ShipMeshVec3{ y: 1 }
			forward: ShipMeshVec3{ z: 1 }
		}
		model := catalog.for_kind(preview.kind)
		if model.enabled {
			append_custom_ship_model(mut vertices, frame, model, preview.scale)
			continue
		}
		// Selection is already communicated by the focused camera and title. Do
		// not replace the seeded hull color with damage-white in TUNE.
		if preview.kind < 0 {
			append_source_player_hull(mut vertices, frame, preview.scale, false)
		} else {
			append_readable_ship_hull(mut vertices, frame, preview.kind, geometry.color, false, preview.scale, false)
		}
	}
	return vertices
}

fn append_custom_ship_model(mut vertices []CourseFillVertex, frame ShipMeshFrame,
	model ShipModel, scale f32) {
	for part in model.parts {
		color := ship_structure_color(part.color)
		alpha := f32(0.94)
		match part.kind {
			'tapered_hull', 'round_hull' {
				sections := part.sections.map(ShipHullSection{
					x: it.x
					y: it.y
					z: it.z
					half_width: it.half_width
					half_height: it.half_height
				})
				if part.kind == 'round_hull' {
					append_round_hull(mut vertices, frame, sections, scale, color, alpha)
				} else {
					append_tapered_hull(mut vertices, frame, sections, scale, color, alpha)
				}
			}
			'wing_pair' {
				for side in [f32(-1), f32(1)] {
					append_hull_wing(mut vertices, frame, side, part.root_width, part.span,
						part.front_z, part.tip_z, part.rear_z, part.thickness, scale, color,
						alpha)
				}
			}
			'spike_pair' {
				append_boss_radial_spike(mut vertices, frame, part.angle, scale, color, alpha)
				append_boss_radial_spike(mut vertices, frame, f32(math.pi) - part.angle,
					scale, color, alpha)
			}
			else {}
		}
	}
}

// render_ship_mesh_vertices_for_camera emits the readable low-poly hulls as
// real three-dimensional triangles. Bullets and particles remain
// resolution-independent sprites, while player/enemy hulls retain thickness in
// oblique and cinematic views.
pub fn (simulation &Simulation) render_ship_mesh_vertices_for_camera(camera_angle f32,
	scales RenderScales) []CourseFillVertex {
	mut vertices := []CourseFillVertex{cap: 16_384}
	ship_hidden := simulation.ship.lifecycle_counter < -228
		|| (simulation.ship.lifecycle_counter < 0
			&& (-simulation.ship.lifecycle_counter % 32) < 16)
	if !ship_hidden {
		clearance := player_ship_surface_clearance(scales.player)
		depth := simulation.ship.relative_depth + ship_render_depth_offset + player_ship_depth_clearance(scales.player)
		frame := simulation.ship_mesh_frame(simulation.ship.angle, depth, camera_angle, -clearance, simulation.ship.bank)
		// Build the segmented player racer. Its paired engine
		// shaft and divided wing panels match the earlier silhouette and make it
		// immediately distinct from the rounded and forked enemy hulls below.
		append_source_player_hull(mut vertices, frame, scales.player, true)
	}
	for enemy in simulation.enemies {
		if !enemy.alive {
			continue
		}
		spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
		geometry := generate_ship_geometry(enemy.kind, spec.shape_seed, enemy.damaged)
		scale := match enemy.kind {
			0 { scales.enemy_small }
			1 { scales.enemy_middle }
			else { scales.enemy_boss }
		}
		clearance := readable_hull_surface_clearance(enemy.kind, scale, enemy_surface_clearance(enemy.kind))
		append_readable_ship_geometry(mut vertices, simulation, enemy.kind, geometry.color, enemy.damaged, enemy.position.x, enemy.position.y, enemy.turn_speed, -clearance, scale, camera_angle, false)
	}
	for enemy in simulation.passed_enemies {
		if !enemy.alive {
			continue
		}
		spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
		geometry := generate_ship_geometry(enemy.kind, spec.shape_seed, false)
		scale := match enemy.kind {
			0 { scales.enemy_small }
			1 { scales.enemy_middle }
			else { scales.enemy_boss }
		}
		clearance := readable_hull_surface_clearance(enemy.kind, scale, enemy_surface_clearance(enemy.kind))
		append_readable_ship_geometry(mut vertices, simulation, enemy.kind, geometry.color, false, enemy.position.x, enemy.position.y, enemy.turn_speed, -clearance, scale, camera_angle, false)
	}
	return vertices
}
