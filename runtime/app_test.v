module runtime

import sim

fn test_runtime_ship_body_filter_only_selects_player_and_enemy_cards() {
	assert is_runtime_ship_body(sim.RenderInstance{ kind: 1 })
	assert is_runtime_ship_body(sim.RenderInstance{ kind: 3.249 })
	assert !is_runtime_ship_body(sim.RenderInstance{ kind: 2.1 })
	assert !is_runtime_ship_body(sim.RenderInstance{ kind: 4.6 })
	assert !is_runtime_ship_body(sim.RenderInstance{ kind: 7 })
}

fn test_ship_render_path_matches_the_active_camera_projection() {
	assert !keeps_instanced_ship_bodies(false)
	assert uses_volumetric_ship_meshes(false, true)
	assert keeps_instanced_ship_bodies(true)
	assert uses_volumetric_ship_meshes(true, false)
	assert !uses_volumetric_ship_meshes(false, false)
}

fn test_pause_overlay_blinks_from_wall_time_that_keeps_advancing() {
	assert C.tt_pause_overlay_visible(0)
	assert C.tt_pause_overlay_visible(1.0)
	assert !C.tt_pause_overlay_visible(1.25)
	assert C.tt_pause_overlay_visible(128.0 / 60.0)
}

fn test_app_config_defaults_to_gentler_master_volume() {
	assert AppConfig{}.audio_volume == f32(0.35)
}

fn test_input_state_maps_directions_and_buttons() {
	input := input_state(u32(1 | 8 | 16), false, false)
	assert input.left
	assert input.down
	assert input.fire
	assert !input.brake
	assert !input.right
	assert !input.up
}

fn test_input_state_reverses_only_primary_and_secondary_buttons() {
	input := input_state(u32(2 | 4 | 16), true, false)
	assert input.right
	assert input.up
	assert input.brake
	assert !input.fire
	assert !input.left
	assert !input.down
}

fn test_input_state_can_force_brake_for_effect_test() {
	input := input_state(0, false, true)
	assert input.brake
	assert !input.fire
}

fn test_adjacent_grade_wraps_in_both_directions() {
	assert adjacent_grade(.normal, -1) == sim.Grade.extreme
	assert adjacent_grade(.normal, 1) == sim.Grade.hard
	assert adjacent_grade(.extreme, 1) == sim.Grade.normal
}

fn test_gameplay_config_uses_title_selection() {
	config := gameplay_config(.hard, 12)
	assert config.grade == sim.Grade.hard
	assert config.starting_level == 12
	assert config.stage_progression
	assert config.procedural_course
	assert config.release_before_action
}

fn test_new_games_draw_distinct_replayable_mt19937_seeds() {
	mut source := sim.new_mt19937(1234)
	first := next_game_seed(mut source)
	second := next_game_seed(mut source)
	assert first == 822569775
	assert second == 2137449171
	assert first != second
	assert gameplay_config_with_seed(.normal, 1, first).random_seed == first
}

fn test_replay_config_enables_the_passed_enemy_pool() {
	config := replay_gameplay_config_with_seed(.hard, 4, 99)
	assert config.replay_mode
	assert config.grade == sim.Grade.hard
	assert config.starting_level == 4
	assert config.random_seed == 99
}

fn test_completed_run_replay_captures_final_run_identity() {
	simulation := sim.new_simulation(sim.SimulationConfig{
		grade:          .hard
		starting_level: 7
		random_seed:    9981
	})
	inputs := [u8(1), 2, 3]
	replay := completed_run_replay(.hard, 7, &simulation, inputs)
	assert replay.grade == .hard
	assert replay.starting_level == 7
	assert replay.random_seed == 9981
	assert replay.inputs == inputs
	assert replay.inputs.data != inputs.data
}

fn test_title_return_uses_the_current_runs_replay() {
	previous := sim.Replay{
		grade:          .normal
		starting_level: 2
		random_seed:    11
		inputs:         [u8(1)]
	}
	simulation := sim.new_simulation(sim.SimulationConfig{
		grade:          .extreme
		starting_level: 9
		random_seed:    8844
	})
	inputs := [u8(16), 17, 18]
	replay := replay_for_title_return(previous, .extreme, 9, &simulation, inputs)
	assert replay.grade == .extreme
	assert replay.starting_level == 9
	assert replay.random_seed == 8844
	assert replay.inputs == inputs
	assert replay.inputs.data != inputs.data
}

fn test_title_return_without_a_current_run_preserves_the_previous_replay() {
	previous := sim.Replay{
		grade:          .hard
		starting_level: 5
		random_seed:    99
		inputs:         [u8(32), 4]
	}
	simulation := sim.new_simulation(sim.SimulationConfig{
		random_seed: 123
	})
	replay := replay_for_title_return(previous, .normal, 1, &simulation, []u8{})
	assert replay == previous
}

fn test_music_sequence_matches_seeded_random_start_and_direction() {
	mut sequence := new_music_sequence(1234, 4, -1)
	assert sequence.track == 3
	assert sequence.direction == 1
	assert sequence.advance(4) == 0
	assert sequence.advance(4) == 1
	mut reverse := new_music_sequence(5489, 4, -1)
	assert reverse.track == 0
	assert reverse.direction == -1
	assert reverse.advance(4) == 3
}

fn test_music_sequence_avoids_repeating_the_previous_game_track() {
	sequence := new_music_sequence(1234, 4, 3)
	assert sequence.track == 0
	assert sequence.direction == 1
}

fn test_compute_backend_is_applied_without_changing_gameplay_config() {
	config := with_compute_backend(gameplay_config(.extreme, 4), .opencl)
	assert config.compute_backend == .opencl
	assert config.grade == sim.Grade.extreme
	assert config.starting_level == 4
	assert config.stage_progression
}

fn test_new_simulation_applies_the_shot_distance_from_object_sizes() {
	app := &App{
		object_sizes: ObjectSizes{
			player_shot_distance: 72
		}
	}
	simulation := app.new_simulation(sim.SimulationConfig{})
	assert simulation.config.player_shot_distance == 72
}

fn test_title_level_selection_wraps_within_reached_level() {
	assert cycled_level(1, 7, -1) == 7
	assert cycled_level(7, 7, 1) == 1
	assert cycled_level(3, 7, 1) == 4
	assert cycled_level(1, 1, 1) == 1
}

fn test_title_level_hold_accelerates_and_clamps_at_boundaries() {
	assert title_repeat_movement(false, 0) == 1
	assert title_repeat_movement(true, 28) == 0
	assert title_repeat_movement(true, 29) == 1
	assert title_repeat_movement(true, 59) == 4
	assert title_moved_level(1, 12, -1, false) == 12
	assert title_moved_level(12, 12, 1, false) == 1
	assert title_moved_level(10, 12, 4, true) == 12
	assert title_moved_level(2, 12, -4, true) == 1
}

fn test_settings_adjust_only_once_when_horizontal_input_is_released() {
	assert title_setting_repeats(.volume)
	assert title_setting_repeats(.track_draw_distance)
	assert title_setting_repeats(.wire_draw_distance)
	assert title_setting_repeats(.border_draw_distance)
	assert title_setting_repeats(.player_shot_distance)
	assert title_setting_repeats(.near_blur)
	assert title_setting_repeats(.near_fade)
	assert !title_setting_repeats(.antialiasing)
	assert !title_setting_repeats(.fps_limit)
	assert title_setting_repeats(.rear_track_blend)

	mut pending := 0
	mut released := 0
	released, pending = settings_adjustment_on_release(pending, false, true)
	assert released == 0
	assert pending == 1
	for _ in 0 .. 120 {
		released, pending = settings_adjustment_on_release(pending, false, true)
		assert released == 0
		assert pending == 1
	}
	released, pending = settings_adjustment_on_release(pending, false, false)
	assert released == 1
	assert pending == 0
	released, pending = settings_adjustment_on_release(pending, false, false)
	assert released == 0
	released, pending = settings_adjustment_on_release(pending, true, false)
	assert released == 0
	assert pending == -1
	released, pending = settings_adjustment_on_release(pending, false, false)
	assert released == -1
	assert pending == 0
}

fn test_title_menu_navigation_visits_grades_then_settings() {
	assert cycled_title_menu_item(.normal, 1, false) == .hard
	assert cycled_title_menu_item(.hard, 1, false) == .extreme
	assert cycled_title_menu_item(.extreme, 1, false) == .settings
	assert cycled_title_menu_item(.settings, 1, false) == .replays
	assert cycled_title_menu_item(.replays, 1, false) == .help
	assert cycled_title_menu_item(.help, 1, false) == .exit
	assert cycled_title_menu_item(.exit, 1, false) == .normal
	assert cycled_title_menu_item(.normal, -1, false) == .exit
	assert cycled_title_menu_item(.settings, 1, true) == .replays
	assert cycled_title_menu_item(.replays, 1, true) == .tune
	assert cycled_title_menu_item(.tune, 1, true) == .help
}

fn test_god_mode_exposes_every_three_digit_starting_level() {
	locked := PlayerData{
		reached_levels: [1, 1, 1]
	}
	assert title_max_level(locked, .extreme, false) == 1
	assert title_max_level(locked, .extreme, true) == 999
	assert title_moved_level(998, title_max_level(locked, .extreme, true), 1, false) == 999
}

fn test_title_grade_menu_items_map_to_game_grades() {
	assert title_menu_item_for_grade(.hard) == .hard
	assert title_menu_grade(.normal) or { panic('missing grade') } == .normal
	assert title_menu_grade(.extreme) or { panic('missing grade') } == .extreme
	assert int(TitleMenuItem.settings) == 3
	assert int(TitleMenuItem.help) == 4
	assert int(TitleMenuItem.tune) == 5
	assert int(TitleMenuItem.exit) == 6
	assert title_menu_grade(.settings) == none
	assert title_menu_grade(.help) == none
	assert title_menu_grade(.tune) == none
	assert title_menu_grade(.exit) == none
}

fn test_settings_navigation_and_antialiasing_steps_wrap() {
	assert cycled_title_settings_item(.volume, 1) == .antialiasing
	assert cycled_title_settings_item(.antialiasing, 1) == .track_draw_distance
	assert cycled_title_settings_item(.track_draw_distance, 1) == .wire_draw_distance
	assert cycled_title_settings_item(.wire_draw_distance, 1) == .border_draw_distance
	assert cycled_title_settings_item(.border_draw_distance, 1) == .player_shot_distance
	assert cycled_title_settings_item(.player_shot_distance, 1) == .fps_limit
	assert cycled_title_settings_item(.fps_limit, 1) == .near_blur
	assert cycled_title_settings_item(.near_blur, 1) == .near_fade
	assert cycled_title_settings_item(.near_fade, 1) == .rear_track_blend
	assert cycled_title_settings_item(.rear_track_blend, 1) == .back
	assert cycled_title_settings_item(.back, 1) == .volume
	assert cycled_title_settings_item(.volume, -1) == .back
	assert stepped_antialiasing_samples(1, 1) == 2
	assert stepped_antialiasing_samples(2, 1) == 4
	assert stepped_antialiasing_samples(4, 1) == 8
	assert stepped_antialiasing_samples(8, 1) == 1
	assert stepped_antialiasing_samples(1, -1) == 8
	assert normalized_track_draw_distance(-1) == minimum_track_draw_distance
	assert normalized_track_draw_distance(0) == 0
	assert normalized_track_draw_distance(64) == 64
	assert normalized_track_draw_distance(999) == 999
	assert normalized_track_draw_distance(1000) == maximum_track_draw_distance
	assert course_ring_count_for_draw_distance(0) == 2
	assert course_ring_count_for_draw_distance(64) == 65
	assert course_ring_count_for_draw_distance(999) == 1000
	assert stepped_fps_limit(60, 1) == fps_limit_display
	assert stepped_fps_limit(fps_limit_display, 1) == fps_limit_unlocked
	assert stepped_fps_limit(fps_limit_unlocked, 1) == 60
	assert stepped_fps_limit(60, -1) == fps_limit_unlocked
	assert normalized_fps_limit(30) == fps_limit_display
}

fn test_settings_fps_value_is_not_overwritten_by_title_high_score() {
	assert C.tt_title_rank_remaining_value(64, fps_limit_display, 123456) == fps_limit_display
	assert C.tt_title_rank_remaining_value(64, fps_limit_unlocked, 123456) == fps_limit_unlocked
	assert C.tt_title_rank_remaining_value(64, 60, 123456) == 60
	assert C.tt_title_rank_remaining_value(4, 60, 123456) == 123456
}

fn test_display_fps_uses_active_monitor_refresh_rate() {
	assert C.tt_target_frame_rate(fps_limit_display, 165) == 165
	assert C.tt_target_frame_rate(fps_limit_display, 60) == 60
	assert C.tt_target_frame_rate(fps_limit_display, 0) == 60
	assert C.tt_target_frame_rate(60, 165) == 60
	assert C.tt_target_frame_rate(fps_limit_unlocked, 165) == 0
}

fn test_horizontal_menu_activation_preserves_adjustable_items() {
	assert title_menu_accepts_horizontal_activation(.settings)
	assert title_menu_accepts_horizontal_activation(.tune)
	assert title_menu_accepts_horizontal_activation(.exit)
	assert !title_menu_accepts_horizontal_activation(.normal)
	assert !title_menu_accepts_horizontal_activation(.help)
}

fn test_rear_track_blend_slider_clamps_and_saves() {
	mut app := App{
		rear_track_blend_percent: 10
		persistence_enabled:      false
	}
	mut data := default_player_data()
	app.apply_rear_track_blend(-1, mut data)
	assert app.rear_track_blend_percent == 0
	assert data.rear_track_blend == 0
	app.apply_rear_track_blend(58, mut data)
	assert app.rear_track_blend_percent == 58
	assert data.rear_track_blend == 58
	app.apply_rear_track_blend(101, mut data)
	assert app.rear_track_blend_percent == 100
	assert data.rear_track_blend == 100
}

fn test_settings_player_shot_distance_applies_immediately_and_clamps() {
	mut app := App{
		object_sizes:        default_object_sizes()
		persistence_enabled: false
	}
	app.apply_player_shot_distance(91)
	assert app.object_sizes.player_shot_distance == 91
	app.apply_player_shot_distance(1000)
	assert app.object_sizes.player_shot_distance == player_shot_distance_max
	app.apply_player_shot_distance(-1)
	assert app.object_sizes.player_shot_distance == player_shot_distance_min
}

fn test_antialiasing_falls_back_to_the_highest_common_supported_mode() {
	assert C.tt_antialiasing_sample_count(8, u32(1 | 2 | 4 | 8)) == 8
	assert C.tt_antialiasing_sample_count(8, u32(1 | 2 | 4)) == 4
	assert C.tt_antialiasing_sample_count(4, u32(1 | 2)) == 2
	assert C.tt_antialiasing_sample_count(2, u32(1)) == 1
}

fn test_each_title_difficulty_keeps_its_own_level_limit() {
	data := PlayerData{
		reached_levels: [2, 5, 8]
	}
	assert title_max_level(data, .normal, false) == 2
	assert title_max_level(data, .hard, false) == 5
	assert title_max_level(data, .extreme, false) == 8
	assert title_max_level(data, .normal, true) == 999
	assert title_max_level(data, .hard, true) == 999
	assert title_max_level(data, .extreme, true) == 999
}

fn test_title_help_pages_wrap_with_the_slider_buttons() {
	assert cycled_help_page(0, 1) == 1
	assert cycled_help_page(2, 1) == 0
	assert cycled_help_page(0, -1) == 2
	assert cycled_help_page(1, 4) == 2
}

fn test_help_disables_the_title_replay_command() {
	assert !title_replay_toggle_allowed(.help, true)
	assert !title_replay_toggle_allowed(.tune, true)
	assert !title_replay_toggle_allowed(.settings, true)
	assert title_replay_toggle_allowed(.normal, true)
	assert !title_replay_toggle_allowed(.normal, false)
	assert title_menu_input_mask(u32(32), true, .help) == 0
	assert title_menu_input_mask(u32(32), true, .normal) == 32
	assert title_menu_input_mask(u32(32), false, .help) == 32
	assert !input_state(title_menu_input_mask(u32(32), true, .help), false, false).brake
	assert !input_state(title_menu_input_mask(u32(32), true, .help), true, false).fire
}

fn test_volume_uses_five_percent_steps_and_clamps() {
	assert volume_percent_from_level(0.35) == 35
	assert volume_percent_from_level(-1) == 0
	assert volume_percent_from_level(2) == 100
	assert stepped_volume_percent(35, -1) == 30
	assert stepped_volume_percent(35, 1) == 40
	assert stepped_volume_percent(0, -1) == 0
	assert stepped_volume_percent(100, 1) == 100
}

fn test_title_volume_preview_runs_for_three_seconds_after_the_latest_change() {
	mut preview := TitleVolumePreview{}
	assert preview.arm(1_000)
	assert preview.active
	assert preview.stop_at_ms == 4_000
	assert !preview.take_expired(3_999)
	assert !preview.arm(2_500)
	assert preview.stop_at_ms == 5_500
	assert !preview.take_expired(4_000)
	assert preview.take_expired(5_500)
	assert !preview.active
	assert preview.arm(6_000)
	preview.cancel()
	assert !preview.take_expired(9_000)
}

fn test_volume_binding_key_names_cover_defaults_and_documented_aliases() {
	assert C.tt_key_from_name(c'plus') >= 0
	assert C.tt_key_from_name(c'-') >= 0
	assert C.tt_key_from_name(c'page_up') >= 0
	assert C.tt_key_from_name(c'kp_subtract') >= 0
	assert C.tt_key_from_name(c'left_shift') >= 0
	assert C.tt_key_from_name(c'left_control') >= 0
	assert C.tt_key_from_name(c'escape') >= 0
	assert C.tt_key_from_name(c'kp_8') >= 0
	assert C.tt_key_from_name(c'f1') >= 0
	assert C.tt_key_from_name(c'F25') >= 0
	assert C.tt_key_from_name(c'gamepad_a') != -1
	assert C.tt_key_from_name(c'controller_a') == C.tt_key_from_name(c'gamepad_a')
	assert C.tt_key_from_name(c'gamepad_left_stick_left') != -1
	assert C.tt_key_from_name(c'gamepad_right_trigger') != -1
	assert C.tt_key_from_name(c'joystick_button_16') != -1
	assert C.tt_key_from_name(c'joystick_axis_8_positive') != -1
	assert C.tt_key_from_name(c'not_a_key') < 0
}

fn test_god_mode_phrase_is_case_insensitive_and_resets_after_a_mismatch() {
	mut index := 0
	for character in 'ItsTantrum'.bytes() {
		index = C.tt_god_mode_sequence_step(index, u32(character))
	}
	assert index == -1
	index = C.tt_god_mode_sequence_step(0, u32(`i`))
	index = C.tt_god_mode_sequence_step(index, u32(`x`))
	assert index == 0
	index = C.tt_god_mode_sequence_step(index, u32(`i`))
	assert index == 1
}

fn test_presentation_fade_covers_transitions_and_game_over() {
	assert presentation_fade(30, 0) == 1
	assert presentation_fade(15, 0) == 0.5
	assert presentation_fade(0, 0) == 0
	assert presentation_fade(0, 120) == 0.65
	assert presentation_fade(30, 120) == 1
}

fn test_title_attract_replay_advances_silently_behind_selection() {
	assert should_advance_simulation(true, false, true, false)
	assert should_advance_simulation(true, true, false, false)
	assert !should_advance_simulation(true, false, false, false)
	assert !should_advance_simulation(true, false, true, true)
}

fn test_title_without_replay_hides_the_game_world() {
	assert !should_render_world(true, false, false, false)
	assert should_render_world(true, true, false, false)
	assert should_render_world(true, false, true, false)
	assert !should_render_world(true, false, true, true)
	assert should_render_world(false, false, false, true)
}

fn test_title_replay_view_toggles_without_restarting_playback() {
	shown := toggled_title_replay(false, true)
	assert shown.replay_mode
	assert !shown.attract_replay
	hidden := toggled_title_replay(shown.replay_mode, true)
	assert !hidden.replay_mode
	assert hidden.attract_replay
	missing := toggled_title_replay(false, false)
	assert !missing.replay_mode
	assert !missing.attract_replay
}

fn test_title_replay_transition_advances_and_retracts_over_30_frames() {
	assert stepped_title_replay_transition(0, true) == 1
	assert stepped_title_replay_transition(29, true) == 30
	assert stepped_title_replay_transition(30, true) == 30
	assert stepped_title_replay_transition(30, false) == 29
	assert stepped_title_replay_transition(1, false) == 0
	assert stepped_title_replay_transition(0, false) == 0
}

fn test_title_replay_viewport_expands_from_four_fifths_to_full_width() {
	assert C.tt_title_replay_viewport_fraction(-1) == 0.8
	assert C.tt_title_replay_viewport_fraction(0) == 0.8
	assert C.tt_title_replay_viewport_fraction(0.25) == 0.92
	assert C.tt_title_replay_viewport_fraction(1) == 1
	assert C.tt_title_replay_viewport_fraction(2) == 1
}

fn test_title_replay_viewport_moves_from_torus_center_to_full_screen() {
	initial_x := C.tt_title_replay_viewport_x_fraction(0)
	transition_x := C.tt_title_replay_viewport_x_fraction(0.25)
	assert initial_x > 0.019 && initial_x < 0.021
	assert transition_x > 0.007 && transition_x < 0.009
	assert C.tt_title_replay_viewport_x_fraction(-1) == initial_x
	assert C.tt_title_replay_viewport_x_fraction(1) == 0
}

fn test_course_grid_width_scales_from_the_480p_frame() {
	assert C.tt_course_line_width_for_extent(480, true, 8) == 1
	assert C.tt_course_line_width_for_extent(720, true, 8) == 1.5
	assert C.tt_course_line_width_for_extent(1080, true, 8) == 2.25
	assert C.tt_course_line_width_for_extent(2160, true, 3) == 3
	assert C.tt_course_line_width_for_extent(1080, false, 8) == 1
	assert C.tt_course_line_width_for_extent(1080, true, 0) == 1
}

fn test_dynamic_vertex_buffers_keep_each_in_flight_frame_separate() {
	for slot in [instance_buffer_slot, tunnel_buffer_slot, tunnel_fill_buffer_slot] {
		frame_size := C.tt_platform_buffer_frame_size(slot)
		total_size := C.tt_platform_buffer_size(slot)
		assert frame_size > 0
		assert total_size > frame_size
		assert total_size % frame_size == 0
	}
}

fn test_title_replay_view_ratio_only_contracts_a_title_with_replay_data() {
	assert title_replay_view_ratio(true, true, 0) == 0
	assert title_replay_view_ratio(true, true, 15) == 0.5
	assert title_replay_view_ratio(true, true, 30) == 1
	assert title_replay_view_ratio(true, false, 0) == 1
	assert title_replay_view_ratio(false, true, 0) == 1
}

fn test_camera_eye_depth_stays_in_source_course_units() {
	assert camera_depth_for_render(true, -47.4311, 10) == -47.4311
	assert camera_depth_for_render(false, -47.4311, 0) == 0
	assert camera_depth_for_render(false, -47.4311, 10) == -3
}

fn test_only_live_gameplay_emits_simulation_audio() {
	assert should_play_simulation_audio(false, false, false)
	assert !should_play_simulation_audio(true, false, true)
	assert !should_play_simulation_audio(true, true, false)
	assert !should_play_simulation_audio(false, true, false)
}

fn test_game_over_return_has_input_delay_and_idle_timeout() {
	assert !should_return_to_title(false, true, true, false, 60)
	assert should_return_to_title(false, true, true, false, 61)
	assert !should_return_to_title(false, true, true, true, 61)
	assert should_return_to_title(false, true, false, false, 1201)
	assert !should_return_to_title(true, true, true, false, 1201)
}

fn test_title_replay_end_waits_through_expected_game_over_tail() {
	assert !replay_input_ended(119, 120)
	assert replay_input_ended(120, 120)
	assert !should_restart_title_replay(120)
	assert should_restart_title_replay(121)
}

fn test_gameplay_status_refreshes_immediately_for_pause_and_game_over() {
	assert should_refresh_gameplay_status(true, false, 3)
	assert should_refresh_gameplay_status(false, true, 3)
	assert should_refresh_gameplay_status(false, false, 20)
	assert !should_refresh_gameplay_status(false, false, 21)
}

fn test_full_title_replay_switches_to_gameplay_status_atomically() {
	assert !title_replay_uses_gameplay_status(true, true, 29)
	assert title_replay_uses_gameplay_status(true, true, 30)
	assert !title_replay_uses_gameplay_status(true, false, 30)
	assert !title_replay_uses_gameplay_status(false, true, 30)
}

fn test_escape_input_bit_is_separate_from_restart_and_gameplay_input() {
	assert input_state(u32(256), false, false) == sim.InputState{}
	assert u32(256) & 128 == 0
}
