// Updates a deterministic replay camera from ship state and a separate seeded motion stream.
module sim

import math

const replay_camera_zoom_ticks = 24

enum ReplayCameraMoveType {
	floating
	fixed
}

fn replay_camera_angle_delta(from f32, to f32) f32 {
	mut delta := to - from
	for delta >= f32(math.pi) {
		delta -= f32(math.pi * 2)
	}
	for delta < -f32(math.pi) {
		delta += f32(math.pi * 2)
	}
	return delta
}

// ReplayCamera implements a seeded FLOAT/FIX camera state machine. The
// Vulkan renderer currently consumes the camera position angle/depth and zoom;
// the full look-at and height state is retained so later 3D projection work can
// use it without changing replay behavior or the random stream.
pub struct ReplayCamera {
pub mut:
	view_angle     f32
	depth_offset   f32
	height         f32
	look_at_angle  f32
	look_at_depth  f32
	look_at_height f32
	rotation       f32
	zoom           f32 = 1
mut:
	random             Mt19937
	move_type          ReplayCameraMoveType
	change_ticks       int
	move_ticks         int
	look_at_ticks      int
	target_angle       f32
	target_depth       f32
	target_height      f32
	angle_speed        f32
	depth_speed        f32
	height_speed       f32
	look_offset_angle  f32
	look_offset_depth  f32
	look_offset_height f32
	target_zoom        f32 = 1
	minimum_zoom       f32 = 0.5
}

pub fn new_replay_camera(seed u32) ReplayCamera {
	return ReplayCamera{
		random: new_mt19937(seed)
	}
}

pub fn (mut camera ReplayCamera) update(ship Ship) {
	camera.change_ticks--
	if camera.change_ticks < 0 {
		camera.start_move(ship)
	}
	camera.look_at_ticks--
	if camera.look_at_ticks == replay_camera_zoom_ticks {
		camera.look_offset_angle = camera.random.next_signed_f32(0.4)
		camera.look_offset_depth = camera.random.next_signed_f32(3)
		camera.look_offset_height = camera.random.next_signed_f32(10)
	} else if camera.look_at_ticks < 0 {
		camera.look_at_ticks = 32 + camera.random.next_int(48)
	}

	camera.target_angle += camera.angle_speed
	camera.target_depth += camera.depth_speed
	camera.target_height += camera.height_speed
	mut desired_angle := camera.target_angle
	mut desired_depth := camera.target_depth
	if camera.move_type == .fixed {
		desired_angle += ship.angle
		desired_depth += ship.relative_depth
		camera.rotation += replay_camera_angle_delta(camera.rotation, ship.angle) * 0.2
	}
	camera.view_angle += replay_camera_angle_delta(camera.view_angle, desired_angle) * 0.12
	camera.depth_offset += (desired_depth - camera.depth_offset) * 0.12
	camera.height += (camera.target_height - camera.height) * 0.12

	offset_ratio := if camera.look_at_ticks <= replay_camera_zoom_ticks {
		1 + f32(math.abs(camera.target_zoom - camera.zoom)) * 2.5
	} else {
		f32(1)
	}
	look_angle_delta := replay_camera_angle_delta(camera.look_at_angle, ship.angle + camera.look_offset_angle * offset_ratio)
	look_depth_delta := ship.relative_depth + camera.look_offset_depth * offset_ratio - camera.look_at_depth
	look_height_delta := camera.look_offset_height * offset_ratio - camera.look_at_height
	if camera.look_at_ticks <= replay_camera_zoom_ticks {
		camera.zoom += (camera.target_zoom - camera.zoom) * 0.16
		camera.look_at_angle += look_angle_delta * 0.2
		camera.look_at_depth += look_depth_delta * 0.2
		camera.look_at_height += look_height_delta * 0.2
	} else {
		camera.look_at_angle += look_angle_delta * 0.1
		// Preserve the camera's depth update, including its use of
		// angular delta outside the short zoom/reframe window.
		camera.look_at_depth += look_angle_delta * 0.1
		camera.look_at_height += look_height_delta * 0.1
	}
	camera.look_offset_angle *= 0.985
	camera.look_offset_depth *= 0.985
	camera.look_offset_height *= 0.985
	if f32(math.abs(camera.look_offset_angle)) < 0.04 {
		camera.look_offset_angle = 0
	}
	if f32(math.abs(camera.look_offset_depth)) < 0.3 {
		camera.look_offset_depth = 0
	}
	if f32(math.abs(camera.look_offset_height)) < 1 {
		camera.look_offset_height = 0
	}

	camera.move_ticks--
	if camera.move_ticks < 0 {
		camera.move_ticks = 15 + camera.random.next_int(15)
		mut angular_separation := f32(math.abs(camera.look_at_angle - camera.view_angle))
		if angular_separation > f32(math.pi) {
			angular_separation = f32(math.pi * 2) - angular_separation
		}
		offset := angular_separation * 3 + f32(math.abs(camera.look_at_depth - camera.depth_offset))
		camera.target_zoom = if offset > 0 { 3.0 / offset } else { 2 }
		if camera.target_zoom < camera.minimum_zoom {
			camera.target_zoom = camera.minimum_zoom
		} else if camera.target_zoom > 2 {
			camera.target_zoom = 2
		}
	}
	camera.look_at_angle = wrap_angle(camera.look_at_angle)
}

fn (mut camera ReplayCamera) start_move(ship Ship) {
	camera.move_type = if camera.random.next_int(2) == 0 { .floating } else { .fixed }
	if camera.move_type == .floating {
		camera.change_ticks = 256 + camera.random.next_int(150)
		camera.target_angle = ship.angle + camera.random.next_signed_f32(1)
		camera.target_depth = ship.relative_depth - 12 + camera.random.next_signed_f32(48)
		camera.target_height = f32(camera.random.next_int(32))
		camera.angle_speed = (ship.angle - camera.target_angle) / f32(camera.change_ticks) * (1 + camera.random.next_f32(1))
		camera.depth_speed = (ship.relative_depth - 12 - camera.target_depth) / f32(camera.change_ticks) * (1.5 + camera.random.next_f32(0.8))
		camera.height_speed = (16 - camera.target_height) / f32(camera.change_ticks) * camera.random.next_f32(1)
		camera.zoom = 1.2 + camera.random.next_f32(0.8)
		camera.target_zoom = camera.zoom
	} else {
		camera.change_ticks = 200 + camera.random.next_int(100)
		camera.target_angle = camera.random.next_signed_f32(0.3)
		camera.target_depth = -8 - camera.random.next_f32(12)
		camera.target_height = 8 + f32(camera.random.next_int(16))
		camera.angle_speed = (ship.angle - camera.target_angle) / f32(camera.change_ticks) * (1 + camera.random.next_f32(1))
		camera.depth_speed = camera.random.next_signed_f32(0.05)
		camera.height_speed = (10 - camera.target_height) / f32(camera.change_ticks) * camera.random.next_f32(0.5)
		camera.target_zoom = 1 + camera.random.next_signed_f32(0.25)
		camera.zoom = 0.2 + camera.random.next_f32(0.8)
	}
	camera.view_angle = camera.target_angle
	camera.depth_offset = camera.target_depth
	camera.height = camera.target_height
	camera.rotation = camera.target_angle
	camera.look_offset_angle = 0
	camera.look_offset_depth = 0
	camera.look_offset_height = 0
	camera.look_at_ticks = 0
	camera.minimum_zoom = 1 - camera.random.next_f32(0.9)
}
