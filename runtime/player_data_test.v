module runtime

import os
import sim

fn test_player_data_round_trip_and_result_tracking() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_player_data_test_${os.getpid()}')
	path := os.join_path(directory, 'player.json')
	defer { os.rmdir_all(directory) or {} }
	mut data := default_player_data()
	data.record_start(.hard, 4)
	data.volume_percent = 65
	data.antialiasing_samples = 4
	data.near_blur_percent = 65
	data.near_fade_percent = 70
	data.rear_track_blend = 58
	data.track_draw_distance = 66
	data.wire_draw_distance = 108
	data.border_draw_distance = 96
	data.fps_limit = 60
	data.record_result(.hard, 4, 7, 12345, sim.Replay{
		grade:          .hard
		starting_level: 4
		random_seed:    9981
		inputs:         [u8(1), 16, 32, 0]
	})
	save_player_data(path, data) or { assert false, err.msg() }
	loaded := load_player_data(path)
	assert loaded.selected_grade == int(sim.Grade.hard)
	assert loaded.selected_level == 7
	assert loaded.high_scores[int(sim.Grade.hard)] == 12345
	assert loaded.high_score_start_levels[int(sim.Grade.hard)] == 4
	assert loaded.high_score_end_levels[int(sim.Grade.hard)] == 7
	assert loaded.reached_levels[int(sim.Grade.hard)] == 7
	assert loaded.volume_percent == 65
	assert loaded.antialiasing_samples == 4
	assert loaded.near_blur_percent == 65
	assert loaded.near_fade_percent == 70
	assert loaded.rear_track_blend == 58
	assert loaded.track_draw_distance == 66
	assert loaded.wire_draw_distance == 108
	assert loaded.border_draw_distance == 96
	assert loaded.fps_limit == 60
	assert loaded.replay.valid
	assert loaded.latest_replay().inputs == [u8(1), 16, 32, 0]
}

fn test_lower_score_preserves_best_run_level_range() {
	mut data := default_player_data()
	data.record_result(.extreme, 3, 9, 5000, sim.Replay{})
	data.record_result(.extreme, 6, 12, 4000, sim.Replay{})
	assert data.high_scores[int(sim.Grade.extreme)] == 5000
	assert data.high_score_start_levels[int(sim.Grade.extreme)] == 3
	assert data.high_score_end_levels[int(sim.Grade.extreme)] == 9
	assert data.reached_levels[int(sim.Grade.extreme)] == 12
}

fn test_version_one_player_data_migrates_best_run_level_ranges() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_migration_test_${os.getpid()}')
	path := os.join_path(directory, 'player.json')
	defer { os.rmdir_all(directory) or {} }
	os.mkdir_all(directory) or { assert false, err.msg() }
	os.write_file(path, '{"version":1,"selected_grade":1,"selected_level":4,"high_scores":[0,12345,0],"reached_levels":[1,7,1]}') or {
		assert false, err.msg()
	}
	data := load_player_data(path)
	assert data.version == player_data_version
	assert data.high_scores == [0, 12345, 0]
	assert data.high_score_start_levels == [1, 1, 1]
	assert data.high_score_end_levels == [1, 1, 1]
	assert data.volume_percent == 35
	assert data.antialiasing_samples == 8
	assert data.near_blur_percent == 80
	assert data.near_fade_percent == 65
	assert data.rear_track_blend == default_rear_track_blend_percent
	assert data.track_draw_distance == 75
	assert data.wire_draw_distance == default_wire_draw_distance
	assert data.border_draw_distance == default_border_draw_distance
	assert data.fps_limit == 0
}

fn test_requested_presentation_settings_are_the_defaults() {
	data := default_player_data()
	assert data.volume_percent == 35
	assert data.antialiasing_samples == 8
	assert data.near_blur_percent == 80
	assert data.near_fade_percent == 65
	assert data.rear_track_blend == default_rear_track_blend_percent
	assert data.track_draw_distance == 75
	assert data.wire_draw_distance == default_wire_draw_distance
	assert data.border_draw_distance == default_border_draw_distance
	assert data.fps_limit == 0
}

fn test_previous_player_data_defaults_the_new_wire_horizon() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_wire_migration_${os.getpid()}')
	path := os.join_path(directory, 'player.json')
	defer { os.rmdir_all(directory) or {} }
	os.mkdir_all(directory) or { assert false, err.msg() }
	os.write_file(path, '{"version":11,"track_draw_distance":60}') or { assert false, err.msg() }
	data := load_player_data(path)
	assert data.version == player_data_version
	assert data.track_draw_distance == 60
	assert data.wire_draw_distance == default_wire_draw_distance
	assert data.border_draw_distance == default_border_draw_distance
}

fn test_saved_antialiasing_is_normalized_to_supported_menu_steps() {
	mut data := default_player_data()
	data.antialiasing_samples = 7
	data.normalize()
	assert data.antialiasing_samples == 4
	data.antialiasing_samples = 99
	data.normalize()
	assert data.antialiasing_samples == 8
	data.antialiasing_samples = 0
	data.normalize()
	assert data.antialiasing_samples == 1
}

fn test_saved_volume_is_clamped_during_load() {
	mut data := default_player_data()
	data.volume_percent = 170
	data.normalize()
	assert data.volume_percent == 100
	data.volume_percent = -20
	data.normalize()
	assert data.volume_percent == -1
}

fn test_saved_near_blur_is_clamped_during_load() {
	mut data := default_player_data()
	data.near_blur_percent = 170
	data.normalize()
	assert data.near_blur_percent == 100
	data.near_blur_percent = -20
	data.normalize()
	assert data.near_blur_percent == -1
}

fn test_saved_near_fade_is_clamped_during_load() {
	mut data := default_player_data()
	data.near_fade_percent = 140
	data.normalize()
	assert data.near_fade_percent == 100
	data.near_fade_percent = -50
	data.normalize()
	assert data.near_fade_percent == -1
}

fn test_saved_rear_track_blend_is_normalized() {
	mut data := default_player_data()
	data.rear_track_blend = 109
	data.normalize()
	assert data.rear_track_blend == 100
	data.rear_track_blend = -9
	data.normalize()
	assert data.rear_track_blend == -1
}

fn test_legacy_rear_track_toggle_migrates_to_slider() {
	mut on := PlayerData{ version: 10, rear_track_blend: 1 }
	on.normalize()
	assert on.rear_track_blend == default_rear_track_blend_percent
	mut off := PlayerData{ version: 10, rear_track_blend: 0 }
	off.normalize()
	assert off.rear_track_blend == 0
}

fn test_saved_track_draw_distance_is_normalized() {
	mut data := default_player_data()
	data.track_draw_distance = 1000
	data.normalize()
	assert data.track_draw_distance == maximum_track_draw_distance
	data.track_draw_distance = 0
	data.normalize()
	assert data.track_draw_distance == 0
	data.track_draw_distance = -9
	data.normalize()
	assert data.track_draw_distance == -1
	data.wire_draw_distance = 1000
	data.normalize()
	assert data.wire_draw_distance == maximum_track_draw_distance
	data.wire_draw_distance = 0
	data.normalize()
	assert data.wire_draw_distance == 0
	data.border_draw_distance = 1000
	data.normalize()
	assert data.border_draw_distance == maximum_track_draw_distance
	data.border_draw_distance = 0
	data.normalize()
	assert data.border_draw_distance == 0
}

fn test_saved_fps_limit_is_normalized() {
	for limit in [-1, 0, 60] {
		mut data := default_player_data()
		data.fps_limit = limit
		data.normalize()
		assert data.fps_limit == limit
	}
	mut invalid := default_player_data()
	invalid.fps_limit = 165
	invalid.normalize()
	assert invalid.fps_limit == -2
	mut unsupported := default_player_data()
	unsupported.fps_limit = 30
	unsupported.normalize()
	assert unsupported.fps_limit == -2
}

fn test_invalid_player_data_falls_back_safely() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_invalid_data_test_${os.getpid()}')
	path := os.join_path(directory, 'player.json')
	defer { os.rmdir_all(directory) or {} }
	os.mkdir_all(directory) or { assert false, err.msg() }
	os.write_file(path, '{ definitely not json') or { assert false, err.msg() }
	data := load_player_data(path)
	assert data.selected_grade == 0
	assert data.selected_level == 1
	assert data.reached_levels == [1, 1, 1]
	assert !data.replay.valid
}
