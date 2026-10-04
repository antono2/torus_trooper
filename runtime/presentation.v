module runtime

// Presentation state decisions shared by the main loop and runtime tests.

fn presentation_fade(transition_frames int, game_over_frames int) f32 {
	transition := f32(int_max(transition_frames, 0)) / f32(menu_transition_frames)
	game_over := f32(int_min(int_max(game_over_frames, 0), game_over_fade_frames)) / f32(game_over_fade_frames) * game_over_fade_opacity
	return if transition > game_over { transition } else { game_over }
}

struct TitleReplayView {
	replay_mode    bool
	attract_replay bool
}

fn toggled_title_replay(replay_mode bool, has_replay bool) TitleReplayView {
	if !has_replay {
		return TitleReplayView{
			replay_mode: replay_mode
		}
	}
	return TitleReplayView{
		replay_mode:    !replay_mode
		attract_replay: replay_mode
	}
}

fn title_replay_toggle_allowed(menu_item TitleMenuItem, has_replay bool) bool {
	return menu_item !in [.settings, .help, .tune, .replays, .exit] && has_replay
}

fn stepped_title_replay_transition(frames int, replay_mode bool) int {
	if replay_mode {
		return int_min(frames + 1, replay_transition_frames)
	}
	return int_max(frames - 1, 0)
}

fn title_replay_view_ratio(title_mode bool, has_replay bool, frames int) f32 {
	if !title_mode || !has_replay {
		return 1
	}
	return f32(int_min(int_max(frames, 0), replay_transition_frames)) / f32(replay_transition_frames)
}

fn camera_depth_for_render(cinematic bool, replay_depth f32, ship_relative_depth f32) f32 {
	// Both camera paths use course units. In gameplay the camera
	// advances by 30% of the ship's longitudinal offset, leaving 70% as visible
	// ship movement. The 2D shaders negate this eye movement when forming their
	// view depth and apply the shared course-depth scale themselves.
	return if cinematic { replay_depth } else { -ship_relative_depth * 0.3 }
}

fn should_play_simulation_audio(title_mode bool, replay_mode bool, attract_replay bool) bool {
	return !title_mode && !replay_mode && !attract_replay
}

fn should_advance_simulation(title_mode bool, replay_mode bool, attract_replay bool,
	paused bool) bool {
	return !paused && (!title_mode || replay_mode || attract_replay)
}

fn should_render_world(title_mode bool, replay_mode bool, attract_replay bool,
	title_help_visible bool) bool {
	return !title_mode || (!title_help_visible && (replay_mode || attract_replay))
}

fn should_return_to_title(title_mode bool, game_over bool, restart_down bool,
	restart_pressed bool, game_over_frames int) bool {
	return !title_mode && game_over
		&& (game_over_frames > game_over_auto_return_frames || (game_over_frames > game_over_restart_delay_frames && restart_down && !restart_pressed))
}

fn should_refresh_gameplay_status(paused bool, game_over bool, tick int) bool {
	return paused || game_over || tick % gameplay_status_interval_ticks == 0
}

fn replay_uses_cinematic_camera(replay_mode bool, attract_replay bool, cinematic_selected bool) bool {
	return if replay_mode { cinematic_selected } else { attract_replay }
}

fn title_replay_uses_gameplay_status(title_mode bool, replay_mode bool,
	replay_change_frames int) bool {
	return title_mode && replay_mode && replay_change_frames == replay_transition_frames
}

fn replay_input_ended(input_index int, input_count int) bool {
	return input_index >= input_count
}

fn should_restart_title_replay(game_over_ticks int) bool {
	return game_over_ticks > attract_replay_restart_delay_ticks
}

