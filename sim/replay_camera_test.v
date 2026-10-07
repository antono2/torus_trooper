// Checks camera wrap direction, reference poses, deterministic motion, and bounds.
module sim

import math

fn test_replay_camera_uses_expected_half_turn_wrap_direction() {
	assert replay_camera_angle_delta(0, f32(math.pi)) == -f32(math.pi)
	assert replay_camera_angle_delta(f32(math.pi), 0) == -f32(math.pi)
}

fn test_replay_camera_matches_known_first_tick() {
	mut camera := new_replay_camera(12345)
	camera.update(Ship{})
	assert f32(math.abs(camera.view_angle - (-0.367112935))) < 0.000001
	assert f32(math.abs(camera.depth_offset - (-47.4310989))) < 0.000001
	assert f32(math.abs(camera.height - 4.00353146)) < 0.000001
	assert camera.look_at_angle == 0
	assert camera.look_at_depth == 0
	assert camera.look_at_height == 0
	assert f32(math.abs(camera.rotation - (-0.367248893))) < 0.000001
	assert f32(math.abs(camera.zoom - 1.65418005)) < 0.000001
}

fn test_replay_camera_is_deterministic_and_bounded() {
	mut first := new_replay_camera(44)
	mut second := new_replay_camera(44)
	mut ship := Ship{ angle: 1.3, relative_depth: 4 }
	for tick in 0 .. 900 {
		ship.angle = wrap_angle(ship.angle + f32(tick % 3 - 1) * 0.002)
		first.update(ship)
		second.update(ship)
		assert first.view_angle == second.view_angle
		assert first.depth_offset == second.depth_offset
		assert first.height == second.height
		assert first.look_at_angle == second.look_at_angle
		assert first.look_at_depth == second.look_at_depth
		assert first.look_at_height == second.look_at_height
		assert first.rotation == second.rotation
		assert first.zoom == second.zoom
		assert first.zoom >= 0.1
		assert first.zoom <= 2
	}
	assert f32(math.abs(first.view_angle - 2.0568328)) < 0.00001
	assert f32(math.abs(first.depth_offset - (-1.1119311))) < 0.00001
	assert f32(math.abs(first.height - 11.726006)) < 0.00001
	assert f32(math.abs(first.look_at_angle - 1.0981444)) < 0.00001
	assert f32(math.abs(first.look_at_depth - 4.332701)) < 0.00001
	assert f32(math.abs(first.look_at_height - 5.6238437)) < 0.00001
	assert f32(math.abs(first.rotation - 1.2988195)) < 0.00001
	assert f32(math.abs(first.zoom - 0.9853087)) < 0.00001
}

fn test_replay_camera_float_mode_tracks_ship_relative_depth() {
	mut found_floating_seed := false
	for seed in 0 .. 32 {
		mut nearby := new_replay_camera(u32(seed))
		mut distant := new_replay_camera(u32(seed))
		nearby.update(Ship{ angle: 1, relative_depth: 4 })
		distant.update(Ship{ angle: 1, relative_depth: 14 })
		if nearby.move_type == .floating {
			found_floating_seed = true
			assert distant.move_type == .floating
			assert f32(math.abs((distant.depth_offset - nearby.depth_offset) - 10)) < 0.00001
			assert distant.look_at_depth == nearby.look_at_depth
			break
		}
	}
	assert found_floating_seed
}
