module runtime

import math
import sim

const calibration_visual_kind_base = f32(64)
const calibration_label_kind_base = f32(96)
const calibration_scene_depth = f32(12)
const calibration_column_spacing = f32(6.5)
const calibration_row_spacing = f32(4.5)
const calibration_orbit_speed = f32(1.25)
const calibration_dolly_speed = f32(3.0)
const calibration_min_view_distance = f32(1.2)
const calibration_max_view_distance = f32(12)
const calibration_resize_step = f32(0.1)
const calibration_tunnel_radius = f32(1.4175)
const calibration_height_scale = f32(1.35 / 21.0)
const calibration_depth_scale = f32(0.55)

struct CalibrationVec3 {
	x f32
	y f32
	z f32
}

fn (a CalibrationVec3) add(b CalibrationVec3) CalibrationVec3 {
	return CalibrationVec3{a.x + b.x, a.y + b.y, a.z + b.z}
}

fn (a CalibrationVec3) subtract(b CalibrationVec3) CalibrationVec3 {
	return CalibrationVec3{a.x - b.x, a.y - b.y, a.z - b.z}
}

fn (a CalibrationVec3) multiply(value f32) CalibrationVec3 {
	return CalibrationVec3{a.x * value, a.y * value, a.z * value}
}

fn (a CalibrationVec3) dot(b CalibrationVec3) f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

fn (a CalibrationVec3) length() f32 {
	return f32(math.sqrt(a.dot(a)))
}

fn (a CalibrationVec3) normalized() CalibrationVec3 {
	length := a.length()
	return if length > 0.00001 { a.multiply(1 / length) } else { CalibrationVec3{ z: 1 } }
}

struct CalibrationCamera {
mut:
	position      CalibrationVec3
	focus         CalibrationVec3
	yaw           f32
	pitch         f32
	view_distance f32 = 4.5
}

fn new_calibration_camera() CalibrationCamera {
	mut camera := CalibrationCamera{}
	camera.focus_on(calibration_object_position(15), 4.5)
	return camera
}

fn (camera &CalibrationCamera) forward() CalibrationVec3 {
	cos_pitch := f32(math.cos(camera.pitch))
	return CalibrationVec3{
		x: f32(math.sin(camera.yaw)) * cos_pitch
		y: -f32(math.sin(camera.pitch))
		z: f32(math.cos(camera.yaw)) * cos_pitch
	}.normalized()
}

fn (camera &CalibrationCamera) right() CalibrationVec3 {
	return CalibrationVec3{
		x: f32(math.cos(camera.yaw))
		z: -f32(math.sin(camera.yaw))
	}
}

fn (mut camera CalibrationCamera) focus_on(target CalibrationVec3, distance f32) {
	camera.focus = target
	camera.view_distance = f32_min(f32_max(distance, calibration_min_view_distance), calibration_max_view_distance)
	camera.position = camera.focus.subtract(camera.forward().multiply(camera.view_distance))
}

fn (mut camera CalibrationCamera) update(input sim.InputState, mouse_dx f32, mouse_dy f32,
	delta_seconds f32) {
	keyboard_orbit := if input.right { f32(1) } else { f32(0) } - if input.left {
		f32(1)
	} else {
		f32(0)
	}
	camera.yaw += mouse_dx * 0.0025 + keyboard_orbit * calibration_orbit_speed * delta_seconds
	camera.pitch = f32_min(f32_max(camera.pitch + mouse_dy * 0.0025, -1.35), 1.35)
	if input.up {
		camera.view_distance -= calibration_dolly_speed * delta_seconds
	}
	if input.down {
		camera.view_distance += calibration_dolly_speed * delta_seconds
	}
	camera.view_distance = f32_min(f32_max(camera.view_distance, calibration_min_view_distance), calibration_max_view_distance)
	camera.position = camera.focus.subtract(camera.forward().multiply(camera.view_distance))
}

struct CalibrationCameraParameters {
	eye_angle   f32
	eye_depth   f32
	eye_height  f32
	look_angle  f32
	look_depth  f32
	look_height f32
}

fn (camera &CalibrationCamera) parameters() CalibrationCameraParameters {
	look := camera.position.add(camera.forward())
	eye_angle, eye_height := calibration_cylinder_position(camera.position)
	look_angle, look_height := calibration_cylinder_position(look)
	return CalibrationCameraParameters{
		eye_angle:   eye_angle
		eye_depth:   camera.position.z / calibration_depth_scale
		eye_height:  eye_height
		look_angle:  look_angle
		look_depth:  look.z / calibration_depth_scale
		look_height: look_height
	}
}

fn calibration_cylinder_position(point CalibrationVec3) (f32, f32) {
	radius := f32(math.sqrt(point.x * point.x + point.y * point.y))
	angle := f32(math.atan2(-point.x, point.y))
	height := (calibration_tunnel_radius - radius) / calibration_height_scale
	return angle, height
}

struct CalibrationScene {
mut:
	selected int
}

fn new_calibration_scene() CalibrationScene {
	return CalibrationScene{ selected: 15 }
}

fn calibration_object_position(index int) CalibrationVec3 {
	column := index % 4
	row := index / 4
	return CalibrationVec3{
		x: (f32(column) - 1.5) * calibration_column_spacing
		y: (1.5 - f32(row)) * calibration_row_spacing
		z: calibration_scene_depth
	}
}

fn calibration_object_view_distance(index int) f32 {
	// Keep the inspection camera independent of the configured scale. Automatic
	// zoom compensation made a larger object look almost unchanged immediately
	// after Tab focused it, which hid whether the setting was actually applied.
	return match object_size_kind(index) {
		.tunnel, .charged_shot { f32(5.0) }
		.enemy_boss { f32(3.2) }
		.enemy_middle { f32(2.2) }
		.player, .particle_fragment { f32(1.5) }
		else { f32(1.2) }
	}
}

fn (mut scene CalibrationScene) cycle(step int) int {
	count := object_size_kind_count()
	if count <= 0 {
		scene.selected = -1
		return scene.selected
	}
	current := if scene.selected >= 0 { scene.selected } else { count - 1 }
	scene.selected = (current + step % count + count) % count
	return scene.selected
}

fn (mut scene CalibrationScene) select(camera CalibrationCamera) int {
	forward := camera.forward()
	mut best_index := -1
	mut best_score := f32(1000000)
	for index in 0 .. object_size_kind_count() {
		to_object := calibration_object_position(index).subtract(camera.position)
		along := to_object.dot(forward)
		if along <= 0 {
			continue
		}
		perpendicular := to_object.subtract(forward.multiply(along)).length()
		angular_score := perpendicular / along
		if angular_score < best_score {
			best_score = angular_score
			best_index = index
		}
	}
	scene.selected = if best_index >= 0 && best_score < 0.16 { best_index } else { -1 }
	return scene.selected
}

// Cull gallery previews that cover the selected model before sending either
// their cards or labels to Vulkan. The label cards are screen-facing and the
// transparent hulls do not write depth, so ordinary depth testing alone cannot
// keep a selected hull visible through another preview.
fn (scene &CalibrationScene) visible_for_focus(camera CalibrationCamera, sizes ObjectSizes, index int) bool {
	if scene.selected < 0 || index == scene.selected {
		return true
	}
	forward := camera.forward()
	to_focus := calibration_object_position(scene.selected).subtract(camera.position)
	to_object := calibration_object_position(index).subtract(camera.position)
	focus_depth := to_focus.dot(forward)
	object_depth := to_object.dot(forward)
	if focus_depth <= 0.05 {
		return true
	}
	if object_depth <= 0 {
		return false
	}
	// Compare projected angular footprints, not just world-space depths. This
	// preserves the rest of the gallery while removing previews that would paint
	// across the selected model, including large previews on the same Z plane.
	focus_angle := to_focus.subtract(forward.multiply(focus_depth)).multiply(1 / focus_depth)
	object_angle := to_object.subtract(forward.multiply(object_depth)).multiply(1 / object_depth)
	object_extent := calibration_preview_extent(index, sizes)
	focus_extent := calibration_preview_extent(scene.selected, sizes)
	return object_angle.subtract(focus_angle).length() > object_extent / object_depth +
		focus_extent / focus_depth + 0.02
}

fn calibration_preview_extent(index int, sizes ObjectSizes) f32 {
	scale := sizes.get(object_size_kind(index))
	return match object_size_kind(index) {
		.tunnel, .charged_shot { scale * 1.5 }
		.enemy_boss { scale * 0.8 }
		else { scale * 0.5 }
	}
}

fn (scene &CalibrationScene) render_instances(sizes ObjectSizes, camera CalibrationCamera) []sim.RenderInstance {
	mut instances := []sim.RenderInstance{cap: object_size_kind_count() * 2}
	for index in 0 .. object_size_kind_count() {
		if !scene.visible_for_focus(camera, sizes, index) {
			continue
		}
		position := calibration_object_position(index)
		scale := sizes.get(object_size_kind(index))
		// Player and enemy hulls have dedicated volumetric meshes. Keeping the old
		// shader cards here would superimpose a large, flat silhouette over them
		// and make side-on geometry inspection impossible.
		if index !in [0, 4, 5, 6] {
			instances << sim.RenderInstance{
				angle:   position.x
				depth:   position.y
				kind:    calibration_visual_kind_base + f32(index)
				heading: position.z
				scale:   if index == scene.selected { -scale } else { scale }
			}
		}
		instances << sim.RenderInstance{
			angle:   position.x
			depth:   position.y
			kind:    calibration_label_kind_base + f32(index)
			heading: position.z
			scale:   scale
		}
	}
	return instances
}

fn (scene &CalibrationScene) render_ship_meshes(sizes ObjectSizes, models sim.ShipModelCatalog, camera CalibrationCamera) []sim.CourseFillVertex {
	mut previews := []sim.ShipMeshPreview{cap: 4}
	for index in [0, 4, 5, 6] {
		if !scene.visible_for_focus(camera, sizes, index) {
			continue
		}
		position := calibration_object_position(index)
		previews << sim.ShipMeshPreview{
			kind:     if index == 0 { -1 } else { index - 4 }
			x:        position.x
			y:        position.y
			z:        position.z
			scale:    sizes.get(object_size_kind(index))
			selected: index == scene.selected
		}
	}
	return sim.render_ship_mesh_previews_with_models(previews, models)
}

fn calibration_object_visual_kind(index int) f32 {
	// Kept in one place so the shader's direct-world mapping remains auditable.
	return match object_size_kind(index) {
		.player { f32(1) }
		.player_shot { f32(2.1) }
		.star_shot { f32(2.35) }
		.charged_shot { f32(5.49) }
		.enemy_small { f32(3.00001) }
		.enemy_middle { f32(3.12501) }
		.enemy_boss { f32(3.25001) }
		.boss_bit { f32(4.6) }
		.bullet_triangle { f32(7) }
		.bullet_square { f32(9) }
		.bullet_bar { f32(11) }
		.particle_spark { f32(6.00051) }
		.particle_jet { f32(6.25051) }
		.particle_star { f32(6.50051) }
		.particle_fragment { f32(6.75051) }
		.tunnel { f32(63) }
	}
}
