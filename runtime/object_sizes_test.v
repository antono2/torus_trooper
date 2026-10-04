module runtime

import math
import os
import sim

fn test_object_size_labels_match_saved_json_keys() {
	for index in 0 .. object_size_kind_count() {
		kind := object_size_kind(index)
		assert object_size_label(kind).to_lower() == kind.str()
	}
}

fn test_requested_high_resolution_object_sizes_are_the_defaults() {
	sizes := default_object_sizes()
	assert sizes.version == object_sizes_version
	assert sizes.player_shot_distance == 75
	assert sizes.player == 1.5
	assert sizes.player_shot == 2
	assert sizes.star_shot == 3
	assert sizes.charged_shot == 3
	assert sizes.enemy_small == 3
	assert sizes.enemy_middle == 3
	assert sizes.enemy_boss == 4
	assert sizes.boss_bit == 3
	assert sizes.bullet_triangle == 3.5
	assert sizes.bullet_square == 3.5
	assert sizes.bullet_bar == 3.5
	assert sizes.particle_spark == 4
	assert sizes.particle_jet == 4
	assert sizes.particle_star == 4
	assert sizes.particle_fragment == 4
	assert sizes.tunnel == 4
}

fn test_object_sizes_round_trip_and_clamp() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_object_sizes_${os.getpid()}')
	path := os.join_path(directory, 'object_sizes.json')
	defer { os.rmdir_all(directory) or {} }
	mut sizes := default_object_sizes()
	sizes.player_shot_distance = 72
	sizes.set(.player, 1.75)
	sizes.set(.particle_fragment, 100)
	sizes.set(.tunnel, 1.4)
	save_object_sizes(path, sizes) or { assert false, err.msg() }
	content := os.read_file(path) or { panic(err) }
	assert content.contains('"player"')
	assert content.contains('"player_shot_distance"')
	assert content.contains('"particle_fragment"')
	assert content.contains('"tunnel"')
	loaded := load_object_sizes(path)
	assert loaded.player_shot_distance == 72
	assert math.abs(loaded.player - 1.75) < 0.0001
	assert loaded.particle_fragment == object_size_max
	assert math.abs(loaded.tunnel - 1.4) < 0.0001
}

fn test_checked_object_sizes_reload_rejects_invalid_file() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_reload_${os.getpid()}')
	path := os.join_path(directory, 'object_sizes.json')
	defer { os.rmdir_all(directory) or {} }
	os.mkdir_all(directory) or { assert false, err.msg() }
	os.write_file(path, '{invalid json') or { assert false, err.msg() }
	if _ := load_object_sizes_checked(path) {
		assert false, 'malformed tuning data must not replace live sizes'
	} else {
		assert true
	}
	assert load_object_sizes(path).player == default_object_sizes().player
}

fn test_player_shot_distance_defaults_and_clamps_independently_of_visual_scales() {
	mut sizes := default_object_sizes()
	assert sizes.player_shot_distance == 75
	sizes.player_shot_distance = 1000
	sizes.normalize()
	assert sizes.player_shot_distance == player_shot_distance_max
	sizes.player_shot_distance = -4
	sizes.normalize()
	assert sizes.player_shot_distance == player_shot_distance_min
}

fn test_version_one_size_file_gains_the_current_shot_distance_default() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_legacy_sizes_${os.getpid()}')
	path := os.join_path(directory, 'object_sizes.json')
	defer { os.rmdir_all(directory) or {} }
	os.mkdir_all(directory) or { assert false, err.msg() }
	os.write_file(path, '{"version":1,"player":1.5}') or { assert false, err.msg() }
	loaded := load_object_sizes(path)
	assert loaded.version == object_sizes_version
	assert loaded.player == 1.5
	assert loaded.player_shot_distance == 75
}

fn test_calibration_scene_contains_each_visual_and_matching_label() {
	scene := new_calibration_scene()
	mut unfocused_scene := scene
	unfocused_scene.selected = -1
	instances := unfocused_scene.render_instances(default_object_sizes(), new_calibration_camera())
	ship_mesh_indices := [0, 4, 5, 6]
	assert instances.len == object_size_kind_count() * 2 - ship_mesh_indices.len
	for index in 0 .. object_size_kind_count() {
		visuals := instances.filter(it.kind == calibration_visual_kind_base + f32(index))
		labels := instances.filter(it.kind == calibration_label_kind_base + f32(index))
		assert labels.len == 1
		if index in ship_mesh_indices {
			assert visuals.len == 0
		} else {
			assert visuals.len == 1
			assert visuals[0].angle == labels[0].angle
			assert visuals[0].depth == labels[0].depth
			assert visuals[0].heading == labels[0].heading
		}
	}
}

fn test_calibration_camera_selection_follows_view_direction() {
	mut scene := new_calibration_scene()
	camera := new_calibration_camera()
	// The camera begins focused on the tunnel reference.
	assert scene.select(camera) == 15
}

fn test_calibration_selected_model_is_not_occluded_by_gallery() {
	mut scene := new_calibration_scene()
	scene.selected = 5
	mut camera := CalibrationCamera{ yaw: f32(math.pi / 2) }
	camera.focus_on(calibration_object_position(5), 10)
	sizes := default_object_sizes()
	assert scene.visible_for_focus(camera, sizes, 5)
	assert !scene.visible_for_focus(camera, sizes, 4)
	assert !scene.visible_for_focus(camera, sizes, 6)
	assert scene.visible_for_focus(camera, sizes, 1)
	instances := scene.render_instances(sizes, camera)
	assert instances.any(it.kind == calibration_label_kind_base + f32(5))
	assert !instances.any(it.kind == calibration_label_kind_base + f32(4))
	assert !instances.any(it.kind == calibration_label_kind_base + f32(6))
	assert instances.any(it.kind == calibration_label_kind_base + f32(1))
	assert scene.render_ship_meshes(sizes, sim.ShipModelCatalog{}, camera).len > 0
}

fn test_calibration_focus_distance_does_not_hide_object_scale_changes() {
	assert calibration_object_view_distance(0) == 1.5
	assert calibration_object_view_distance(6) == 3.2
	assert calibration_object_view_distance(15) == 5.0
}

fn test_calibration_gallery_objects_have_world_space_separation() {
	for left in 0 .. object_size_kind_count() {
		for right in left + 1 .. object_size_kind_count() {
			distance := calibration_object_position(left).subtract(calibration_object_position(right)).length()
			assert distance >= calibration_row_spacing - 0.001
		}
	}
}

fn test_calibration_tab_cycle_wraps_in_both_directions() {
	mut scene := new_calibration_scene()
	assert scene.cycle(1) == 0
	assert scene.cycle(1) == 1
	assert scene.cycle(-1) == 0
	assert scene.cycle(-1) == object_size_kind_count() - 1
}

fn test_calibration_camera_focus_and_orbit_keep_object_centered() {
	target := calibration_object_position(6)
	mut camera := new_calibration_camera()
	camera.focus_on(target, 3.5)
	assert camera.focus == target
	assert math.abs(camera.position.subtract(target).length() - 3.5) < 0.0001
	before := camera.position
	camera.update(sim.InputState{ right: true }, 0, 0, 0.5)
	assert camera.position != before
	assert math.abs(camera.position.subtract(target).length() - 3.5) < 0.0001
	assert camera.forward().dot(target.subtract(camera.position).normalized()) > 0.999
}

fn test_calibration_camera_w_and_s_dolly_without_crossing_target() {
	target := calibration_object_position(2)
	mut camera := new_calibration_camera()
	camera.focus_on(target, 4)
	camera.update(sim.InputState{ up: true }, 0, 0, 0.5)
	assert math.abs(camera.view_distance - 2.5) < 0.0001
	camera.update(sim.InputState{ down: true }, 0, 0, 0.5)
	assert math.abs(camera.view_distance - 4) < 0.0001
}
