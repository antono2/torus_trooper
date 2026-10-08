// Generates seeded ship structures, collision dimensions and exhaust offsets from shared geometry.
module sim

import math

pub enum ShipStructureShape {
	square
	wing
	triangle
	rocket
}

pub struct ShipStructureGeometry {
pub:
	position           Vec2
	rotation_z_degrees f32
	rotation_x_degrees f32
	width              f32
	height             f32
	shape              ShipStructureShape
	x_reverse          f32
	color              int
	division_count     int
}

pub struct ShipGeometry {
pub:
	collision      Vec2
	color          int
	rocket_offsets []f32
	structures     []ShipStructureGeometry
}

struct ShipGeometryBuilder {
mut:
	rng        Mt19937
	structures []ShipStructureGeometry
}

// generate_ship_geometry assembles seeded Structure values. Positions and
// dimensions remain in model coordinates so the renderer can consume the same
// definition used for collision and exhaust placement.
pub fn generate_ship_geometry(kind int, seed int, damaged bool) ShipGeometry {
	tier := int_max(0, int_min(2, kind))
	mut builder := ShipGeometryBuilder{
		rng: new_mt19937(u32(seed))
	}
	return match tier {
		1 { builder.create_middle(damaged) }
		2 { builder.create_large(damaged) }
		else { builder.create_small(damaged) }
	}
}

pub fn ship_shape_collision(kind int, seed int) Vec2 {
	return generate_ship_geometry(kind, seed, false).collision
}

pub fn ship_shape_rocket_offsets(kind int, seed int) []f32 {
	return generate_ship_geometry(kind, seed, false).rocket_offsets
}

fn (mut builder ShipGeometryBuilder) create_small(damaged bool) ShipGeometry {
	shaft_count := 1 + builder.rng.next_int(2)
	spacing := (f32(0.25) + builder.rng.next_f32(0.1)) * 1.5
	offset := (f32(0.5) + builder.rng.next_f32(0.3)) * 1.5
	length := (f32(0.7) + builder.rng.next_f32(0.9)) * 1.5
	wing_width := (f32(1.5) + builder.rng.next_f32(0.7)) * 1.5
	direction := builder.rng.next_f32(1) * f32(math.pi) / 3 + f32(math.pi) / 4
	pitch := builder.rng.next_f32(1) * f32(math.pi) / 10
	color := builder.rng.next_int(6) + 2
	shape := ship_structure_shape(builder.rng.next_int(3))
	mut rockets := []f32{}
	mut collision_width := f32(0)
	if shaft_count == 1 {
		builder.add_shaft(0, 0, offset, direction, length, 2, wing_width, direction / 2, pitch, color, shape, 5, 1, damaged)
		collision_width = offset / 2 + wing_width
		rockets << 0
	} else {
		builder.add_shaft(spacing, 0, offset, direction, length, 1, wing_width, direction / 2, pitch, color, shape, 5, 1, damaged)
		builder.add_shaft(spacing, 0, offset, direction, length, 1, wing_width, direction / 2, pitch, color, shape, 5, -1, damaged)
		collision_width = spacing + offset / 2 + wing_width
		rockets << spacing * 0.05
		rockets << -spacing * 0.05
	}
	return ShipGeometry{
		collision: Vec2{ x: collision_width * 0.1, y: length * 0.6 }
		color: color
		rocket_offsets: rockets
		structures: builder.structures.clone()
	}
}

fn (mut builder ShipGeometryBuilder) create_middle(damaged bool) ShipGeometry {
	shaft_count := 3 + builder.rng.next_int(2)
	spacing := (f32(1) + builder.rng.next_f32(0.7)) * 1.6
	offset := (f32(0.9) + builder.rng.next_f32(0.6)) * 1.6
	length := (f32(1.5) + builder.rng.next_f32(2)) * 1.6
	wing_width := (f32(2.5) + builder.rng.next_f32(1.4)) * 1.6
	direction := builder.rng.next_f32(1) * f32(math.pi) / 3 + f32(math.pi) / 4
	pitch := builder.rng.next_f32(1) * f32(math.pi) / 10
	color := builder.rng.next_int(6) + 2
	shape := ship_structure_shape(builder.rng.next_int(3))
	mut rockets := []f32{}
	if shaft_count == 3 {
		center_shape := ship_structure_shape(builder.rng.next_int(3))
		builder.add_shaft(0, 0, offset * 0.5, direction, length, 2, wing_width, direction, pitch, color, center_shape, 8, 1, damaged)
		builder.add_shaft(spacing, 0, offset, direction, length * 0.8, 1, wing_width, direction / 2, pitch, color, shape, 5, 1, damaged)
		builder.add_shaft(spacing, 0, offset, direction, length * 0.8, 1, wing_width, direction / 2, pitch, color, shape, 5, -1, damaged)
		rockets << 0
		rockets << spacing * 0.05
		rockets << -spacing * 0.05
	} else {
		builder.add_shaft(spacing / 3, -spacing / 2, offset, direction, length * 0.7, 1, wing_width * 0.6, direction / 3, pitch / 2, color, shape, 5, 1, false)
		builder.add_shaft(spacing / 3, -spacing / 2, offset, direction, length * 0.7, 1, wing_width * 0.6, direction / 3, pitch / 2, color, shape, 5, -1, false)
		builder.add_shaft(spacing, 0, offset, direction, length, 1, wing_width, direction / 2, pitch, color, shape, 5, 1, damaged)
		builder.add_shaft(spacing, 0, offset, direction, length, 1, wing_width, direction / 2, pitch, color, shape, 5, -1, damaged)
		rockets << spacing * 0.025
		rockets << -spacing * 0.025
		rockets << spacing * 0.05
		rockets << -spacing * 0.05
	}
	return ShipGeometry{
		collision: Vec2{
			x: (spacing + offset / 2 + wing_width) * 0.1
			y: length * 0.6
		}
		color: color
		rocket_offsets: rockets
		structures: builder.structures.clone()
	}
}

fn (mut builder ShipGeometryBuilder) create_large(damaged bool) ShipGeometry {
	shaft_count := 5 + builder.rng.next_int(2)
	spacing := (f32(3) + builder.rng.next_f32(2.2)) * 1.6
	offset := (f32(1.5) + builder.rng.next_f32(1)) * 1.6
	length := (f32(3) + builder.rng.next_f32(4)) * 1.6
	wing_width := (f32(5) + builder.rng.next_f32(2.5)) * 1.6
	direction := builder.rng.next_f32(1) * f32(math.pi) / 3 + f32(math.pi) / 4
	pitch := builder.rng.next_f32(1) * f32(math.pi) / 10
	color := builder.rng.next_int(6) + 2
	shape := ship_structure_shape(builder.rng.next_int(3))
	mut rockets := []f32{}
	if shaft_count == 5 {
		center_shape := ship_structure_shape(builder.rng.next_int(3))
		builder.add_shaft(0, 0, offset * 0.5, direction, length, 2, wing_width, direction, pitch, color, center_shape, 8, 1, damaged)
		builder.add_shaft(spacing * 0.6, 0, offset, direction, length * 0.6, 1, wing_width, direction / 3, pitch / 2, color, shape, 5, 1, damaged)
		builder.add_shaft(spacing * 0.6, 0, offset, direction, length * 0.6, 1, wing_width, direction / 3, pitch / 2, color, shape, 5, -1, damaged)
		builder.add_shaft(spacing, 0, offset, direction, length * 0.9, 1, wing_width, direction / 2, pitch, color, shape, 5, 1, damaged)
		builder.add_shaft(spacing, 0, offset, direction, length * 0.9, 1, wing_width, direction / 2, pitch, color, shape, 5, -1, damaged)
		rockets << 0
		rockets << spacing * 0.03
		rockets << -spacing * 0.03
		rockets << spacing * 0.05
		rockets << -spacing * 0.05
	} else {
		builder.add_shaft(spacing / 4, -spacing / 2, offset, direction, length * 0.6, 1, wing_width * 0.6, direction / 3, pitch / 2, color, shape, 5, 1, false)
		builder.add_shaft(spacing / 4, -spacing / 2, offset, direction, length * 0.6, 1, wing_width * 0.6, direction / 3, pitch / 2, color, shape, 5, -1, false)
		builder.add_shaft(spacing / 2, -spacing / 3 * 2, offset, direction, length * 0.8, 1, wing_width * 0.8, direction / 3, pitch / 3 * 2, color, shape, 5, 1, false)
		builder.add_shaft(spacing / 2, -spacing / 3 * 2, offset, direction, length * 0.8, 1, wing_width * 0.8, direction / 3, pitch / 3 * 2, color, shape, 5, -1, false)
		builder.add_shaft(spacing, 0, offset, direction, length, 1, wing_width, direction / 2, pitch, color, shape, 5, 1, damaged)
		builder.add_shaft(spacing, 0, offset, direction, length, 1, wing_width, direction / 2, pitch, color, shape, 5, -1, damaged)
		rockets << spacing * 0.0125
		rockets << -spacing * 0.0125
		rockets << spacing * 0.025
		rockets << -spacing * 0.025
		rockets << spacing * 0.05
		rockets << -spacing * 0.05
	}
	return ShipGeometry{
		collision: Vec2{
			x: (spacing + offset / 2 + wing_width) * 0.1
			y: length * 0.6
		}
		color: color
		rocket_offsets: rockets
		structures: builder.structures.clone()
	}
}

fn (mut builder ShipGeometryBuilder) add_shaft(ox f32, oy f32, offset f32, direction f32,
	rocket_length f32, wing_count int, wing_width f32, wing_rotation f32, pitch f32,
	color int, shape ShipStructureShape, division_count int, reverse int, damaged bool) {
	mut rocket_x := ox
	if reverse == -1 {
		rocket_x *= -1
	}
	builder.structures << ShipStructureGeometry{
		position: Vec2{ x: rocket_x, y: oy }
		width: rocket_length * 0.15
		height: rocket_length
		shape: .rocket
		x_reverse: 1
		color: if damaged { 0 } else { 1 }
	}
	wing_height := rocket_length * (builder.rng.next_f32(0.5) + 1.5)
	for index in 0 .. wing_count {
		mut position := Vec2{
			x: ox + f32(math.sin(direction)) * offset
			y: oy + f32(math.cos(direction)) * offset
		}
		mut rotation_z := wing_rotation * 180 / f32(math.pi)
		mut x_reverse := f32(1)
		if (index % 2 * 2 - 1) * reverse == 1 {
			position.x *= -1
			rotation_z *= -1
			x_reverse = f32(-1)
		}
		builder.structures << ShipStructureGeometry{
			position: position
			rotation_z_degrees: rotation_z
			rotation_x_degrees: pitch * 180 / f32(math.pi)
			width: wing_width
			height: wing_height
			shape: shape
			x_reverse: x_reverse
			color: if damaged { 0 } else { color }
			division_count: division_count
		}
	}
}

fn ship_structure_shape(value int) ShipStructureShape {
	return match value {
		0 { .square }
		1 { .wing }
		else { .triangle }
	}
}
