module runtime

import time

// Presentation state decisions shared by the main loop and runtime tests.

// Use monotonic milliseconds: changing the system clock must not skip a fade
// or return a completed game to the title. Simulation/replay ticks stay separate.
fn presentation_time_ms() i64 {
	return i64(time.sys_mono_now() / 1_000_000)
}

struct PresentationTimers {
mut:
	transition_remaining_ms i64 = menu_transition_duration_ms
	game_over_elapsed_ms    i64
	replay_change_ms        i64
}

fn clamped_presentation_ms(value i64, duration i64) i64 {
	return if value < 0 { i64(0) } else if value > duration { duration } else { value }
}

fn (mut timers PresentationTimers) advance(elapsed_ms i64, title_mode bool, game_over bool,
	replay_mode bool, calibration_mode bool) {
	delta := if elapsed_ms > 0 { elapsed_ms } else { i64(0) }
	timers.transition_remaining_ms = clamped_presentation_ms(timers.transition_remaining_ms - delta,
		menu_transition_duration_ms)
	if !title_mode && game_over {
		timers.game_over_elapsed_ms = clamped_presentation_ms(timers.game_over_elapsed_ms + delta,
			game_over_auto_return_ms)
	} else if !game_over {
		timers.game_over_elapsed_ms = 0
	}
	if !calibration_mode {
		timers.replay_change_ms = stepped_title_replay_transition(timers.replay_change_ms,
			replay_mode, delta)
	}
}

fn presentation_fade(transition_remaining_ms i64, game_over_elapsed_ms i64) f32 {
	transition := f32(clamped_presentation_ms(transition_remaining_ms, menu_transition_duration_ms)) / f32(menu_transition_duration_ms)
	game_over := f32(clamped_presentation_ms(game_over_elapsed_ms, game_over_fade_duration_ms)) / f32(game_over_fade_duration_ms) * game_over_fade_opacity
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

fn stepped_title_replay_transition(elapsed_ms i64, replay_mode bool, delta_ms i64) i64 {
	delta := if delta_ms > 0 { delta_ms } else { i64(0) }
	return clamped_presentation_ms(elapsed_ms + if replay_mode { delta } else { -delta },
		replay_transition_duration_ms)
}

fn title_replay_view_ratio(title_mode bool, has_replay bool, elapsed_ms i64) f32 {
	if !title_mode || !has_replay {
		return 1
	}
	return f32(clamped_presentation_ms(elapsed_ms, replay_transition_duration_ms)) / f32(replay_transition_duration_ms)
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
	restart_pressed bool, game_over_elapsed_ms i64) bool {
	return !title_mode && game_over
		&& (game_over_elapsed_ms >= game_over_auto_return_ms || (game_over_elapsed_ms >= game_over_restart_delay_ms && restart_down && !restart_pressed))
}

fn should_refresh_gameplay_status(paused bool, game_over bool, tick int) bool {
	return paused || game_over || tick % gameplay_status_interval_ticks == 0
}

fn replay_uses_cinematic_camera(replay_mode bool, attract_replay bool, cinematic_selected bool) bool {
	return if replay_mode { cinematic_selected } else { attract_replay }
}

fn title_replay_uses_gameplay_status(title_mode bool, replay_mode bool,
	replay_change_ms i64) bool {
	return title_mode && replay_mode && replay_change_ms == replay_transition_duration_ms
}

fn replay_input_ended(input_index int, input_count int) bool {
	return input_index >= input_count
}

fn should_restart_title_replay(game_over_ticks int) bool {
	return game_over_ticks > attract_replay_restart_delay_ticks
}

