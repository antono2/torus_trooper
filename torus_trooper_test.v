module main

import os
import sim

fn test_options_file_precedes_command_line_overrides() {
	directory := os.join_path(os.temp_dir(), 'torus_trooper_options_test_${os.getpid()}')
	path := os.join_path(directory, 'options.ini')
	defer {
		os.rmdir_all(directory) or {}
	}
	os.mkdir_all(directory) or { assert false, err.msg() }
	os.write_file(path, '-brightness 35\n-luminosity 25 -res 800 600\n-window\n-reverse\n-nosound\n--grade normal\n--level 2\n--msaa 2\n--near-blur 35\n--near-fade 40\n--track-draw-distance 58\n--wire-draw-distance 96\n--fps-limit display') or {
		assert false, err.msg()
	}
	launch_args := effective_arguments(path, [
		'--brightness',
		'90',
		'--resolution',
		'1920',
		'1080',
		'--fullscreen',
		'--grade=hard',
		'--level=7',
		'--antialiasing=8',
		'--near-blur=70',
		'--near-fade=75',
		'--track-draw-distance=68',
		'--wire-draw-distance=110',
		'--border-draw-distance=90',
		'--fps-limit=60',
	])
	size := resolution_argument(launch_args) or { panic(err) }
	assert size.width == 1920
	assert size.height == 1080
	assert percentage_argument(launch_args, ['--brightness', '-brightness'], 100) or {
		panic(err)
	} == f32(0.9)
	assert percentage_argument(launch_args, ['--luminosity', '--luminous', '-luminosity', '-luminous'], 80) or { panic(err) } == f32(0.25)
	assert fullscreen_argument(launch_args)
	assert reverse_buttons_argument(launch_args)
	assert no_sound_argument(launch_args)
	assert grade_argument(launch_args) or { panic(err) } == sim.Grade.hard
	assert level_argument(launch_args) or { panic(err) } == 7
	assert antialiasing_argument(launch_args) or { panic(err) } == 8
	assert percentage_argument(launch_args, ['--near-blur'], 60) or { panic(err) } == f32(0.7)
	assert named_argument_explicit(launch_args, ['--near-blur'])
	assert percentage_argument(launch_args, ['--near-fade'], 65) or { panic(err) } == f32(0.75)
	assert named_argument_explicit(launch_args, ['--near-fade'])
	assert track_draw_distance_argument(launch_args) or { panic(err) } == 68
	assert wire_draw_distance_argument(launch_args) or { panic(err) } == 110
	assert border_draw_distance_argument(launch_args) or { panic(err) } == 90
	assert named_argument_explicit(launch_args, ['--track-draw-distance'])
	assert fps_limit_argument(launch_args) or { panic(err) } == 60
	assert named_argument_explicit(launch_args, ['--fps-limit'])
	assert selection_argument_explicit(launch_args)
}

fn test_missing_options_file_uses_command_line_only() {
	launch_args := effective_arguments('/definitely/missing/torus-trooper-options.ini', [
		'--window',
		'--compute=opencl',
		'--volume=0.4',
	])
	assert launch_args == ['--window', '--compute=opencl', '--volume=0.4']
	assert !fullscreen_argument(launch_args)
	assert compute_backend_argument(launch_args) or { panic(err) } == sim.ComputeBackend.opencl
	assert audio_volume_argument(launch_args) == f32(0.4)
}

fn test_audio_volume_defaults_lower_and_preserves_explicit_overrides() {
	assert audio_volume_argument([]) == f32(0.35)
	assert audio_volume_argument(['--volume', '0.6']) == f32(0.6)
	assert audio_volume_argument(['--volume=0.2']) == f32(0.2)
	assert audio_volume_argument(['--volume=-1']) == f32(0)
	assert audio_volume_argument(['--volume=2']) == f32(1)
	assert !audio_volume_argument_explicit([])
	assert audio_volume_argument_explicit(['--volume', '0.6'])
	assert audio_volume_argument_explicit(['--volume=0.2'])
}

fn test_antialiasing_accepts_config_file_and_command_line_forms() {
	assert antialiasing_argument([]) or { panic(err) } == 8
	assert antialiasing_argument(['--msaa', '2']) or { panic(err) } == 2
	assert antialiasing_argument(['--antialiasing=8']) or { panic(err) } == 8
	assert antialiasing_argument(['--msaa=1']) or { panic(err) } == 1
	assert !antialiasing_argument_explicit([])
	assert antialiasing_argument_explicit(['--msaa=4'])
	_ := antialiasing_argument(['--msaa=3']) or {
		assert err.msg().contains('1, 2, 4, or 8')
		return
	}
	assert false
}

fn test_near_blur_accepts_config_file_and_command_line_forms() {
	assert percentage_argument([], ['--near-blur'], 80) or { panic(err) } == f32(0.8)
	assert percentage_argument(['--near-blur', '35'], ['--near-blur'], 80) or {
		panic(err)
	} == f32(0.35)
	assert percentage_argument(['--near-blur=0'], ['--near-blur'], 80) or {
		panic(err)
	} == f32(0)
	assert !named_argument_explicit([], ['--near-blur'])
	assert named_argument_explicit(['--near-blur=80'], ['--near-blur'])
}

fn test_near_fade_accepts_config_file_and_command_line_forms() {
	assert percentage_argument([], ['--near-fade'], 65) or { panic(err) } == f32(0.65)
	assert percentage_argument(['--near-fade=100'], ['--near-fade'], 65) or {
		panic(err)
	} == f32(1)
	assert named_argument_explicit(['--near-fade', '25'], ['--near-fade'])
}

fn test_fps_limit_accepts_fixed_display_and_unlocked_modes() {
	assert fps_limit_argument([]string{}) or { panic(err) } == 0
	assert fps_limit_argument(['--fps-limit', '60']) or { panic(err) } == 60
	assert fps_limit_argument(['--fps-limit=display']) or { panic(err) } == -1
	assert fps_limit_argument(['--fps-limit=unlocked']) or { panic(err) } == 0
}

fn test_fps_limit_rejects_30() {
	_ := fps_limit_argument(['--fps-limit=30']) or {
		assert err.msg().contains('invalid FPS limit')
		return
	}
	assert false
}

fn test_fps_limit_rejects_arbitrary_rates() {
	_ := fps_limit_argument(['--fps-limit=165']) or {
		assert err.msg().contains('invalid FPS limit')
		return
	}
	assert false
}

fn test_all_input_actions_are_bindable_from_options_or_command_line() {
	defaults := key_bindings_argument([]string{}) or { panic(err) }
	assert defaults.left.starts_with('left,a,kp_4')
	assert defaults.left.contains('gamepad_left_stick_left')
	assert defaults.left.contains('joystick_axis_1_negative')
	assert defaults.fire.contains('space')
	assert defaults.fire.contains('gamepad_a')
	assert defaults.fire.contains('joystick_button_1')
	assert defaults.charge.contains('left_shift')
	assert defaults.back == 'escape'
	assert defaults.volume_down == 'minus,kp_subtract'
	assert defaults.volume_up == 'equal,kp_add'
	assert defaults.fullscreen == 'f11'
	assert defaults.fps == 'f'
	bound := key_bindings_argument([
		'--bind-left=a,j',
		'--bind-fire',
		'f,space',
		'--bind-charge=c',
		'--bind-pause=q',
		'--bind-restart=enter',
		'--bind-back=backspace',
		'--bind-volume-down',
		'page_down',
		'--volume-up-key=page_up',
		'--bind-fullscreen=f12',
		'--bind-fps=f10',
	]) or { panic(err) }
	assert bound.left == 'a,j'
	assert bound.fire == 'f,space'
	assert bound.charge == 'c'
	assert bound.pause == 'q'
	assert bound.restart == 'enter'
	assert bound.back == 'backspace'
	assert bound.volume_down == 'page_down'
	assert bound.volume_up == 'page_up'
	assert bound.fullscreen == 'f12'
	assert bound.fps == 'f10'
	_ := key_bindings_argument(['--bind-volume-up']) or {
		assert err.msg().contains('requires a key name')
		return
	}
	assert false
}

fn test_later_window_mode_wins_across_file_and_command_line() {
	assert fullscreen_argument(['--window', '--fullscreen'])
	assert !fullscreen_argument(['--fullscreen', '-window'])
}

fn test_rear_track_blend_slider_and_legacy_flags() {
	assert rear_track_blend_argument([]) or { panic(err) } == 10
	assert rear_track_blend_argument(['--no-rear-track-blend', '--rear-track-blend']) or { panic(err) } == 10
	assert rear_track_blend_argument(['--rear-track-blend', '--no-rear-track-blend']) or { panic(err) } == 0
	assert rear_track_blend_argument(['--rear-track-blend-percent=58']) or { panic(err) } == 58
	assert rear_track_blend_argument(['--rear-track-blend-percent', '100']) or { panic(err) } == 100
	assert named_argument_explicit(['--rear-track-blend'], ['--rear-track-blend',
		'--no-rear-track-blend'])
}

fn test_track_draw_distance_accepts_config_and_command_line_forms() {
	assert track_draw_distance_argument([]) or { panic(err) } == 75
	assert track_draw_distance_argument(['--track-draw-distance', '0']) or { panic(err) } == 0
	assert track_draw_distance_argument(['--track-draw-distance=999']) or { panic(err) } == 999
	_ := track_draw_distance_argument(['--track-draw-distance=1000']) or {
		assert err.msg().contains('0 to 999')
		return
	}
	assert false
}

fn test_wire_draw_distance_accepts_config_and_command_line_forms() {
	assert wire_draw_distance_argument([]) or { panic(err) } == 120
	assert wire_draw_distance_argument(['--wire-draw-distance', '0']) or { panic(err) } == 0
	assert wire_draw_distance_argument(['--wire-draw-distance=999']) or { panic(err) } == 999
	_ := wire_draw_distance_argument(['--wire-draw-distance=1000']) or {
		assert err.msg().contains('wire draw distance')
		return
	}
	assert false
}

fn test_border_draw_distance_accepts_config_and_command_line_forms() {
	assert border_draw_distance_argument([]) or { panic(err) } == 120
	assert border_draw_distance_argument(['--border-draw-distance', '0']) or { panic(err) } == 0
	assert border_draw_distance_argument(['--border-draw-distance=999']) or { panic(err) } == 999
	_ := border_draw_distance_argument(['--border-draw-distance=1000']) or {
		assert err.msg().contains('border draw distance')
		return
	}
	assert false
}

fn test_object_sizes_path_accepts_split_and_equals_forms() {
	assert object_sizes_path_argument(['--object-sizes-file', '/tmp/first.json']) == '/tmp/first.json'
	assert object_sizes_path_argument(['--object-sizes-file=/tmp/second.json']) == '/tmp/second.json'
	assert object_sizes_path_argument([]).ends_with(os.join_path('torus_trooper', 'object_sizes.json'))
	assert model_file_path_argument(['--model-file', '/tmp/first.json']) == '/tmp/first.json'
	assert model_file_path_argument(['--model-file=/tmp/second.json']) == '/tmp/second.json'
	assert model_file_path_argument([]) == os.join_path('models', 'tune_models.json')
}

fn test_debug_view_argument_selects_named_overlays() {
	assert !debug_view_argument([])!.any()
	all := debug_view_argument(['--debug-view=all'])!
	assert all.boundaries && all.slices && all.enemies && all.collisions && all.exhaust
	selected := debug_view_argument(['--debug-view', 'boundaries,enemies'])!
	assert selected.boundaries && selected.enemies
	assert !selected.slices && !selected.collisions && !selected.exhaust
	if _ := debug_view_argument(['--debug-view=invalid']) {
		assert false
	} else {
		assert true
	}
}
