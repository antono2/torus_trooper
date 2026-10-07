// Connects the deterministic simulation to the platform window, rendering, audio, and menus.
module runtime

import sim
import time

#flag linux -lglfw

#flag linux -lvulkan

#flag darwin -lglfw

#flag darwin -lvulkan

#flag windows -lglfw3

$if windows {
	#flag -I$env('GLFW_INCLUDE')
	#flag -L$env('GLFW_LIB')
	#flag -L$env('VULKAN_SDK')/Lib
	#flag -DGLFW_INCLUDE_VULKAN
	#flag -DGLFW_INCLUDE_NONE
}

#flag windows -lvulkan-1

#flag windows -lgdi32

#flag windows -lshell32

#include "vulkan_bridge.h"

@[typedef]
struct C.TTPlatform {}

fn C.tt_platform_take_replay_event(platform &C.TTPlatform) int
fn C.tt_platform_clipboard(platform &C.TTPlatform) &char
fn C.tt_platform_replay_overlay(platform &C.TTPlatform, open bool, editing bool, selected int)
fn C.tt_platform_replay_line(platform &C.TTPlatform, codes &u8, length int)

fn C.tt_platform_create(width int, height int, title &char, fullscreen int, sample_count int, fps_limit int) &C.TTPlatform

fn C.tt_platform_antialiasing_samples(platform &C.TTPlatform) int

fn C.tt_platform_antialiasing_supported(platform &C.TTPlatform, sample_count int) bool

fn C.tt_platform_set_antialiasing(platform &C.TTPlatform, sample_count int) int

fn C.tt_platform_set_fps_limit(platform &C.TTPlatform, fps_limit int) bool

fn C.tt_platform_reset_frame_timing(platform &C.TTPlatform)

fn C.tt_platform_set_near_camera_blur(platform &C.TTPlatform, strength f32)

fn C.tt_platform_set_near_camera_fade(platform &C.TTPlatform, strength f32)

fn C.tt_antialiasing_sample_count(requested_samples int, support u32) int

fn C.tt_platform_destroy(platform &C.TTPlatform)

fn C.tt_platform_poll(platform &C.TTPlatform) bool

fn C.tt_platform_should_close(platform &C.TTPlatform) bool

fn C.tt_platform_request_close(platform &C.TTPlatform)

fn C.tt_platform_device_count(platform &C.TTPlatform) int

fn C.tt_platform_device_name(platform &C.TTPlatform, index int) &char

fn C.tt_platform_device_api_version(platform &C.TTPlatform, index int) u32

fn C.tt_platform_device_driver_version(platform &C.TTPlatform, index int) u32

fn C.tt_platform_device_graphics_queue(platform &C.TTPlatform, index int) int

fn C.tt_platform_device_present_queue(platform &C.TTPlatform, index int) int

fn C.tt_platform_set_bullets(platform &C.TTPlatform, positions voidptr, count u32)

fn C.tt_platform_set_tunnel(platform &C.TTPlatform, vertices voidptr, count u32)

fn C.tt_platform_set_tunnel_fill(platform &C.TTPlatform, vertices voidptr, count u32)

fn C.tt_platform_set_ship_mesh(platform &C.TTPlatform, vertices voidptr, count u32)

fn C.tt_platform_set_ship_material_seed(platform &C.TTPlatform, seed u32)

fn C.tt_instance_uses_opacity(kind f32) bool

fn C.tt_platform_set_tunnel_color(platform &C.TTPlatform, r f32, g f32, b f32)

fn C.tt_platform_set_tunnel_scale(platform &C.TTPlatform, scale f32)

fn C.tt_platform_set_view_angle(platform &C.TTPlatform, angle f32)

fn C.tt_platform_set_camera(platform &C.TTPlatform, angle f32, depth_offset f32, zoom f32, shake_x f32, shake_y f32, use_3d bool, eye_height f32, look_angle f32, look_depth f32, look_height f32, rotation f32, ship_surface_radius f32, ship_render_depth f32)

fn C.tt_platform_set_hud_visible(platform &C.TTPlatform, visible bool)

fn C.tt_platform_set_mouse_capture(platform &C.TTPlatform, captured bool)

fn C.tt_platform_take_mouse_delta(platform &C.TTPlatform, x &f32, y &f32)

fn C.tt_platform_take_calibration_save(platform &C.TTPlatform) bool

fn C.tt_platform_take_calibration_reload(platform &C.TTPlatform) bool

fn C.tt_platform_take_calibration_reset(platform &C.TTPlatform) bool

fn C.tt_platform_take_calibration_auto_orbit(platform &C.TTPlatform) bool

fn C.tt_platform_take_calibration_cycle(platform &C.TTPlatform) int

fn C.tt_platform_set_window_title(platform &C.TTPlatform, title &char)

fn C.tt_platform_set_loading_progress(platform &C.TTPlatform, progress f32) bool

fn C.tt_platform_finish_loading(platform &C.TTPlatform)

fn C.tt_platform_set_transition(platform &C.TTPlatform, fade f32)

fn C.tt_platform_set_replay_view_ratio(platform &C.TTPlatform, ratio f32)

fn C.tt_platform_set_bindings(platform &C.TTPlatform, left &char, right &char, up &char, down &char, fire &char, charge &char, pause &char, restart &char, back &char, volume_down &char, volume_up &char, fullscreen &char, fps &char) bool

fn C.tt_platform_take_god_mode_toggle(platform &C.TTPlatform) bool

fn C.tt_key_from_name(name &char) int

fn C.tt_god_mode_sequence_step(index int, codepoint u32) int

fn C.tt_title_replay_viewport_fraction(ratio f32) f32

fn C.tt_title_replay_viewport_x_fraction(ratio f32) f32

fn C.tt_course_line_width_for_extent(height u32, wide_lines bool, max_line_width f32) f32

fn C.tt_pause_overlay_visible(wall_time f64) bool

fn is_runtime_ship_body(instance sim.RenderInstance) bool {
	return (instance.kind > 0.5 && instance.kind < 1.5)
		|| (instance.kind > 2.5 && instance.kind < 3.5)
}

fn uses_volumetric_ship_meshes(calibration_mode bool, world_visible bool) bool {
	// Hull geometry is already emitted in the active course/camera frame.  It is
	// therefore valid for the normal chase projection as well as the cinematic
	// camera; falling back to the instanced card here makes every ship lose its
	// side faces as soon as gameplay leaves a 3D replay.
	return calibration_mode || world_visible
}

fn keeps_instanced_ship_bodies(calibration_mode bool) bool {
	// Tuning keeps its labelled reference cards.  Every actual game view uses
	// the procedural hull mesh so switching cameras cannot change model volume.
	return calibration_mode
}

fn C.tt_platform_set_display(platform &C.TTPlatform, brightness f32, luminosity f32)

fn C.tt_platform_set_status(platform &C.TTPlatform, score int, remaining_time_ms int, hits int, zone int, speed int, rank int, rank_remaining int, next_extend_score int, time_change_ticks int, time_change_seconds int, game_over bool, paused bool, god_mode bool)

fn C.tt_platform_set_title_status(platform &C.TTPlatform, grade int, level int, max_level int, high_score int, high_score_start_level int, high_score_end_level int, has_replay bool, active_menu_item int, volume_percent int, help_page int, god_mode bool, settings_open bool, settings_item int, antialiasing_samples int, near_blur_percent int, near_fade_percent int, rear_track_blend_percent int, track_draw_distance int, wire_draw_distance int, border_draw_distance int, player_shot_distance int, fps_limit int)

fn C.tt_platform_set_title_grade_info(platform &C.TTPlatform, grade int, level int, max_level int, high_score int, high_score_start_level int, high_score_end_level int)

fn C.tt_platform_input(platform &C.TTPlatform) u32
fn C.tt_platform_controller_back_pressed(platform &C.TTPlatform) bool
fn C.tt_platform_controller_start_pressed(platform &C.TTPlatform) bool

fn C.tt_platform_set_paused(platform &C.TTPlatform, paused bool)

fn C.tt_platform_last_error() &char

fn C.tt_title_rank_remaining_value(hud_state int, settings_value int, extreme_high_score int) int

fn C.tt_target_frame_rate(fps_limit int, display_refresh_rate int) int

pub struct KeyBindings {
pub:
	left        string = 'left,a,kp_4,gamepad_left_stick_left,gamepad_dpad_left,joystick_axis_1_negative'
	right       string = 'right,d,kp_6,gamepad_left_stick_right,gamepad_dpad_right,joystick_axis_1_positive'
	up          string = 'up,w,kp_8,gamepad_left_stick_up,gamepad_dpad_up,joystick_axis_2_negative'
	down        string = 'down,s,kp_2,gamepad_left_stick_down,gamepad_dpad_down,joystick_axis_2_positive'
	fire        string = 'space,z,period,kp_decimal,left_control,gamepad_a,gamepad_y,gamepad_left_bumper,joystick_button_1,joystick_button_4,joystick_button_5'
	charge      string = 'left_shift,x,slash,left_alt,gamepad_b,gamepad_x,gamepad_right_bumper,gamepad_back,joystick_button_2,joystick_button_3,joystick_button_6,joystick_button_7'
	pause       string = 'p'
	restart     string = 'enter,r'
	back        string = 'escape,gamepad_start,joystick_button_8'
	volume_down string = 'minus,kp_subtract'
	volume_up   string = 'equal,kp_add'
	fullscreen  string = 'f11'
	fps         string = 'f'
}

pub struct AppConfig {
pub:
	title                    string = 'Torus Trooper'
	width                    int    = default_window_width
	height                   int    = default_window_height
	audio_asset_root         string = '.'
	audio_volume             f32    = default_volume
	audio_volume_explicit    bool
	antialiasing_samples     int = default_antialiasing_samples
	antialiasing_explicit    bool
	near_blur_percent        int = default_near_blur_percent
	near_blur_explicit       bool
	near_fade_percent        int = default_near_fade_percent
	near_fade_explicit       bool
	rear_track_blend_percent int = default_rear_track_blend_percent
	rear_track_explicit      bool
	track_draw_distance      int = default_track_draw_distance
	track_draw_explicit      bool
	wire_draw_distance       int = default_wire_draw_distance
	wire_draw_explicit       bool
	border_draw_distance     int = default_border_draw_distance
	border_draw_explicit     bool
	fps_limit                int = fps_limit_unlocked
	fps_limit_explicit       bool
	audio_enabled            bool        = true
	key_bindings             KeyBindings = KeyBindings{}
	brightness               f32         = default_brightness
	luminosity               f32         = default_luminosity
	grade                    sim.Grade
	starting_level           int = 1
	reverse_buttons          bool
	fullscreen               bool
	player_data_path         string
	object_sizes_path        string
	model_file_path          string
	persistence_enabled      bool = true
	selection_explicit       bool
	compute_backend          sim.ComputeBackend
	debug_view               sim.DebugViewOptions
}

pub struct DeviceInfo {
pub:
	name                  string
	api_version           u32
	driver_version        u32
	graphics_queue_family int
	present_queue_family  int
}

@[heap]
pub struct App {
mut:
	platform                 &C.TTPlatform = unsafe { nil }
	audio                    &Audio        = unsafe { nil }
	devices                  []DeviceInfo
	grade                    sim.Grade
	starting_level           int
	reverse_buttons          bool
	volume_percent           int
	audio_volume_explicit    bool
	player_data_path         string
	object_sizes_path        string
	model_file_path          string
	object_sizes             ObjectSizes
	persistence_enabled      bool
	selection_explicit       bool
	compute_backend          sim.ComputeBackend
	debug_view               sim.DebugViewOptions
	compute_session          &sim.ComputeSession = unsafe { nil }
	vulkan_memory            &VulkanMemory       = unsafe { nil }
	antialiasing_samples     int                 = 1
	near_blur_percent        int                 = default_near_blur_percent
	near_fade_percent        int                 = default_near_fade_percent
	rear_track_blend_percent int                 = default_rear_track_blend_percent
	track_draw_distance      int                 = default_track_draw_distance
	wire_draw_distance       int                 = default_wire_draw_distance
	border_draw_distance     int                 = default_border_draw_distance
	fps_limit                int                 = fps_limit_unlocked
	title_settings_open      bool
	title_settings_item      TitleSettingsItem
	god_mode                 bool
}

pub fn new_app(config AppConfig) !&App {
	initialize_vulkan_loader()!
	stored_data := if config.persistence_enabled && config.player_data_path.len > 0 {
		load_player_data(config.player_data_path)
	} else {
		default_player_data()
	}
	requested_samples := if !config.antialiasing_explicit && stored_data.antialiasing_samples > 0 {
		stored_data.antialiasing_samples
	} else {
		config.antialiasing_samples
	}
	requested_near_blur := if !config.near_blur_explicit && stored_data.near_blur_percent >= 0 {
		stored_data.near_blur_percent
	} else {
		config.near_blur_percent
	}
	requested_near_fade := if !config.near_fade_explicit && stored_data.near_fade_percent >= 0 {
		stored_data.near_fade_percent
	} else {
		config.near_fade_percent
	}
	requested_rear_track_blend := if !config.rear_track_explicit && stored_data.rear_track_blend >= 0 {
		stored_data.rear_track_blend
	} else {
		config.rear_track_blend_percent
	}
	requested_track_draw_distance := if !config.track_draw_explicit
		&& stored_data.track_draw_distance >= 0 {
		stored_data.track_draw_distance
	} else {
		config.track_draw_distance
	}
	requested_wire_draw_distance := if !config.wire_draw_explicit
		&& stored_data.wire_draw_distance >= 0 {
		stored_data.wire_draw_distance
	} else {
		config.wire_draw_distance
	}
	requested_border_draw_distance := if !config.border_draw_explicit
		&& stored_data.border_draw_distance >= 0 {
		stored_data.border_draw_distance
	} else {
		config.border_draw_distance
	}
	requested_fps_limit := if !config.fps_limit_explicit && stored_data.fps_limit >= fps_limit_display {
		stored_data.fps_limit
	} else {
		config.fps_limit
	}
	platform := C.tt_platform_create(config.width, config.height, config.title.str, int(config.fullscreen), requested_samples, normalized_fps_limit(requested_fps_limit))
	if isnil(platform) {
		message := unsafe { C.tt_platform_last_error().vstring() }
		return error(message)
	}
	bindings := config.key_bindings
	if !C.tt_platform_set_bindings(platform, bindings.left.str, bindings.right.str, bindings.up.str, bindings.down.str, bindings.fire.str, bindings.charge.str, bindings.pause.str, bindings.restart.str, bindings.back.str, bindings.volume_down.str, bindings.volume_up.str, bindings.fullscreen.str, bindings.fps.str) {
		message := unsafe { C.tt_platform_last_error().vstring() }
		C.tt_platform_destroy(platform)
		return error(message)
	}
	if !C.tt_platform_set_loading_progress(platform, 0.94) {
		message := unsafe { C.tt_platform_last_error().vstring() }
		C.tt_platform_destroy(platform)
		return error(message)
	}
	mut vulkan_memory := new_vulkan_memory(platform) or {
		C.tt_platform_destroy(platform)
		return error('Vulkan memory setup failed: ${err}')
	}
	if !C.tt_platform_set_loading_progress(platform, 0.97) {
		message := unsafe { C.tt_platform_last_error().vstring() }
		vulkan_memory.destroy()
		C.tt_platform_destroy(platform)
		return error(message)
	}
	compute_session := sim.new_compute_session(config.compute_backend)
	object_sizes := load_object_sizes(config.object_sizes_path)
	mut app := &App{
		platform:                 platform
		grade:                    config.grade
		starting_level:           config.starting_level
		reverse_buttons:          config.reverse_buttons
		volume_percent:           volume_percent_from_level(config.audio_volume)
		audio_volume_explicit:    config.audio_volume_explicit
		player_data_path:         config.player_data_path
		object_sizes_path:        config.object_sizes_path
		model_file_path:          config.model_file_path
		object_sizes:             object_sizes
		persistence_enabled:      config.persistence_enabled
		selection_explicit:       config.selection_explicit
		compute_backend:          config.compute_backend
		debug_view:               config.debug_view
		compute_session:          compute_session
		vulkan_memory:            vulkan_memory
		antialiasing_samples:     C.tt_platform_antialiasing_samples(platform)
		near_blur_percent:        int_min(int_max(requested_near_blur, 0), 100)
		near_fade_percent:        int_min(int_max(requested_near_fade, 0), 100)
		rear_track_blend_percent: normalized_rear_track_blend_percent(requested_rear_track_blend)
		track_draw_distance:      normalized_track_draw_distance(requested_track_draw_distance)
		wire_draw_distance:       normalized_track_draw_distance(requested_wire_draw_distance)
		border_draw_distance:     normalized_track_draw_distance(requested_border_draw_distance)
		fps_limit:                normalized_fps_limit(requested_fps_limit)
	}
	C.tt_platform_set_near_camera_blur(platform, f32(app.near_blur_percent) / 100.0)
	C.tt_platform_set_near_camera_fade(platform, f32(app.near_fade_percent) / 100.0)
	if !C.tt_platform_set_loading_progress(platform, 0.98) {
		message := unsafe { C.tt_platform_last_error().vstring() }
		app.shutdown()
		return error(message)
	}
	// Audio owns an OS device, so it is deliberately created only after the
	// window/platform and is allowed to fail independently of the game.
	if config.audio_enabled {
		app.audio = new_audio(AudioConfig{ asset_root: config.audio_asset_root }) or {
			eprintln('audio disabled: ${err}')
			unsafe { nil }
		}
	}
	if !isnil(app.audio) {
		app.audio.set_volume(app.volume_level())
	}
	if !C.tt_platform_set_loading_progress(platform, 0.99) {
		message := unsafe { C.tt_platform_last_error().vstring() }
		app.shutdown()
		return error(message)
	}
	C.tt_platform_set_display(platform, config.brightness, config.luminosity)
	for index in 0 .. C.tt_platform_device_count(platform) {
		app.devices << DeviceInfo{
			name:                  unsafe { C.tt_platform_device_name(platform, index).vstring() }
			api_version:           C.tt_platform_device_api_version(platform, index)
			driver_version:        C.tt_platform_device_driver_version(platform, index)
			graphics_queue_family: C.tt_platform_device_graphics_queue(platform, index)
			present_queue_family:  C.tt_platform_device_present_queue(platform, index)
		}
	}
	return app
}

pub fn (app &App) print_diagnostics() {
	println('GLFW: Vulkan surface creation succeeded')
	println('Compute requested: ${app.compute_backend.name()}')
	active := app.compute_session.active_backend()
	println('Compute active: ${active.name()}${if app.compute_backend != active {
		' (fallback)'
	} else {
		''
	}}')
	if active == .opencl {
		println('OpenCL device: ${app.compute_session.device()}')
	} else if app.compute_backend == .opencl && app.compute_session.fallback().len > 0 {
		println('OpenCL fallback: ${app.compute_session.fallback()}')
	}
	for index, device in app.devices {
		println('GPU ${index}: ${device.name}')
		println('  Vulkan API: ${version_major(device.api_version)}.${version_minor(device.api_version)}.${version_patch(device.api_version)}')
		println('  driver: ${device.driver_version}')
		println('  graphics queue: ${device.graphics_queue_family}')
		println('  present queue: ${device.present_queue_family}')
	}
	println('Vulkan anti-aliasing: ${app.antialiasing_samples}x MSAA')
	println('Near-camera blur: ${app.near_blur_percent}%')
	println('Near-camera fade: ${app.near_fade_percent}%')
	println('Rear track blend: ${app.rear_track_blend_percent}%')
	println('Track draw distance: ${app.track_draw_distance} panels')
	println('Wire draw distance: ${app.wire_draw_distance} slices')
	println('Border draw distance: ${app.border_draw_distance} slices')
	println('FPS limit: ${fps_limit_label(app.fps_limit)}')
	if !isnil(app.vulkan_memory) {
		stats := app.vulkan_memory.stats()
		println('Vulkan allocator: blocks=${stats.block_count} allocations=${stats.allocation_count} committed=${stats.committed} used=${stats.used}')
	}
}

pub fn (mut app App) run(test_effects bool, test_object_tuning bool, direct_tuning bool) {
	app.print_diagnostics()
	println('Renderer bootstrap complete. Press Escape or close the window to exit.')
	if test_object_tuning || direct_tuning {
		app.god_mode = true
	}
	mut player_data := if app.persistence_enabled && app.player_data_path.len > 0 {
		load_player_data(app.player_data_path)
	} else {
		default_player_data()
	}
	if !app.audio_volume_explicit && player_data.volume_percent >= 0 {
		app.volume_percent = player_data.volume_percent
		if !isnil(app.audio) {
			app.audio.set_volume(app.volume_level())
		}
	}
	mut run_seed_source := sim.new_mt19937(u32(time.now().unix_nano()))
	if !app.selection_explicit {
		app.grade = unsafe { sim.Grade(player_data.selected_grade) }
		app.starting_level = player_data.selected_level
	}
	player_data.reached_levels[int(app.grade)] = int_max(player_data.reached_levels[int(app.grade)], app.starting_level)
	mut simulation_config := with_compute_backend(gameplay_config(app.grade, app.starting_level), app.compute_backend)
	mut simulation := app.new_simulation(simulation_config)
	mut music_sequence := MusicSequence{}
	mut previous_music_track := -1
	mut title_mode := !test_effects && !test_object_tuning && !direct_tuning
	mut calibration_mode := test_object_tuning || direct_tuning
	mut replay_mode := false
	mut replay_camera_enabled := false
	mut replay_hud_visible := true
	mut replay_camera := sim.new_replay_camera(u32(simulation.config.random_seed))
	mut replay_camera_toggle_pressed := false
	mut recorded_inputs := []u8{}
	mut suspended_run := SuspendedRun{}
	mut last_replay := if player_data.replay.valid {
		player_data.latest_replay()
	} else {
		sim.Replay{}
	}
	mut attract_replay := title_mode && last_replay.inputs.len > 0
	if attract_replay {
		simulation_config = with_compute_backend(replay_gameplay_config_with_seed(last_replay.grade, last_replay.starting_level, last_replay.random_seed), app.compute_backend)
		simulation = app.new_replay_simulation(last_replay)
		replay_camera = sim.new_replay_camera(u32(last_replay.random_seed))
	}
	// Title inputs already held while the window opens
	// must be released before they can change selection or start a run.
	mut direction_pressed := true
	mut title_key_repeat := 0
	mut settings_adjust_pending := 0
	mut action_pressed := true
	mut presentation_timers := PresentationTimers{}
	mut replay_game_over_ticks := 0
	mut result_recorded := false
	mut title_start_levels := [1, 1, 1]
	title_start_levels[int(app.grade)] = int_min(app.starting_level, title_max_level(player_data, app.grade, app.god_mode))
	mut title_menu_item := title_menu_item_for_grade(app.grade)
	mut title_help_page := 0
	mut replay_library := ReplayLibrary{}
	mut replay_controls_blocked := false
	mut replay_from_library := false
	if title_mode {
		app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
	}
	// Player data and the initial procedural course are part of startup too. Keep
	// the loading presentation visible until both are resident instead of
	// exposing their cost as a misleadingly low first gameplay FPS sample.
	C.tt_platform_finish_loading(app.platform)
	step_seconds := f64(1.0 / sim.ticks_per_second)
	mut previous := time.ticks()
	mut presentation_previous_ms := presentation_time_ms()
	mut accumulator := f64(0)
	mut paused := false
	mut pause_pressed := false
	mut restart_pressed := false
	mut escape_pressed := false
	mut volume_hotkey_pressed := false
	mut title_volume_preview := TitleVolumePreview{}
	mut calibration_camera := new_calibration_camera()
	mut calibration_scene := new_calibration_scene()
	mut calibration_models := new_live_model_file(app.model_file_path)
	mut calibration_resize_pressed := false
	mut calibration_dirty := false
	mut calibration_notice := ''
	mut calibration_auto_orbit := false
	mut tuning_test_frames := 0
	if calibration_mode {
		calibration_models.reload(true)
		C.tt_platform_set_hud_visible(app.platform, false)
		if direct_tuning {
			C.tt_platform_set_mouse_capture(app.platform, true)
		}
		println('TUNE opened. Tab selects; mouse/A/D orbit; Space toggles auto-orbit; W/S zoom; +/- resizes; Backspace resets; Ctrl+S saves; Ctrl+R reloads; Escape returns.')
	}
	if !title_mode && !calibration_mode && !isnil(app.audio) {
		music_sequence = new_music_sequence(simulation.config.random_seed, 4, previous_music_track)
		previous_music_track = music_sequence.track
		app.audio.play_music(music_sequence.track)
		C.tt_platform_reset_frame_timing(app.platform)
		previous = time.ticks()
		presentation_previous_ms = presentation_time_ms()
	}
	if test_effects {
		println('Effect test enabled: automatic events run from 2 to 13 seconds.')
	}
	for !C.tt_platform_should_close(app.platform) {
		// Advance existing UI state before input can start a new transition. A
		// slow previous frame must not consume a fade that has only just begun.
		// Simulation catch-up is capped separately below; UI uses real time.
		presentation_now_ms := presentation_time_ms()
		presentation_timers.advance(presentation_now_ms - presentation_previous_ms, title_mode,
			simulation.game_over, replay_mode, calibration_mode)
		presentation_previous_ms = presentation_now_ms
		mut input_mask := C.tt_platform_input(app.platform)
		input_mask = controller_menu_input_mask(input_mask, title_mode,
			app.title_settings_open || title_menu_item == .help || replay_library.open || replay_mode,
			suspended_run.valid, C.tt_platform_controller_back_pressed(app.platform),
			C.tt_platform_controller_start_pressed(app.platform))
		if replay_controls_blocked {
			if input_mask & input_gameplay_and_menu_bits == 0 {
				replay_controls_blocked = false
			}
			input_mask = 0
		}
		if replay_library.open {
			chosen := app.take_replay_library_choice(mut replay_library, mut player_data)
			if chosen >= 0 {
				last_replay = player_data.replays[chosen].simulation_replay()
				simulation_config = with_compute_backend(replay_gameplay_config_with_seed(last_replay.grade, last_replay.starting_level, last_replay.random_seed), app.compute_backend)
				simulation = app.new_replay_simulation(last_replay)
				replay_camera = sim.new_replay_camera(u32(last_replay.random_seed))
				replay_game_over_ticks = 0
				accumulator = 0
				replay_mode = true
				replay_from_library = true
				attract_replay = true
				replay_camera_enabled = false
				replay_hud_visible = true
				presentation_timers.replay_change_ms = 0
				C.tt_platform_set_hud_visible(app.platform, true)
			}
			if chosen != -1 {
				replay_controls_blocked = true
				C.tt_platform_replay_overlay(app.platform, false, false, -1)
				if chosen == -2 {
					app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
				}
			}
			input_mask = 0
			direction_pressed = true
			action_pressed = true
			escape_pressed = true
		}
		if C.tt_platform_take_god_mode_toggle(app.platform) {
			app.god_mode = !app.god_mode
			simulation.god_mode = app.god_mode
			println('Godmode: ${if app.god_mode { 'enabled' } else { 'disabled' }}.')
			if calibration_mode && !app.god_mode {
				calibration_mode = false
				title_mode = true
				title_menu_item = .help
				C.tt_platform_set_mouse_capture(app.platform, false)
				C.tt_platform_set_hud_visible(app.platform, true)
			}
			if title_mode {
				if !app.god_mode {
					if title_menu_item == .tune {
						title_menu_item = .help
					}
					for grade in 0 .. title_start_levels.len {
						title_start_levels[grade] = int_min(title_start_levels[grade], player_data.reached_levels[grade])
					}
				}
				app.starting_level = title_start_levels[int(app.grade)]
				app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
			} else {
				app.set_gameplay_status(simulation, paused)
			}
		}
		// HELP and SETTINGS own title controls. Mask the replay/charge button
		// before applying the
		// optional fire/charge reversal so Shift cannot become either title
		// action while the help overlay is selected.
		title_overlay_selected := title_mode
			&& (title_menu_item == .help || app.title_settings_open || replay_library.open)
		menu_input_mask := title_menu_input_mask(input_mask, title_mode, title_menu_item)
		menu_input := input_state(menu_input_mask, app.reverse_buttons, false)
		start_down := menu_input.fire || input_mask & input_restart_bit != 0
		replay_down := menu_input.brake
		action_down := start_down || replay_down
		direction_down := menu_input.left || menu_input.right || menu_input.up || menu_input.down
		if title_mode && !replay_library.open {
			mut settings_adjust_released := 0
			continuous_setting := app.title_settings_open
				&& title_setting_repeats(app.title_settings_item)
			if app.title_settings_open && !continuous_setting {
				settings_adjust_released, settings_adjust_pending = settings_adjustment_on_release(settings_adjust_pending, menu_input.left, menu_input.right)
			} else {
				settings_adjust_pending = 0
			}
			settings_adjust_requested := if continuous_setting {
				menu_input.left != menu_input.right
			} else {
				settings_adjust_released != 0
			}
			horizontal_menu_activation := !app.title_settings_open && !replay_mode
				&& !direction_pressed && (menu_input.left || menu_input.right)
				&& title_menu_accepts_horizontal_activation(title_menu_item)
			settings_back_activation := app.title_settings_open
				&& app.title_settings_item == .back && !direction_pressed
				&& (menu_input.left || menu_input.right)
			primary_menu_activation := start_down && !action_pressed
			menu_item_activation := primary_menu_activation || horizontal_menu_activation
			settings_back_selected := primary_menu_activation || settings_back_activation
			// Keep the help overlay authoritative even if a replay transition was
			// already pending when selection moved onto HELP.
			if title_overlay_selected && replay_mode {
				replay_mode = false
				presentation_timers.replay_change_ms = 0
				C.tt_platform_set_hud_visible(app.platform, true)
				app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
			}
			mut selection_changed := false
			if app.title_settings_open && (menu_input.up || menu_input.down)
				&& !direction_pressed {
				settings_adjust_pending = 0
				app.title_settings_item = cycled_title_settings_item(app.title_settings_item, if menu_input.up {
					-1
				} else {
					1
				})
				selection_changed = true
			} else if app.title_settings_open && settings_adjust_requested {
				mut movement := 1
				mut direction := settings_adjust_released
				if continuous_setting {
					movement = title_repeat_movement(direction_pressed, title_key_repeat)
					if direction_pressed {
						title_key_repeat++
					}
					direction = if menu_input.left { -1 } else { 1 }
				}
				if movement > 0 {
					if app.adjust_title_setting(direction, movement, mut player_data)
						&& !isnil(app.audio) && title_volume_preview.arm(time.ticks()) {
						music_sequence = new_music_sequence(simulation.config.random_seed, 4, previous_music_track)
						previous_music_track = music_sequence.track
						app.audio.play_music(music_sequence.track)
					}
					selection_changed = true
				}
			} else if !app.title_settings_open && !replay_mode
				&& (menu_input.up || menu_input.down) && !direction_pressed {
				title_menu_item = cycled_title_menu_item(title_menu_item, if menu_input.up {
					-1
				} else {
					1
				}, app.god_mode)
				if grade := title_menu_grade(title_menu_item) {
					app.grade = grade
					app.starting_level = title_start_levels[int(grade)]
				}
				selection_changed = true
			} else if !app.title_settings_open && !replay_mode
				&& (menu_input.left || menu_input.right) {
				movement := title_repeat_movement(direction_pressed, title_key_repeat)
				if direction_pressed {
					title_key_repeat++
				}
				if movement > 0 {
					direction := if menu_input.left { -1 } else { 1 }
					if grade := title_menu_grade(title_menu_item) {
						grade_index := int(grade)
						max_level := title_max_level(player_data, app.grade, app.god_mode)
						title_start_levels[grade_index] = title_moved_level(title_start_levels[grade_index], max_level, direction * movement, title_key_repeat >= 30)
						app.starting_level = title_start_levels[grade_index]
					} else {
						match title_menu_item {
							.help {
								title_help_page = cycled_help_page(title_help_page, direction * movement)
							}
							else {}
						}
					}
					selection_changed = title_menu_grade(title_menu_item) != none
						|| title_menu_item == .help
				}
			}
			if selection_changed {
				app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
			}
			if app.title_settings_open && settings_back_selected
				&& app.title_settings_item == .back {
				app.title_settings_open = false
				app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
			} else if !app.title_settings_open && !replay_mode
				&& title_menu_item == .settings
				&& menu_item_activation {
				app.title_settings_open = true
				app.title_settings_item = .volume
				replay_mode = false
				presentation_timers.replay_change_ms = 0
				C.tt_platform_set_hud_visible(app.platform, true)
				app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
			} else if !app.title_settings_open && !replay_mode && title_menu_item == .replays
				&& menu_item_activation {
				replay_library.open = true
				replay_library.mode = .list
				replay_mode = false
				C.tt_platform_set_hud_visible(app.platform, true)
			} else if !app.title_settings_open && !replay_mode && title_menu_item == .exit
				&& menu_item_activation {
				C.tt_platform_request_close(app.platform)
			} else if !app.title_settings_open && !replay_mode && title_menu_item == .tune
				&& app.god_mode
				&& menu_item_activation {
				title_volume_preview.cancel()
				calibration_mode = true
				title_mode = false
				replay_mode = false
				attract_replay = false
				calibration_camera = new_calibration_camera()
				calibration_scene = new_calibration_scene()
				calibration_models.reload(true)
				C.tt_platform_set_mouse_capture(app.platform, true)
				C.tt_platform_set_hud_visible(app.platform, false)
				if !isnil(app.audio) {
					app.audio.halt_music()
				}
				println('Object tuning scene opened. Tab changes focus, A/D and mouse orbit, W/S zoom, +/- resizes, Ctrl+S saves, Escape returns.')
			} else if !app.title_settings_open && !replay_mode
				&& title_menu_item !in [.settings, .help, .tune, .replays, .exit] && start_down && !action_pressed {
				title_volume_preview.cancel()
				app.finish_suspended_run(suspended_run, mut player_data)
				suspended_run = SuspendedRun{}
				player_data.record_start(app.grade, app.starting_level)
				app.save_player_data_if_enabled(player_data)
				simulation_config = with_compute_backend(gameplay_config_with_seed(app.grade, app.starting_level, next_game_seed(mut run_seed_source)), app.compute_backend)
				simulation = app.new_simulation(simulation_config)
				title_mode = false
				presentation_timers.transition_remaining_ms = menu_transition_duration_ms
				replay_controls_blocked = C.tt_platform_controller_start_pressed(app.platform)
				replay_mode = false
				attract_replay = false
				presentation_timers.replay_change_ms = 0
				recorded_inputs.clear()
				replay_game_over_ticks = 0
				result_recorded = false
				accumulator = 0
				if !isnil(app.audio) {
					music_sequence = new_music_sequence(simulation.config.random_seed, 4, previous_music_track)
					previous_music_track = music_sequence.track
					app.audio.play_music(music_sequence.track)
				}
				// Exclude all synchronous run setup (including a first music start on
				// slow removable storage) from both simulation elapsed time and FPS.
				C.tt_platform_reset_frame_timing(app.platform)
				previous = time.ticks()
				presentation_previous_ms = presentation_time_ms()
				println('Run started: ${sim.rules_for_grade(app.grade).name}, level ${app.starting_level}.')
			}
			if !app.title_settings_open && replay_down && !action_pressed
				&& title_replay_toggle_allowed(title_menu_item, last_replay.inputs.len > 0) {
				view := toggled_title_replay(replay_mode, true)
				replay_mode = view.replay_mode
				attract_replay = view.attract_replay
				C.tt_platform_set_hud_visible(app.platform, false)
				if replay_mode {
					replay_camera_enabled = false
					replay_hud_visible = true
					println('Replay view shown.')
				} else {
					println('Replay view hidden; title selection shown.')
				}
			}
		}
		volume_down := input_mask & input_volume_down_bit != 0
		volume_up := input_mask & input_volume_up_bit != 0
		volume_hotkey_down := volume_down || volume_up
		if !title_mode && !calibration_mode && volume_hotkey_down && !volume_hotkey_pressed
			&& volume_down != volume_up {
			app.apply_volume(stepped_volume_percent(app.volume_percent, if volume_down {
				-1
			} else {
				1
			}), mut player_data)
			println('Volume: ${app.volume_percent}%.')
		}
		volume_hotkey_pressed = volume_hotkey_down
		if replay_mode {
			camera_toggle_down := menu_input.left || menu_input.right
			hud_toggle_down := menu_input.up || menu_input.down
			if camera_toggle_down && !replay_camera_toggle_pressed {
				replay_camera_enabled = menu_input.left
				println(if replay_camera_enabled {
					'Replay camera: cinematic.'
				} else {
					'Replay camera: ship-follow.'
				})
			}
			if hud_toggle_down && !replay_camera_toggle_pressed {
				replay_hud_visible = menu_input.up
				C.tt_platform_set_hud_visible(app.platform, replay_hud_visible)
				println(if replay_hud_visible {
					'Replay HUD: shown.'
				} else {
					'Replay HUD: hidden.'
				})
			}
			replay_camera_toggle_pressed = camera_toggle_down || hud_toggle_down
		} else {
			replay_camera_toggle_pressed = false
		}
		if !direction_down {
			title_key_repeat = 0
		}
		direction_pressed = direction_down
		action_pressed = action_down
		pause_down := input_mask & input_pause_bit != 0
		if !title_mode && !calibration_mode && pause_down && !pause_pressed && !simulation.game_over {
			paused = !paused
			C.tt_platform_set_paused(app.platform, paused)
			app.set_gameplay_status(simulation, paused)
			if !isnil(app.audio) {
				app.audio.set_paused(paused)
			}
		}
		pause_pressed = pause_down
		restart_down := input_mask & input_restart_bit != 0
		escape_down := input_mask & input_back_bit != 0
		escape_edge := escape_down && !escape_pressed
		mut resumed_run := false
		if calibration_mode && escape_edge {
			calibration_mode = false
			title_mode = true
			title_menu_item = .tune
			direction_pressed = true
			action_pressed = true
			C.tt_platform_set_mouse_capture(app.platform, false)
			C.tt_platform_set_hud_visible(app.platform, true)
			app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
			println('Returned to title selection.')
		} else if title_mode && escape_edge {
			if app.title_settings_open {
				app.title_settings_open = false
				app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
				println('Settings closed.')
			} else if title_menu_item == .help {
				title_menu_item = title_menu_item_for_grade(app.grade)
				app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
				println('Help closed.')
			} else if replay_mode {
				title_menu_item = title_menu_item_for_grade(app.grade)
				view := toggled_title_replay(replay_mode, last_replay.inputs.len > 0)
				replay_mode = view.replay_mode
				attract_replay = view.attract_replay
				C.tt_platform_set_hud_visible(app.platform, false)
				if replay_from_library {
					replay_library.open = true
					replay_library.mode = .list
					title_menu_item = .replays
					replay_controls_blocked = true
					replay_from_library = false
				}
			} else if suspended_run.valid {
				title_volume_preview.cancel()
				simulation = sim.Simulation{ ...suspended_run.simulation }
				simulation_config = simulation.config
				recorded_inputs = suspended_run.inputs.clone()
				app.grade = suspended_run.grade
				app.starting_level = suspended_run.starting_level
				paused = suspended_run.paused
				music_sequence = suspended_run.music
				previous_music_track = music_sequence.track
				suspended_run = SuspendedRun{}
				title_mode = false
				replay_mode = false
				attract_replay = false
				result_recorded = false
				accumulator = 0
				presentation_timers.transition_remaining_ms = menu_transition_duration_ms
				replay_controls_blocked = true
				input_mask = 0
				C.tt_platform_set_paused(app.platform, paused)
				C.tt_platform_set_hud_visible(app.platform, true)
				app.set_gameplay_status(simulation, paused)
				if !isnil(app.audio) {
					app.audio.play_music(music_sequence.track)
					app.audio.set_paused(paused)
				}
				C.tt_platform_reset_frame_timing(app.platform)
				previous = time.ticks()
				presentation_previous_ms = presentation_time_ms()
				resumed_run = true
				println('Run resumed: ticks=${simulation.tick} score=${simulation.score} checksum=${simulation.checksum():016x}')
			} else {
				C.tt_platform_request_close(app.platform)
			}
		}
		returning_from_game_over := should_return_to_title(title_mode, simulation.game_over, restart_down, restart_pressed, presentation_timers.game_over_elapsed_ms)
		if returning_from_game_over || (!title_mode && !calibration_mode && escape_edge && !resumed_run) {
			title_volume_preview.cancel()
			suspending_run := !simulation.game_over
			if suspending_run {
				suspended_run = suspend_run(&simulation, recorded_inputs, app.grade, app.starting_level, paused, music_sequence)
				println('Run suspended: ticks=${simulation.tick} score=${simulation.score} checksum=${simulation.checksum():016x}')
			}
			last_replay = replay_for_title_return(last_replay, app.grade, app.starting_level, &simulation, recorded_inputs)
			if !suspending_run && !result_recorded && recorded_inputs.len > 0 {
				player_data.record_result(app.grade, app.starting_level, int(simulation.level), simulation.score, last_replay)
				app.save_player_data_if_enabled(player_data)
			}
			title_mode = true
			presentation_timers.transition_remaining_ms = menu_transition_duration_ms
			presentation_timers.game_over_elapsed_ms = 0
			accumulator = 0
			paused = false
			C.tt_platform_set_paused(app.platform, false)
			replay_mode = false
			attract_replay = last_replay.inputs.len > 0
			presentation_timers.replay_change_ms = 0
			if attract_replay {
				simulation_config = with_compute_backend(replay_gameplay_config_with_seed(last_replay.grade, last_replay.starting_level, last_replay.random_seed), app.compute_backend)
				simulation = app.new_replay_simulation(last_replay)
				replay_camera = sim.new_replay_camera(u32(last_replay.random_seed))
				replay_game_over_ticks = 0
			}
			C.tt_platform_set_hud_visible(app.platform, true)
			title_menu_item = title_menu_item_for_grade(app.grade)
			title_start_levels[int(app.grade)] = int_min(app.starting_level, title_max_level(player_data, app.grade, app.god_mode))
			app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
			if !isnil(app.audio) {
				app.audio.set_paused(false)
				app.audio.halt_music()
			}
			println('Returned to title selection.')
		}
		restart_pressed = restart_down
		escape_pressed = escape_down
		live_input := input_state(input_mask, app.reverse_buttons, test_effects
			&& simulation.tick >= 120 && simulation.tick < 240)
		now := time.ticks()
		if title_mode && title_volume_preview.take_expired(now) && !isnil(app.audio) {
			app.audio.halt_music()
		}
		mut elapsed := f64(now - previous) / 1000.0
		previous = now
		if elapsed > 0.25 {
			elapsed = 0.25
		}
		if calibration_mode {
			calibration_models.poll(now)
			mut mouse_dx := f32(0)
			mut mouse_dy := f32(0)
			C.tt_platform_take_mouse_delta(app.platform, &mouse_dx, &mouse_dy)
			if C.tt_platform_take_calibration_auto_orbit(app.platform) {
				calibration_auto_orbit = !calibration_auto_orbit
			}
			if calibration_auto_orbit {
				calibration_camera.yaw += f32(elapsed) * 0.45
			}
			cycle_step := C.tt_platform_take_calibration_cycle(app.platform)
			if cycle_step != 0 {
				selected := calibration_scene.cycle(cycle_step)
				calibration_camera.focus_on(calibration_object_position(selected), calibration_object_view_distance(selected))
			}
			calibration_camera.update(live_input, mouse_dx, mouse_dy, f32(elapsed))
			selected := calibration_scene.select(calibration_camera)
			if selected >= 0 && volume_hotkey_down && !calibration_resize_pressed
				&& volume_down != volume_up {
				kind := object_size_kind(selected)
				direction := if volume_down {
					-calibration_resize_step
				} else {
					calibration_resize_step
				}
				app.object_sizes.set(kind, app.object_sizes.get(kind) + direction)
				calibration_dirty = true
				calibration_notice = 'UNSAVED'
			}
			calibration_resize_pressed = volume_hotkey_down
			if C.tt_platform_take_calibration_reset(app.platform) && selected >= 0 {
				kind := object_size_kind(selected)
				app.object_sizes.set(kind, default_object_sizes().get(kind))
				calibration_dirty = true
				calibration_notice = 'RESET SELECTED - UNSAVED'
			}
			if C.tt_platform_take_calibration_reload(app.platform) {
				calibration_models.reload(true)
				mut reload_ok := true
				app.object_sizes = load_object_sizes_checked(app.object_sizes_path) or {
					reload_ok = false
					calibration_notice = 'RELOAD FAILED - SEE TERMINAL'
					eprintln('could not reload object sizes from ${app.object_sizes_path}: ${err}')
					app.object_sizes
				}
				if reload_ok {
					calibration_dirty = false
					calibration_notice = 'RELOADED'
					println('Object sizes reloaded from ${app.object_sizes_path}.')
				}
			}
			if C.tt_platform_take_calibration_save(app.platform) {
				mut save_ok := true
				save_object_sizes(app.object_sizes_path, app.object_sizes) or {
					save_ok = false
					calibration_notice = 'SAVE FAILED - SEE TERMINAL'
					eprintln('could not save object sizes: ${err}')
				}
				if save_ok {
					calibration_dirty = false
					calibration_notice = 'SAVED'
					println('Object sizes saved to ${app.object_sizes_path}.')
				}
			}
			selection_status := if selected >= 0 {
				kind := object_size_kind(selected)
				'${object_size_label(kind)} ${app.object_sizes.get(kind):.2f}x'
			} else {
				'NO OBJECT'
			}
			model_status := if selected in [0, 4, 5, 6] {
				model := calibration_models.catalog.for_kind(if selected == 0 {
					-1
				} else {
					selected - 4
				})
				if model.enabled { 'CUSTOM ${model.parts.len} PARTS' } else { 'BUILT-IN HULL' }
			} else {
				''
			}
			file_status := if calibration_dirty { 'UNSAVED' } else { 'ON DISK' }
			orbit_status := if calibration_auto_orbit { 'AUTO ORBIT' } else { 'ORBIT OFF' }
			calibration_title := 'TUNE | ${selection_status} ${model_status} | ${calibration_models.status} | ${file_status} ${calibration_notice} | ${orbit_status} | Tab select | mouse/A/D orbit | Space auto | W/S zoom | +/- scale | Backspace reset | Ctrl+S save | Ctrl+R reload | Esc back'
			C.tt_platform_set_window_title(app.platform, calibration_title.str)
		} else {
			calibration_resize_pressed = false
		}
		if should_advance_simulation(title_mode || calibration_mode, replay_mode, attract_replay, paused) {
			accumulator += elapsed
		}
		for should_advance_simulation(title_mode || calibration_mode, replay_mode, attract_replay, paused)
			&& accumulator >= step_seconds {
			is_title_replay := replay_mode || attract_replay
			if is_title_replay && simulation.game_over {
				replay_game_over_ticks++
				if should_restart_title_replay(replay_game_over_ticks) {
					simulation_config = with_compute_backend(replay_gameplay_config_with_seed(last_replay.grade, last_replay.starting_level, last_replay.random_seed), app.compute_backend)
					simulation = app.new_replay_simulation(last_replay)
					replay_camera = sim.new_replay_camera(u32(last_replay.random_seed))
					replay_game_over_ticks = 0
					println('Title replay restarted.')
				}
			}
			if is_title_replay && replay_input_ended(simulation.tick, last_replay.inputs.len)
				&& !simulation.game_over {
				simulation.game_over = true
			}
			input := if is_title_replay {
				if simulation.tick < last_replay.inputs.len {
					sim.decode_input(last_replay.inputs[simulation.tick])
				} else {
					sim.InputState{}
				}
			} else {
				live_input
			}
			if !is_title_replay {
				recorded_inputs << sim.encode_input(input)
			}
			if test_effects && !is_title_replay {
				inject_test_event(mut simulation)
			}
			previous_audio_state := capture_audio_state(&simulation)
			simulation.update_with_input(input)
			if !replay_mode && !attract_replay && simulation.game_over && !result_recorded
				&& recorded_inputs.len > 0 {
				last_replay = completed_run_replay(app.grade, app.starting_level, &simulation, recorded_inputs)
				player_data.record_result(app.grade, app.starting_level, int(simulation.level), simulation.score, last_replay)
				app.starting_level = int(simulation.level)
				app.save_player_data_if_enabled(player_data)
				result_recorded = true
			}
			if replay_mode || attract_replay {
				replay_camera.update(simulation.ship)
			}
			if should_play_simulation_audio(title_mode, replay_mode, attract_replay) {
				app.play_simulation_audio(previous_audio_state, &simulation, mut music_sequence)
				previous_music_track = music_sequence.track
			}
			accumulator -= step_seconds
		}
		world_visible := calibration_mode
			|| should_render_world(title_mode, replay_mode, attract_replay, title_menu_item == .help || app.title_settings_open || replay_library.open)
		mut presentation_fraction := if should_advance_simulation(title_mode || calibration_mode, replay_mode, attract_replay, paused) {
			f32(accumulator / step_seconds)
		} else {
			f32(0)
		}
		if presentation_fraction < 0 {
			presentation_fraction = 0
		} else if presentation_fraction > 1 {
			presentation_fraction = 1
		}
		// Keep gameplay deterministic at 60 Hz while allowing the course and all
		// actors projected through it to advance on every presented frame.
		// Make an explicit value copy: this simulation is heap promoted by
		// replay selection, while the interpolated view must remain separate.
		mut presentation := sim.Simulation{ ...simulation }
		presentation.ship.course_position = simulation.presentation_course_position(presentation_fraction)
		presentation.ship.relative_depth = simulation.presentation_relative_depth(presentation_fraction)
		presentation.ship.eye_angle = simulation.presentation_eye_angle(presentation_fraction)
		presentation.ship.angle = simulation.presentation_ship_angle(presentation_fraction)
		presentation.ship.bank = simulation.presentation_ship_bank(presentation_fraction)
		calibration_parameters := calibration_camera.parameters()
		cinematic_replay := replay_uses_cinematic_camera(replay_mode, attract_replay, replay_camera_enabled)
		use_replay_camera_3d := calibration_mode || cinematic_replay
		camera_angle := if calibration_mode {
			calibration_parameters.eye_angle
		} else if use_replay_camera_3d {
			replay_camera.view_angle
		} else {
			presentation.camera_angle()
		}
		camera_depth := if calibration_mode {
			calibration_parameters.eye_depth
		} else {
			camera_depth_for_render(use_replay_camera_3d, replay_camera.depth_offset, presentation.ship.relative_depth)
		}
		camera_zoom := if calibration_mode {
			f32(1)
		} else if use_replay_camera_3d {
			replay_camera.zoom
		} else {
			f32(1)
		}
		course_camera_angle := if use_replay_camera_3d { f32(0) } else { camera_angle }
		course_view_direction := if use_replay_camera_3d
			&& replay_camera.look_at_depth < replay_camera.depth_offset {
			f32(-1)
		} else {
			f32(1)
		}
		course_start_distance := presentation.course_render_start_for_camera(camera_depth, use_replay_camera_3d, course_view_direction)
		all_render_instances := if calibration_mode {
			calibration_scene.render_instances(app.object_sizes, calibration_camera)
		} else if world_visible {
			presentation.render_instances_for_camera_with_scales(course_camera_angle, app.object_sizes.render_scales())
		} else {
			[]sim.RenderInstance{}
		}
		// Tuning deliberately keeps its labelled reference cards. Gameplay and
		// replay consistently use the asymmetric 3D hulls; their mesh frames carry
		// the course-relative bank for either camera projection.
		render_instances := if keeps_instanced_ship_bodies(calibration_mode) {
			all_render_instances
		} else {
			all_render_instances.filter(!is_runtime_ship_body(it))
		}
		if render_instances.len > 0 {
			C.tt_platform_set_bullets(app.platform, unsafe { voidptr(&render_instances[0]) }, u32(render_instances.len))
		} else {
			C.tt_platform_set_bullets(app.platform, unsafe { nil }, 0)
		}
		wire_ring_count := course_ring_count_for_draw_distance(app.wire_draw_distance)
		panel_ring_count := app.track_draw_distance + 2
		course_camera_distance := presentation.course_camera_distance(camera_depth, use_replay_camera_3d)
		mut tunnel_vertices := if calibration_mode || app.wire_draw_distance == 0 {
			[]sim.CourseVertex{}
		} else if world_visible {
			presentation.render_course_wire_without_markers(wire_ring_count, 32, course_camera_angle, course_start_distance, app.track_draw_distance, course_camera_distance, app.rear_track_blend_percent)
		} else {
			[]sim.CourseVertex{}
		}
		if world_visible && app.wire_draw_distance > 0 && cinematic_replay {
			tunnel_vertices << presentation.render_course_backward_wire_without_markers(wire_ring_count, 32, course_camera_angle, course_start_distance, app.track_draw_distance, course_camera_distance, app.rear_track_blend_percent)
		}
		if world_visible && !calibration_mode && app.border_draw_distance > 0 {
			tunnel_vertices << presentation.render_course_side_lights_to_distance(course_camera_angle,
				course_start_distance, 1, 0, app.border_draw_distance)
			if cinematic_replay {
				tunnel_vertices << presentation.render_course_side_lights_to_distance(course_camera_angle,
					course_start_distance, -1, 0, app.border_draw_distance)
			}
		}
		if world_visible && !title_mode && !calibration_mode && app.debug_view.any() {
			tunnel_vertices << presentation.render_debug_view_vertices(course_camera_angle,
				course_start_distance, int_max(wire_ring_count, panel_ring_count), app.debug_view)
		}
		if tunnel_vertices.len > 0 {
			C.tt_platform_set_tunnel(app.platform, unsafe { voidptr(&tunnel_vertices[0]) }, u32(tunnel_vertices.len))
		} else {
			C.tt_platform_set_tunnel(app.platform, unsafe { nil }, 0)
		}
		mut tunnel_fill_vertices := if calibration_mode {
			[]sim.CourseFillVertex{}
		} else if world_visible {
			presentation.render_course_fill_snapshot_from_with_rear_blend(panel_ring_count, 32, course_camera_angle, course_start_distance, course_camera_distance, app.rear_track_blend_percent, app.track_draw_distance)
		} else {
			[]sim.CourseFillVertex{}
		}
		if world_visible && cinematic_replay {
			tunnel_fill_vertices << presentation.render_course_backward_fill_snapshot_from_with_rear_blend(panel_ring_count, 32, course_camera_angle, course_start_distance, course_camera_distance, app.rear_track_blend_percent, app.track_draw_distance)
		}
		if tunnel_fill_vertices.len > 0 {
			C.tt_platform_set_tunnel_fill(app.platform, unsafe { voidptr(&tunnel_fill_vertices[0]) }, u32(tunnel_fill_vertices.len))
		} else {
			C.tt_platform_set_tunnel_fill(app.platform, unsafe { nil }, 0)
		}
		ship_mesh_vertices := if calibration_mode {
			calibration_scene.render_ship_meshes(app.object_sizes, calibration_models.catalog, calibration_camera)
		} else if uses_volumetric_ship_meshes(calibration_mode, world_visible) {
			presentation.render_ship_mesh_vertices_for_camera(course_camera_angle, app.object_sizes.render_scales())
		} else {
			[]sim.CourseFillVertex{}
		}
		if ship_mesh_vertices.len > 0 {
			C.tt_platform_set_ship_mesh(app.platform, unsafe { voidptr(&ship_mesh_vertices[0]) }, u32(ship_mesh_vertices.len))
		} else {
			C.tt_platform_set_ship_mesh(app.platform, unsafe { nil }, 0)
		}
		C.tt_platform_set_ship_material_seed(app.platform, ship_material_key(simulation.config.random_seed, simulation.level, simulation.zone))
		tunnel_color := if calibration_mode {
			sim.calibration_ice_cyan
		} else {
			simulation.tunnel_line_color()
		}
		C.tt_platform_set_tunnel_color(app.platform, tunnel_color.r, tunnel_color.g, tunnel_color.b)
		C.tt_platform_set_tunnel_scale(app.platform, if calibration_mode {
			f32(1)
		} else {
			app.object_sizes.tunnel
		})
		camera_eye_height := if calibration_mode {
			calibration_parameters.eye_height
		} else {
			replay_camera.height
		}
		camera_look_angle := if calibration_mode {
			calibration_parameters.look_angle
		} else {
			replay_camera.look_at_angle
		}
		camera_look_depth := if calibration_mode {
			calibration_parameters.look_depth
		} else {
			replay_camera.look_at_depth
		}
		camera_look_height := if calibration_mode {
			calibration_parameters.look_height
		} else {
			replay_camera.look_at_height
		}
		C.tt_platform_set_camera(app.platform, camera_angle, camera_depth, camera_zoom, if calibration_mode {
			f32(0)
		} else {
			simulation.ship.camera_shake_x
		}, if calibration_mode { f32(0) } else { simulation.ship.camera_shake_y }, use_replay_camera_3d, camera_eye_height, camera_look_angle, camera_look_depth, camera_look_height, if calibration_mode {
			f32(0)
		} else {
			replay_camera.rotation
		}, presentation.ship_render_surface_radius(course_camera_angle), presentation.ship_render_depth())
		C.tt_platform_set_transition(app.platform, if calibration_mode {
			f32(0)
		} else {
			presentation_fade(presentation_timers.transition_remaining_ms, presentation_timers.game_over_elapsed_ms)
		})
		replay_ratio := if calibration_mode {
			f32(1)
		} else {
			title_replay_view_ratio(title_mode, last_replay.inputs.len > 0, presentation_timers.replay_change_ms)
		}
		C.tt_platform_set_replay_view_ratio(app.platform, replay_ratio)
		if calibration_mode {
			C.tt_platform_set_hud_visible(app.platform, false)
		} else if title_mode && presentation_timers.replay_change_ms > 0 && presentation_timers.replay_change_ms < replay_transition_duration_ms {
			C.tt_platform_set_hud_visible(app.platform, false)
		} else if title_replay_uses_gameplay_status(title_mode, replay_mode, presentation_timers.replay_change_ms) {
			// Switch the state bits before revealing the full-window replay HUD.
			// Otherwise the title torus can flash for up to the next status tick.
			app.set_gameplay_status(simulation, paused)
			C.tt_platform_set_hud_visible(app.platform, replay_hud_visible)
		} else if title_mode {
			C.tt_platform_set_hud_visible(app.platform, true)
			app.set_title_status(player_data, title_start_levels, last_replay.inputs.len > 0, title_menu_item, title_help_page)
		}
		if !title_mode && !calibration_mode
			&& should_refresh_gameplay_status(paused, simulation.game_over, simulation.tick) {
			app.set_gameplay_status(simulation, paused)
		}
		if test_object_tuning {
			tuning_test_frames++
			if tuning_test_frames >= 300 {
				C.tt_platform_request_close(app.platform)
			}
		}
		app.draw_replay_library(replay_library, player_data)
		if !C.tt_platform_poll(app.platform) {
			eprintln('rendering failed: ${unsafe { C.tt_platform_last_error().vstring() }}')
			break
		}
	}
	app.finish_suspended_run(suspended_run, mut player_data)
	println('simulation ticks=${simulation.tick} bullets=${simulation.living_bullets()} enemies=${simulation.living_enemies()} score=${simulation.score} checksum=${simulation.checksum():016x}')
}

fn (app &App) save_player_data_if_enabled(data PlayerData) {
	if !app.persistence_enabled || app.player_data_path.len == 0 {
		return
	}
	save_player_data(app.player_data_path, data) or {
		eprintln('could not save player data: ${err}')
	}
}

fn (app &App) set_gameplay_status(simulation &sim.Simulation, paused bool) {
	C.tt_platform_set_status(app.platform, simulation.score, simulation.remaining_time_ms, simulation.ship.hits, int(simulation.level), int(simulation.ship.speed * displayed_speed_scale), simulation.stage.rank, int_max(simulation.stage.zone_end_rank - simulation.stage.rank, 0), simulation.next_extend_score, simulation.time_change_ticks, simulation.time_change_seconds, simulation.game_over, paused, app.god_mode)
}

fn inject_test_event(mut simulation sim.Simulation) {
	match simulation.tick {
		120 { println('[effect test] charge begins') }
		240 { println('[effect test] maximum charge released') }
		270 {
			println('[effect test] non-overlapping X100/X12/X2 multiplier list')
			simulation.multiplier_popup_cursor = 0
			simulation.multiplier_popups[0] = sim.MultiplierPopup{
				alive:      true
				life:       180
				alpha:      0.8
				multiplier: 100
			}
			simulation.multiplier_popups[1] = sim.MultiplierPopup{
				alive:      true
				life:       180
				alpha:      0.8
				multiplier: 12
			}
			simulation.multiplier_popups[2] = sim.MultiplierPopup{
				alive:      true
				life:       180
				alpha:      0.8
				multiplier: 2
			}
		}
		300 {
			inject_destroyed_enemy(mut simulation, 0, false, '[effect test] small enemy hit/destruction')
		}
		360 {
			inject_destroyed_enemy(mut simulation, 1, true, '[effect test] middle enemy hit/destruction')
		}
		420 {
			inject_destroyed_enemy(mut simulation, 2, true, '[effect test] boss destruction and zone +30 sec')
		}
		482 {
			inject_destroyed_enemy(mut simulation, 2, true, '[effect test] boss destruction, zone +45 sec, music change')
		}
		540 {
			println('[effect test] player hit and -15 sec')
			simulation.ship.invulnerable_ticks = 0
			simulation.ship.lifecycle_counter = 1
			simulation.spawn(sim.Vec2{
				x: simulation.ship.angle
				y: simulation.ship.relative_depth
			}, 0, 0, -1)
		}
		600 {
			println('[effect test] 100,000-point time extension')
			simulation.score = 100001
		}
		660 {
			println('[effect test] final warning beeps, then game over/music fade')
			simulation.remaining_time_ms = 2017
			simulation.next_beep_time_ms = 2000
		}
		else {}
	}
}

fn inject_destroyed_enemy(mut simulation sim.Simulation, kind int, charged bool, label string) {
	println(label)
	if kind == 2 {
		simulation.stage.in_boss_mode = true
		simulation.stage.bosses_remaining = 1
	}
	health := if kind == 2 {
		30
	} else if kind == 1 {
		10
	} else {
		1
	}
	score := if kind == 2 {
		2000
	} else if kind == 1 {
		500
	} else {
		100
	}
	position := sim.Vec2{
		x: simulation.ship.angle
		// Keep the scripted visual regression away from the ship and HUD so the
		// destruction tier and floating multiplier remain independently legible.
		y: simulation.ship.relative_depth + 6
	}
	simulation.enemies[0] = sim.Enemy{
		alive:    true
		position: position
		health:   health
		kind:     kind
		score:    score
	}
	simulation.shots[0] = sim.Shot{
		alive:      true
		position:   sim.Vec2{
			x: position.x
			y: position.y - 0.715
		}
		range:      35
		charged:    charged
		damage:     if charged { 100 } else { 1 }
		multiplier: if charged { 2 } else { 1 }
	}
}

pub fn (mut app App) shutdown() {
	// The callback thread and device must stop before GLFW/Vulkan are torn down.
	if !isnil(app.audio) {
		app.audio.shutdown()
		app.audio = unsafe { nil }
	}
	if !isnil(app.compute_session) {
		app.compute_session.close()
		app.compute_session = unsafe { nil }
	}
	if !isnil(app.vulkan_memory) {
		C.tt_platform_wait_idle(app.platform)
		app.vulkan_memory.destroy()
		app.vulkan_memory = unsafe { nil }
	}
	if !isnil(app.platform) {
		C.tt_platform_destroy(app.platform)
		app.platform = unsafe { nil }
	}
}

struct SimulationAudioState {
	fired_shots      int
	side_fired_shots int
	charging_shot    int
	charge_ticks     int
	enemy_hits       int
	destroyed_small  int
	destroyed_middle int
	destroyed_boss   int
	ship_hits        int
	time_extensions  int
	warning_beeps    int
	music_fades      int
	music_changes    int
	game_over        bool
}

struct MusicSequence {
mut:
	track     int = -1
	direction int = 1
}

fn new_music_sequence(seed u64, track_count int, previous_track int) MusicSequence {
	if track_count <= 0 {
		return MusicSequence{}
	}
	mut random := sim.new_mt19937(u32(seed))
	mut track := random.next_int(track_count)
	direction := random.next_int(2) * 2 - 1
	if track == previous_track {
		track = (track + 1) % track_count
	}
	return MusicSequence{
		track:     track
		direction: direction
	}
}

fn (mut sequence MusicSequence) advance(track_count int) int {
	if track_count <= 0 {
		sequence.track = -1
		return sequence.track
	}
	sequence.track += sequence.direction
	if sequence.track < 0 {
		sequence.track = track_count - 1
	} else if sequence.track >= track_count {
		sequence.track = 0
	}
	return sequence.track
}

fn capture_audio_state(simulation &sim.Simulation) SimulationAudioState {
	mut charge_ticks := 0
	if simulation.charging_shot >= 0 {
		charge_ticks = simulation.shots[simulation.charging_shot].charge_ticks
	}
	return SimulationAudioState{
		fired_shots:      simulation.fired_shots
		side_fired_shots: simulation.side_fired_shots
		charging_shot:    simulation.charging_shot
		charge_ticks:     charge_ticks
		enemy_hits:       simulation.enemy_hits
		destroyed_small:  simulation.destroyed_small
		destroyed_middle: simulation.destroyed_middle
		destroyed_boss:   simulation.destroyed_boss
		ship_hits:        simulation.ship.hits
		time_extensions:  simulation.time_extensions
		warning_beeps:    simulation.warning_beeps
		music_fades:      simulation.music_fades
		music_changes:    simulation.music_changes
		game_over:        simulation.game_over
	}
}

fn (mut app App) play_simulation_audio(previous SimulationAudioState, simulation &sim.Simulation,
	mut music_sequence MusicSequence) {
	if isnil(app.audio) {
		return
	}
	if simulation.fired_shots > previous.fired_shots
		|| simulation.side_fired_shots > previous.side_fired_shots {
		app.audio.play_effect(.shot)
	}
	if simulation.charging_shot >= 0 {
		shot := simulation.shots[simulation.charging_shot]
		if shot.charge_ticks > previous.charge_ticks && (shot.charge_ticks - 1) % 52 == 0 {
			app.audio.play_effect(.charge)
		}
	} else if previous.charging_shot >= 0 && previous.charge_ticks >= sim.charged_shot_min_ticks {
		app.audio.play_effect(.charge_shot)
	}
	if simulation.enemy_hits > previous.enemy_hits {
		app.audio.play_effect(.hit)
	}
	if simulation.destroyed_small > previous.destroyed_small {
		app.audio.play_effect(.small_dest)
	}
	if simulation.destroyed_middle > previous.destroyed_middle {
		app.audio.play_effect(.middle_dest)
	}
	if simulation.destroyed_boss > previous.destroyed_boss {
		app.audio.play_effect(.boss_dest)
	}
	if simulation.ship.hits > previous.ship_hits {
		app.audio.play_effect(.myship_dest)
	}
	if simulation.time_extensions > previous.time_extensions {
		app.audio.play_effect(.extend)
	}
	if simulation.warning_beeps > previous.warning_beeps {
		app.audio.play_effect(.timeup_beep)
	}
	if simulation.game_over && !previous.game_over {
		app.audio.fade_music()
	}
	if simulation.music_fades > previous.music_fades {
		app.audio.fade_music()
	}
	if simulation.music_changes > previous.music_changes {
		app.audio.play_music(music_sequence.advance(4))
	}
}

fn version_major(version u32) u32 {
	return version >> 22
}

fn version_minor(version u32) u32 {
	return (version >> 12) & 0x3ff
}

fn version_patch(version u32) u32 {
	return version & 0xfff
}

fn ship_material_key(seed u64, level f32, zone int) u32 {
	// Hash input is presentation state only; never advance a simulation RNG.
	return u32(seed) ^ (u32(int(level)) * u32(0x85ebca6b)) ^ (u32(zone) * u32(0x9e3779b9))
}
