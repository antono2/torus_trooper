module runtime

import json2
import os
import sim
import time

const player_data_version = 14

pub struct StoredReplay {
pub mut:
	name                 string
	recorded_at          i64
	score                int
	valid                bool
	grade                int
	starting_level       int = 1
	random_seed          u64
	inputs               []u8
	player_shot_distance f32 = 35
	god_mode             bool
}

pub struct PlayerData {
pub mut:
	version                 int = player_data_version
	selected_grade          int
	selected_level          int   = 1
	high_scores             []int = [0, 0, 0]
	high_score_start_levels []int = [1, 1, 1]
	high_score_end_levels   []int = [1, 1, 1]
	reached_levels          []int = [1, 1, 1]
	volume_percent          int   = default_volume_percent
	antialiasing_samples    int   = default_antialiasing_samples
	near_blur_percent       int   = default_near_blur_percent
	near_fade_percent       int   = default_near_fade_percent
	rear_track_blend        int   = default_rear_track_blend_percent
	track_draw_distance     int   = default_track_draw_distance
	wire_draw_distance      int   = default_wire_draw_distance
	border_draw_distance    int   = default_border_draw_distance
	fps_limit               int
	replay                  StoredReplay
	replays                 []StoredReplay
}

pub fn default_player_data() PlayerData {
	return PlayerData{}
}

pub fn load_player_data(path string) PlayerData {
	content := os.read_file(path) or { return default_player_data() }
	mut data := json2.decode[PlayerData](content) or { return default_player_data() }
	data.normalize()
	return data
}

pub fn save_player_data(path string, data PlayerData) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(data, prettify: true, escape_unicode: true))!
}

pub fn (mut data PlayerData) normalize() {
	if data.version < 11 && data.rear_track_blend == 1 {
		data.rear_track_blend = default_rear_track_blend_percent
	}
	if data.version < 14 && data.replays.len == 0 && data.replay.valid && replay_is_valid(data.replay) {
		data.replays << data.replay
	}
	data.replays = data.replays.filter(replay_is_valid(it))
	data.version = player_data_version
	data.selected_grade = clamp_int(data.selected_grade, 0, 2)
	data.selected_level = int_max(data.selected_level, 1)
	data.volume_percent = clamp_int(data.volume_percent, -1, 100)
	data.antialiasing_samples = normalize_stored_antialiasing(data.antialiasing_samples)
	data.near_blur_percent = clamp_int(data.near_blur_percent, -1, 100)
	data.near_fade_percent = clamp_int(data.near_fade_percent, -1, 100)
	data.rear_track_blend = clamp_int(data.rear_track_blend, -1, 100)
	data.track_draw_distance = if data.track_draw_distance < 0 {
		-1
	} else {
		clamp_int(data.track_draw_distance, minimum_track_draw_distance, maximum_track_draw_distance)
	}
	data.wire_draw_distance = if data.wire_draw_distance < 0 {
		-1
	} else {
		clamp_int(data.wire_draw_distance, minimum_track_draw_distance, maximum_track_draw_distance)
	}
	data.border_draw_distance = if data.border_draw_distance < 0 {
		-1
	} else {
		clamp_int(data.border_draw_distance, minimum_track_draw_distance, maximum_track_draw_distance)
	}
	data.fps_limit = normalize_stored_fps_limit(data.fps_limit)
	for data.high_scores.len < 3 {
		data.high_scores << 0
	}
	for data.reached_levels.len < 3 {
		data.reached_levels << 1
	}
	for data.high_score_start_levels.len < 3 {
		data.high_score_start_levels << 1
	}
	for data.high_score_end_levels.len < 3 {
		data.high_score_end_levels << 1
	}
	data.high_scores = data.high_scores[..3].clone()
	data.reached_levels = data.reached_levels[..3].clone()
	data.high_score_start_levels = data.high_score_start_levels[..3].clone()
	data.high_score_end_levels = data.high_score_end_levels[..3].clone()
	for index in 0 .. 3 {
		data.high_scores[index] = int_max(data.high_scores[index], 0)
		data.reached_levels[index] = int_max(data.reached_levels[index], 1)
		data.high_score_start_levels[index] = int_max(data.high_score_start_levels[index], 1)
		data.high_score_end_levels[index] = int_max(data.high_score_end_levels[index], data.high_score_start_levels[index])
	}
	if data.replay.grade < 0 || data.replay.grade > 2 || data.replay.starting_level < 1
		|| data.replay.inputs.len == 0 {
		data.replay = StoredReplay{}
	}
}

fn normalize_stored_fps_limit(limit int) int {
	return if limit in [-1, 0, 60] { limit } else { -2 }
}

fn normalize_stored_antialiasing(samples int) int {
	if samples < 0 {
		return -1
	}
	if samples >= 8 {
		return 8
	}
	if samples >= 4 {
		return 4
	}
	if samples >= 2 {
		return 2
	}
	return 1
}

pub fn (mut data PlayerData) record_start(grade sim.Grade, level int) {
	data.selected_grade = int(grade)
	data.selected_level = int_max(level, 1)
}

pub fn (mut data PlayerData) record_result(grade sim.Grade, start_level int, reached_level int,
	score int, replay sim.Replay) {
	index := int(grade)
	if score > data.high_scores[index] {
		data.high_scores[index] = score
		data.high_score_start_levels[index] = int_max(start_level, 1)
		data.high_score_end_levels[index] = int_max(reached_level, 1)
	}
	data.reached_levels[index] = int_max(data.reached_levels[index], reached_level)
	data.selected_grade = index
	data.selected_level = int_max(reached_level, 1)
	data.replay = StoredReplay{
		name:                 'Run ${data.replays.len + 1}'
		recorded_at:          time.now().unix()
		score:                score
		valid:                replay.inputs.len > 0
		grade:                index
		starting_level:       start_level
		random_seed:          replay.random_seed
		inputs:               replay.inputs.clone()
		player_shot_distance: replay.player_shot_distance
		god_mode:             replay.god_mode
	}
	if replay_is_valid(data.replay) {
		data.replays << data.replay
	}
}

pub fn (data &PlayerData) latest_replay() sim.Replay {
	return data.replay.simulation_replay()
}

fn clamp_int(value int, minimum int, maximum int) int {
	return int_min(int_max(value, minimum), maximum)
}
