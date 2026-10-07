// Implements title, difficulty, and settings-menu choices and their display state.
module runtime

import sim

// Title navigation, settings changes and their HUD presentation.

// Stable HUD protocol IDs; see shaders/hud_state.h. Menu order is defined
// separately by cycled_title_menu_item.
enum TitleMenuItem {
	normal = 0
	hard = 1
	extreme = 2
	settings = 3
	help = 4
	tune = 5
	exit = 6
	replays = 7
}

enum TitleSettingsItem {
	volume
	antialiasing
	track_draw_distance
	wire_draw_distance
	border_draw_distance
	player_shot_distance
	fps_limit
	near_blur
	near_fade
	rear_track_blend
	back
}

fn (app &App) set_title_status(data PlayerData, start_levels []int, has_replay bool,
	active_menu_item TitleMenuItem, help_page int) {
	for grade_index in 0 .. 3 {
		grade := unsafe { sim.Grade(grade_index) }
		C.tt_platform_set_title_grade_info(app.platform, grade_index, start_levels[grade_index], title_max_level(data, grade, app.god_mode), data.high_scores[grade_index], data.high_score_start_levels[grade_index], data.high_score_end_levels[grade_index])
	}
	grade := int(app.grade)
	max_level := title_max_level(data, app.grade, app.god_mode)
	C.tt_platform_set_title_status(app.platform, grade, app.starting_level, max_level, data.high_scores[grade], data.high_score_start_levels[grade], data.high_score_end_levels[grade], has_replay, int(active_menu_item), app.volume_percent, help_page, app.god_mode, app.title_settings_open, int(app.title_settings_item), app.antialiasing_samples, app.near_blur_percent, app.near_fade_percent, app.rear_track_blend_percent, app.track_draw_distance, app.wire_draw_distance, app.border_draw_distance, int(app.object_sizes.player_shot_distance + 0.5), app.fps_limit)
}

fn title_menu_item_for_grade(grade sim.Grade) TitleMenuItem {
	return unsafe { TitleMenuItem(int(grade)) }
}

fn title_menu_grade(item TitleMenuItem) ?sim.Grade {
	if item !in [.normal, .hard, .extreme] {
		return none
	}
	return unsafe { sim.Grade(int(item)) }
}

fn title_menu_accepts_horizontal_activation(item TitleMenuItem) bool {
	return item in [.settings, .tune, .exit, .replays]
}

fn title_max_level(data PlayerData, grade sim.Grade, god_mode bool) int {
	return if god_mode {
		god_mode_max_start_level
	} else {
		int_min(data.reached_levels[int(grade)], god_mode_max_start_level)
	}
}

fn cycled_title_menu_item(item TitleMenuItem, delta int, god_mode bool) TitleMenuItem {
	items := if god_mode {
		[TitleMenuItem.normal, .hard, .extreme, .settings, .replays, .tune, .help, .exit]
	} else {
		[TitleMenuItem.normal, .hard, .extreme, .settings, .replays, .help, .exit]
	}
	mut index := items.index(item)
	if index < 0 {
		index = 0
	}
	index = (index + delta + items.len) % items.len
	return items[index]
}

fn cycled_title_settings_item(item TitleSettingsItem, delta int) TitleSettingsItem {
	item_count := int(TitleSettingsItem.back) + 1
	return unsafe { TitleSettingsItem((int(item) + delta % item_count + item_count) % item_count) }
}

fn normalized_track_draw_distance(distance int) int {
	return int_min(int_max(distance, minimum_track_draw_distance), maximum_track_draw_distance)
}

fn normalized_rear_track_blend_percent(percent int) int {
	return int_min(int_max(percent, 0), 100)
}

fn course_ring_count_for_draw_distance(distance int) int {
	return int_max(2, normalized_track_draw_distance(distance) + 1)
}

fn normalized_fps_limit(limit int) int {
	return if limit in [fps_limit_display, fps_limit_unlocked, 60] {
		limit
	} else {
		fps_limit_display
	}
}

fn stepped_fps_limit(limit int, direction int) int {
	values := [60, fps_limit_display, fps_limit_unlocked]
	mut index := values.index(normalized_fps_limit(limit))
	if index < 0 {
		index = 1
	}
	return values[(index + direction + values.len) % values.len]
}

fn fps_limit_label(limit int) string {
	return match normalized_fps_limit(limit) {
		fps_limit_display { 'display' }
		fps_limit_unlocked { 'unlocked' }
		else { '${limit}' }
	}
}

fn stepped_antialiasing_samples(samples int, direction int) int {
	values := [1, 2, 4, 8]
	mut index := values.index(samples)
	if index < 0 {
		index = 0
	}
	return values[(index + direction + values.len) % values.len]
}

const title_help_page_count = 3

fn cycled_help_page(page int, delta int) int {
	return (page + delta % title_help_page_count + title_help_page_count) % title_help_page_count
}

fn title_repeat_movement(was_pressed bool, repeat_ticks int) int {
	if !was_pressed {
		return 1
	}
	next_tick := repeat_ticks + 1
	if next_tick < 30 || next_tick % 5 != 0 {
		return 0
	}
	scale := next_tick / 30
	return scale * scale
}

fn settings_adjustment_on_release(pending int, left bool, right bool) (int, int) {
	if left || right {
		if left != right {
			return 0, if left { -1 } else { 1 }
		}
		return 0, pending
	}
	return pending, 0
}

fn title_setting_repeats(item TitleSettingsItem) bool {
	return item in [.volume, .track_draw_distance, .wire_draw_distance, .border_draw_distance,
		.player_shot_distance, .near_blur, .near_fade, .rear_track_blend]
}

fn title_moved_level(level int, max_level int, delta int, repeating bool) int {
	maximum := int_max(max_level, 1)
	next := level + delta
	if next < 1 {
		return if repeating { 1 } else { maximum }
	}
	if next > maximum {
		return if repeating { maximum } else { 1 }
	}
	return next
}

fn volume_percent_from_level(level f32) int {
	return int_min(int_max(int(level * 100 + 0.5), 0), 100)
}

fn stepped_volume_percent(percent int, direction int) int {
	return int_min(int_max(percent + direction * 5, 0), 100)
}

struct TitleVolumePreview {
mut:
	active     bool
	stop_at_ms i64
}

// arm returns true only when the caller needs to start music. Repeated slider
// movement keeps the current track playing and extends the audible sample.
fn (mut preview TitleVolumePreview) arm(now_ms i64) bool {
	should_start := !preview.active
	preview.active = true
	preview.stop_at_ms = now_ms + title_volume_preview_duration_ms
	return should_start
}

fn (mut preview TitleVolumePreview) take_expired(now_ms i64) bool {
	if !preview.active || now_ms < preview.stop_at_ms {
		return false
	}
	preview.cancel()
	return true
}

fn (mut preview TitleVolumePreview) cancel() {
	preview.active = false
	preview.stop_at_ms = 0
}

fn (app &App) volume_level() f32 {
	return f32(app.volume_percent) / 100
}

fn (mut app App) apply_volume(percent int, mut data PlayerData) {
	app.volume_percent = int_min(int_max(percent, 0), 100)
	data.volume_percent = app.volume_percent
	if !isnil(app.audio) {
		app.audio.set_volume(app.volume_level())
	}
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_antialiasing(samples int, mut data PlayerData) {
	applied := C.tt_platform_set_antialiasing(app.platform, samples)
	if applied <= 0 {
		eprintln('could not change anti-aliasing: ${unsafe { C.tt_platform_last_error().vstring() }}')
		return
	}
	app.antialiasing_samples = applied
	data.antialiasing_samples = applied
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_near_blur(percent int, mut data PlayerData) {
	app.near_blur_percent = int_min(int_max(percent, 0), 100)
	data.near_blur_percent = app.near_blur_percent
	C.tt_platform_set_near_camera_blur(app.platform, f32(app.near_blur_percent) / 100.0)
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_near_fade(percent int, mut data PlayerData) {
	app.near_fade_percent = int_min(int_max(percent, 0), 100)
	data.near_fade_percent = app.near_fade_percent
	C.tt_platform_set_near_camera_fade(app.platform, f32(app.near_fade_percent) / 100.0)
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_rear_track_blend(percent int, mut data PlayerData) {
	app.rear_track_blend_percent = normalized_rear_track_blend_percent(percent)
	data.rear_track_blend = app.rear_track_blend_percent
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_track_draw_distance(distance int, mut data PlayerData) {
	app.track_draw_distance = normalized_track_draw_distance(distance)
	data.track_draw_distance = app.track_draw_distance
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_wire_draw_distance(distance int, mut data PlayerData) {
	app.wire_draw_distance = normalized_track_draw_distance(distance)
	data.wire_draw_distance = app.wire_draw_distance
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_border_draw_distance(distance int, mut data PlayerData) {
	app.border_draw_distance = normalized_track_draw_distance(distance)
	data.border_draw_distance = app.border_draw_distance
	app.save_player_data_if_enabled(data)
}

fn (mut app App) apply_player_shot_distance(distance f32) {
	app.object_sizes.player_shot_distance = clamp_player_shot_distance(distance)
	if !app.persistence_enabled || app.object_sizes_path.len == 0 {
		return
	}
	save_object_sizes(app.object_sizes_path, app.object_sizes) or {
		eprintln('could not save player shot distance: ${err}')
	}
}

fn (mut app App) apply_fps_limit(limit int, mut data PlayerData) {
	normalized := normalized_fps_limit(limit)
	if !C.tt_platform_set_fps_limit(app.platform, normalized) {
		eprintln('could not change FPS limit: ${unsafe { C.tt_platform_last_error().vstring() }}')
		return
	}
	app.fps_limit = normalized
	data.fps_limit = normalized
	app.save_player_data_if_enabled(data)
}

// Returns true when a volume change needs an audible preview.
fn (mut app App) adjust_title_setting(direction int, movement int, mut data PlayerData) bool {
	match app.title_settings_item {
		.volume {
			next_volume := stepped_volume_percent(app.volume_percent, direction * movement)
			if next_volume != app.volume_percent {
				app.apply_volume(next_volume, mut data)
				return true
			}
		}
		.antialiasing {
			mut requested := stepped_antialiasing_samples(app.antialiasing_samples, direction)
			for requested != app.antialiasing_samples
				&& !C.tt_platform_antialiasing_supported(app.platform, requested) {
				requested = stepped_antialiasing_samples(requested, direction)
			}
			app.apply_antialiasing(requested, mut data)
		}
		.near_blur {
			app.apply_near_blur(app.near_blur_percent + direction * movement * 5, mut data)
		}
		.near_fade {
			app.apply_near_fade(app.near_fade_percent + direction * movement * 5, mut data)
		}
		.rear_track_blend {
			app.apply_rear_track_blend(app.rear_track_blend_percent + direction * movement, mut data)
		}
		.track_draw_distance {
			app.apply_track_draw_distance(app.track_draw_distance + direction * movement, mut data)
		}
		.wire_draw_distance {
			app.apply_wire_draw_distance(app.wire_draw_distance + direction * movement, mut data)
		}
		.border_draw_distance {
			app.apply_border_draw_distance(app.border_draw_distance + direction * movement, mut data)
		}
		.player_shot_distance {
			app.apply_player_shot_distance(app.object_sizes.player_shot_distance + f32(direction * movement))
		}
		.fps_limit {
			app.apply_fps_limit(stepped_fps_limit(app.fps_limit, direction), mut data)
		}
		.back {}
	}
	return false
}
