module main

import os
import runtime
import sim

fn main() {
	launch_args := effective_arguments('options.ini', os.args[1..])
	relaunch_graphical_tinyc_build(launch_args)
	resolution := resolution_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	grade := grade_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	starting_level := level_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	brightness := percentage_argument(launch_args, ['--brightness', '-brightness'], runtime.default_brightness_percent) or {
		eprintln(err)
		exit(2)
	}
	luminosity := percentage_argument(launch_args, ['--luminosity', '--luminous', '-luminosity',
		'-luminous'], runtime.default_luminosity_percent) or {
		eprintln(err)
		exit(2)
	}
	near_blur := percentage_argument(launch_args, ['--near-blur'], runtime.default_near_blur_percent) or {
		eprintln(err)
		exit(2)
	}
	near_fade := percentage_argument(launch_args, ['--near-fade'], runtime.default_near_fade_percent) or {
		eprintln(err)
		exit(2)
	}
	rear_track_blend := rear_track_blend_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	track_draw_distance := track_draw_distance_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	wire_draw_distance := wire_draw_distance_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	border_draw_distance := border_draw_distance_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	fps_limit := fps_limit_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	compute_backend := compute_backend_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	debug_view := debug_view_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	key_bindings := key_bindings_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	antialiasing_samples := antialiasing_argument(launch_args) or {
		eprintln(err)
		exit(2)
	}
	if '--headless' in launch_args {
		run_headless(grade, starting_level, compute_backend, launch_args)
		return
	}
	tuning_launch := '--tune' in launch_args || '--test-object-tuning' in launch_args
	mut app := runtime.new_app(runtime.AppConfig{
		title:                    'Torus Trooper'
		width:                    resolution.width
		height:                   resolution.height
		audio_volume:             audio_volume_argument(launch_args)
		audio_volume_explicit:    audio_volume_argument_explicit(launch_args)
		antialiasing_samples:     antialiasing_samples
		antialiasing_explicit:    antialiasing_argument_explicit(launch_args)
		near_blur_percent:        int(near_blur * 100.0 + 0.5)
		near_blur_explicit:       named_argument_explicit(launch_args, ['--near-blur'])
		near_fade_percent:        int(near_fade * 100.0 + 0.5)
		near_fade_explicit:       named_argument_explicit(launch_args, ['--near-fade'])
		rear_track_blend_percent: rear_track_blend
		rear_track_explicit:      named_argument_explicit(launch_args, [
			'--rear-track-blend',
			'--no-rear-track-blend',
			'--rear-track-blend-percent',
		])
		track_draw_distance:      track_draw_distance
		track_draw_explicit:      named_argument_explicit(launch_args, [
			'--track-draw-distance',
		])
		wire_draw_distance:       wire_draw_distance
		wire_draw_explicit:       named_argument_explicit(launch_args, [
			'--wire-draw-distance',
		])
		border_draw_distance:     border_draw_distance
		border_draw_explicit:     named_argument_explicit(launch_args, [
			'--border-draw-distance',
		])
		fps_limit:                fps_limit
		fps_limit_explicit:       named_argument_explicit(launch_args, ['--fps-limit'])
		audio_enabled:            !tuning_launch && !no_sound_argument(launch_args)
		key_bindings:             key_bindings
		brightness:               brightness
		luminosity:               luminosity
		grade:                    grade
		starting_level:           starting_level
		reverse_buttons:          reverse_buttons_argument(launch_args)
		fullscreen:               fullscreen_argument(launch_args)
		player_data_path:         player_data_path_argument(launch_args)
		object_sizes_path:        object_sizes_path_argument(launch_args)
		model_file_path:          model_file_path_argument(launch_args)
		persistence_enabled:      '--test-effects' !in launch_args
		selection_explicit:       selection_argument_explicit(launch_args)
		compute_backend:          compute_backend
		debug_view:               debug_view
	}) or {
		eprintln('startup failed: ${err}')
		exit(1)
	}
	defer {
		app.shutdown()
	}

	if '--probe' in launch_args {
		app.print_diagnostics()
		return
	}
	app.run('--test-effects' in launch_args, '--test-object-tuning' in launch_args,
		'--tune' in launch_args)
}

fn relaunch_graphical_tinyc_build(launch_args []string) {
	$if tinyc && linux {
		if '--headless' in launch_args {
			return
		}
		// Volk exposes Vulkan commands as global function-pointer variables.
		// TinyCC exports those variables from ELF executables, allowing the
		// Vulkan loader and GLFW 3.x to resolve them as if they were functions.
		// A system compiler gives these implementation details hidden linkage.
		mut compiler_args := ['-cc', 'gcc', 'run', @VMODROOT]
		compiler_args << os.args[1..]
		os.execvp(@VEXE, compiler_args) or {
			eprintln('could not restart the graphical build with GCC: ${err}')
			exit(1)
		}
	} $else {
		_ = launch_args
	}
}

fn effective_arguments(options_path string, command_arguments []string) []string {
	mut launch_args := []string{}
	if content := os.read_file(options_path) {
		launch_args << content.fields()
	}
	launch_args << command_arguments
	return launch_args
}

fn player_data_path_argument(launch_args []string) string {
	for index, argument in launch_args {
		if argument == '--data-file' && index + 1 < launch_args.len {
			return launch_args[index + 1]
		}
		if argument.starts_with('--data-file=') {
			return argument.all_after('=')
		}
	}
	config_directory := os.config_dir() or { os.home_dir() }
	return os.join_path(config_directory, 'torus_trooper', 'player.json')
}

fn object_sizes_path_argument(launch_args []string) string {
	for index, argument in launch_args {
		if argument == '--object-sizes-file' && index + 1 < launch_args.len {
			return launch_args[index + 1]
		}
		if argument.starts_with('--object-sizes-file=') {
			return argument.all_after('=')
		}
	}
	config_directory := os.config_dir() or { os.home_dir() }
	return os.join_path(config_directory, 'torus_trooper', 'object_sizes.json')
}

fn model_file_path_argument(launch_args []string) string {
	for index, argument in launch_args {
		if argument == '--model-file' && index + 1 < launch_args.len {
			return launch_args[index + 1]
		}
		if argument.starts_with('--model-file=') {
			return argument.all_after('=')
		}
	}
	return os.join_path('models', 'tune_models.json')
}

fn debug_view_argument(launch_args []string) !sim.DebugViewOptions {
	mut selected := ''
	for index, argument in launch_args {
		if argument == '--debug-view' {
			if index + 1 >= launch_args.len {
				return error('--debug-view needs a comma-separated value')
			}
			selected = launch_args[index + 1]
		} else if argument.starts_with('--debug-view=') {
			selected = argument.all_after('=')
		}
	}
	if selected == '' || selected == 'off' {
		return sim.DebugViewOptions{}
	}
	if selected == 'all' {
		return sim.DebugViewOptions{
			boundaries: true
			slices:     true
			enemies:    true
			collisions: true
			exhaust:    true
		}
	}
	mut boundaries := false
	mut slices := false
	mut enemies := false
	mut collisions := false
	mut exhaust := false
	for item in selected.split(',') {
		match item {
			'boundaries' { boundaries = true }
			'slices' { slices = true }
			'enemies' { enemies = true }
			'collisions' { collisions = true }
			'exhaust' { exhaust = true }
			else { return error('unknown debug view: ${item}') }
		}
	}
	return sim.DebugViewOptions{
		boundaries: boundaries
		slices:     slices
		enemies:    enemies
		collisions: collisions
		exhaust:    exhaust
	}
}

fn selection_argument_explicit(launch_args []string) bool {
	for argument in launch_args {
		if argument == '--grade' || argument.starts_with('--grade=') || argument == '--level'
			|| argument.starts_with('--level=') {
			return true
		}
	}
	return false
}

struct WindowSize {
	width  int = runtime.default_window_width
	height int = runtime.default_window_height
}

fn resolution_argument(launch_args []string) !WindowSize {
	mut size := WindowSize{}
	for index, argument in launch_args {
		if argument in ['--resolution', '--res', '-res'] {
			if index + 2 >= launch_args.len {
				return error('${argument} requires width and height')
			}
			size = WindowSize{
				width:  launch_args[index + 1].int()
				height: launch_args[index + 2].int()
			}
		}
	}
	if size.width <= 0 || size.height <= 0 {
		return error('resolution width and height must be positive')
	}
	return size
}

fn reverse_buttons_argument(launch_args []string) bool {
	return '--reverse' in launch_args || '-reverse' in launch_args
}

fn fullscreen_argument(launch_args []string) bool {
	mut fullscreen := false
	for argument in launch_args {
		match argument {
			'--fullscreen', '-fullscreen' {
				fullscreen = true
			}
			'--window', '-window' {
				fullscreen = false
			}
			else {}
		}
	}
	return fullscreen
}

fn rear_track_blend_argument(launch_args []string) !int {
	mut percent := runtime.default_rear_track_blend_percent
	for index, argument in launch_args {
		if argument == '--no-rear-track-blend' {
			percent = 0
		} else if argument == '--rear-track-blend' {
			percent = runtime.default_rear_track_blend_percent
		} else if argument == '--rear-track-blend-percent' {
			if index + 1 >= launch_args.len {
				return error('--rear-track-blend-percent requires a value from 0 to 100')
			}
			percent = launch_args[index + 1].int()
		} else if argument.starts_with('--rear-track-blend-percent=') {
			percent = argument.all_after('=').int()
		}
	}
	if percent < 0 || percent > 100 {
		return error('rear track blend must be from 0 to 100 percent')
	}
	return percent
}

fn track_draw_distance_argument(launch_args []string) !int {
	mut value := runtime.default_track_draw_distance
	for index, argument in launch_args {
		if argument == '--track-draw-distance' {
			if index + 1 >= launch_args.len {
				return error('--track-draw-distance requires a value from 0 to 999')
			}
			value = launch_args[index + 1].int()
		} else if argument.starts_with('--track-draw-distance=') {
			value = argument.all_after('=').int()
		}
	}
	if value < runtime.minimum_track_draw_distance || value > runtime.maximum_track_draw_distance {
		return error('track draw distance must be from 0 to 999')
	}
	return value
}

fn wire_draw_distance_argument(launch_args []string) !int {
	mut value := runtime.default_wire_draw_distance
	for index, argument in launch_args {
		if argument == '--wire-draw-distance' {
			if index + 1 >= launch_args.len {
				return error('--wire-draw-distance requires a value from 0 to 999')
			}
			value = launch_args[index + 1].int()
		} else if argument.starts_with('--wire-draw-distance=') {
			value = argument.all_after('=').int()
		}
	}
	if value < runtime.minimum_track_draw_distance || value > runtime.maximum_track_draw_distance {
		return error('wire draw distance must be from 0 to 999')
	}
	return value
}

fn border_draw_distance_argument(launch_args []string) !int {
	mut value := runtime.default_border_draw_distance
	for index, argument in launch_args {
		if argument == '--border-draw-distance' {
			if index + 1 >= launch_args.len {
				return error('--border-draw-distance requires a value from 0 to 999')
			}
			value = launch_args[index + 1].int()
		} else if argument.starts_with('--border-draw-distance=') {
			value = argument.all_after('=').int()
		}
	}
	if value < runtime.minimum_track_draw_distance || value > runtime.maximum_track_draw_distance {
		return error('border draw distance must be from 0 to 999')
	}
	return value
}

fn fps_limit_argument(launch_args []string) !int {
	mut value := 'unlocked'
	for index, argument in launch_args {
		if argument == '--fps-limit' {
			if index + 1 >= launch_args.len {
				return error('--fps-limit requires 60, display, or unlocked')
			}
			value = launch_args[index + 1]
		} else if argument.starts_with('--fps-limit=') {
			value = argument.all_after('=')
		}
	}
	return match value.to_lower() {
		'60' { 60 }
		'display', 'vsync' { -1 }
		'unlocked', 'off', '0' { 0 }
		else {
			return error('invalid FPS limit `${value}`; use 60, display, or unlocked')
		}
	}
}

fn percentage_argument(launch_args []string, names []string, default_value int) !f32 {
	mut value := default_value
	for index, argument in launch_args {
		if argument in names {
			if index + 1 >= launch_args.len {
				return error('${argument} requires a value from 0 to 100')
			}
			value = launch_args[index + 1].int()
		} else {
			for name in names {
				if argument.starts_with('${name}=') {
					value = argument.all_after('=').int()
				}
			}
		}
	}
	if value < 0 || value > 100 {
		return error('percentage must be from 0 to 100')
	}
	return f32(value) / 100
}

fn named_argument_explicit(launch_args []string, names []string) bool {
	for argument in launch_args {
		if argument in names {
			return true
		}
		for name in names {
			if argument.starts_with('${name}=') {
				return true
			}
		}
	}
	return false
}

fn level_argument(launch_args []string) !int {
	mut value := 1
	for index, argument in launch_args {
		if argument == '--level' {
			if index + 1 >= launch_args.len {
				return error('--level requires a positive integer')
			}
			value = launch_args[index + 1].int()
		} else if argument.starts_with('--level=') {
			value = argument.all_after('=').int()
		}
	}
	if value < 1 {
		return error('--level requires a positive integer')
	}
	return value
}

fn no_sound_argument(launch_args []string) bool {
	return '--no-sound' in launch_args || '-nosound' in launch_args
}

fn grade_argument(launch_args []string) !sim.Grade {
	mut value := 'normal'
	for index, argument in launch_args {
		if argument == '--grade' {
			if index + 1 >= launch_args.len {
				return error('--grade requires normal, hard, or extreme')
			}
			value = launch_args[index + 1].to_lower()
		} else if argument.starts_with('--grade=') {
			value = argument.all_after('=').to_lower()
		}
	}
	return match value {
		'normal', 'n' { sim.Grade.normal }
		'hard', 'h' { sim.Grade.hard }
		'extreme', 'e' { sim.Grade.extreme }
		else { error('unknown grade "${value}"; expected normal, hard, or extreme') }
	}
}

fn audio_volume_argument(launch_args []string) f32 {
	mut volume := runtime.default_volume
	for index, argument in launch_args {
		if argument == '--volume' && index + 1 < launch_args.len {
			volume = launch_args[index + 1].f32()
		} else if argument.starts_with('--volume=') {
			volume = argument.all_after('=').f32()
		}
	}
	if volume < 0 {
		return 0
	}
	if volume > 1 {
		return 1
	}
	return volume
}

fn audio_volume_argument_explicit(launch_args []string) bool {
	for argument in launch_args {
		if argument == '--volume' || argument.starts_with('--volume=') {
			return true
		}
	}
	return false
}

fn antialiasing_argument(launch_args []string) !int {
	mut samples := runtime.default_antialiasing_samples
	for index, argument in launch_args {
		if argument in ['--antialiasing', '--msaa'] {
			if index + 1 >= launch_args.len {
				return error('${argument} requires 1, 2, 4, or 8')
			}
			samples = launch_args[index + 1].int()
		} else if argument.starts_with('--antialiasing=') || argument.starts_with('--msaa=') {
			samples = argument.all_after('=').int()
		}
	}
	if samples !in [1, 2, 4, 8] {
		return error('anti-aliasing samples must be 1, 2, 4, or 8')
	}
	return samples
}

fn antialiasing_argument_explicit(launch_args []string) bool {
	for argument in launch_args {
		if argument in ['--antialiasing', '--msaa']
			|| argument.starts_with('--antialiasing=') || argument.starts_with('--msaa=') {
			return true
		}
	}
	return false
}

fn key_binding_argument(launch_args []string, action string, default_value string,
	aliases []string) !string {
	mut value := default_value
	for index, argument in launch_args {
		if argument in aliases {
			if index + 1 >= launch_args.len {
				return error('${argument} requires a key name')
			}
			value = launch_args[index + 1]
		} else {
			for alias in aliases {
				if argument.starts_with('${alias}=') {
					value = argument.all_after('=')
				}
			}
		}
	}
	if value.len == 0 {
		return error('${action} key names cannot be empty')
	}
	return value
}

fn key_bindings_argument(launch_args []string) !runtime.KeyBindings {
	defaults := runtime.KeyBindings{}
	return runtime.KeyBindings{
		left:        key_binding_argument(launch_args, 'left', defaults.left, ['--bind-left'])!
		right:       key_binding_argument(launch_args, 'right', defaults.right, [
			'--bind-right',
		])!
		up:          key_binding_argument(launch_args, 'up', defaults.up, ['--bind-up'])!
		down:        key_binding_argument(launch_args, 'down', defaults.down, ['--bind-down'])!
		fire:        key_binding_argument(launch_args, 'fire', defaults.fire, ['--bind-fire'])!
		charge:      key_binding_argument(launch_args, 'charge', defaults.charge, [
			'--bind-charge',
			'--bind-brake',
		])!
		pause:       key_binding_argument(launch_args, 'pause', defaults.pause, [
			'--bind-pause',
		])!
		restart:     key_binding_argument(launch_args, 'restart', defaults.restart, [
			'--bind-restart',
			'--bind-start',
		])!
		back:        key_binding_argument(launch_args, 'back', defaults.back, ['--bind-back'])!
		volume_down: key_binding_argument(launch_args, 'volume down', defaults.volume_down, [
			'--bind-volume-down',
			'--volume-down-key',
		])!
		volume_up:   key_binding_argument(launch_args, 'volume up', defaults.volume_up, [
			'--bind-volume-up',
			'--volume-up-key',
		])!
		fullscreen:  key_binding_argument(launch_args, 'fullscreen', defaults.fullscreen, [
			'--bind-fullscreen',
		])!
		fps:         key_binding_argument(launch_args, 'FPS overlay', defaults.fps, [
			'--bind-fps',
		])!
	}
}

fn compute_backend_argument(launch_args []string) !sim.ComputeBackend {
	mut value := 'cpu'
	for index, argument in launch_args {
		if argument == '--compute' {
			if index + 1 >= launch_args.len {
				return error('--compute requires cpu or opencl')
			}
			value = launch_args[index + 1].to_lower()
		} else if argument.starts_with('--compute=') {
			value = argument.all_after('=').to_lower()
		}
	}
	return match value {
		'cpu' { sim.ComputeBackend.cpu }
		'opencl' { sim.ComputeBackend.opencl }
		else { error('unknown compute backend "${value}"; expected cpu or opencl') }
	}
}

fn run_headless(grade sim.Grade, starting_level int, compute_backend sim.ComputeBackend,
	launch_args []string) {
	mut ticks := 600
	for index, argument in launch_args {
		if argument == '--ticks' && index + 1 < launch_args.len {
			ticks = launch_args[index + 1].int()
		}
	}
	mut compute_session := sim.new_compute_session(compute_backend)
	defer {
		compute_session.close()
	}
	mut simulation := sim.new_simulation(sim.SimulationConfig{
		compute_backend: compute_backend
		grade:           grade
		starting_level:  starting_level
	})
	simulation.attach_compute_session(compute_session)
	for _ in 0 .. ticks {
		simulation.update()
	}
	println('ticks=${simulation.tick}')
	println('grade=${sim.rules_for_grade(grade).name}')
	println('level=${simulation.level:.1f}')
	println('living_bullets=${simulation.living_bullets()}')
	println('checksum=${simulation.checksum():016x}')
	render_instances := simulation.render_instances()
	println('render_instances=${render_instances.len}')
	println('render_checksum=${sim.render_snapshot_checksum(render_instances):016x}')
	course_vertices := simulation.render_course_snapshot(72, 32, simulation.camera_angle())
	println('course_vertices=${course_vertices.len}')
	println('course_checksum=${sim.course_snapshot_checksum(course_vertices):016x}')
	course_fill_vertices := simulation.render_course_fill_snapshot(72, 32, simulation.camera_angle())
	println('course_fill_vertices=${course_fill_vertices.len}')
	println('course_fill_checksum=${sim.course_fill_snapshot_checksum(course_fill_vertices):016x}')
	course_backward_vertices := simulation.render_course_backward_snapshot(72, 32, simulation.camera_angle())
	println('course_backward_vertices=${course_backward_vertices.len}')
	println('course_backward_checksum=${sim.course_snapshot_checksum(course_backward_vertices):016x}')
	course_backward_fill_vertices := simulation.render_course_backward_fill_snapshot(72, 32, simulation.camera_angle())
	println('course_backward_fill_vertices=${course_backward_fill_vertices.len}')
	println('course_backward_fill_checksum=${sim.course_fill_snapshot_checksum(course_backward_fill_vertices):016x}')
	println('compute_requested=${simulation.config.compute_backend.name()}')
	println('compute_active=${simulation.active_compute_backend().name()}')
	if simulation.active_compute_backend() == .opencl {
		println('opencl_device=${compute_session.device()}')
	} else if compute_backend == .opencl && compute_session.fallback().len > 0 {
		println('opencl_fallback=${compute_session.fallback()}')
	}
	println('compute_fallback_batches=${simulation.compute_stats.fallback_batches}')
	println('compute_verified_batches=${simulation.compute_stats.verified_batches}')
	println('compute_mismatched_batches=${simulation.compute_stats.mismatched_batches}')
	println('compute_particle_mismatched_batches=${simulation.compute_stats.particle_mismatched_batches}')
	println('compute_bullet_mismatched_batches=${simulation.compute_stats.bullet_mismatched_batches}')
	println('compute_shot_mismatched_batches=${simulation.compute_stats.shot_mismatched_batches}')
	println('compute_enemy_mismatched_batches=${simulation.compute_stats.enemy_mismatched_batches}')
	println('compute_differential_mismatches=${simulation.compute_stats.differential_mismatches}')
	println('compute_max_differential_error=${simulation.compute_stats.max_differential_error}')
	println('compute_collision_candidate_batches=${simulation.compute_stats.collision_candidate_batches}')
	println('compute_collision_candidate_items=${simulation.compute_stats.collision_candidate_items}')
	println('compute_collision_candidate_mismatched_batches=${simulation.compute_stats.collision_candidate_mismatched_batches}')
	println('compute_collision_candidate_mismatches=${simulation.compute_stats.collision_candidate_mismatches}')
	println('compute_collision_active_shots=${simulation.compute_stats.collision_active_shots}')
	println('compute_collision_active_targets=${simulation.compute_stats.collision_active_targets}')
	println('compute_collision_tested_pairs=${simulation.compute_stats.collision_tested_pairs}')
	println('compute_checksum=${simulation.compute_stats.checksum():016x}')
}
