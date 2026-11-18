// Run the Linux verification gates for the game, supporting modules and renderer.
import os
import scripts.testrun
import strconv
import time

const gate_timeout = 10 * time.minute
const smoke_ticks = '600'
const muted = ['--no-sound', '--volume', '0']
const standard_resolution = ['--res', '800', '600']
// The default course and seed after 600 ticks under the pinned V3 toolchain.
const baseline = {
	'checksum':                      '490efd84cf12692f'
	'render_instances':              '180'
	'render_checksum':               'c24e7880e15b4f35'
	'course_vertices':               '9152'
	'course_checksum':               'e1b047594b88bcb3'
	'course_fill_vertices':          '10560'
	'course_fill_checksum':          'de699b72a44f7744'
	'course_backward_vertices':      '9152'
	'course_backward_checksum':      '9f0a33dc89dd13eb'
	'course_backward_fill_vertices': '10368'
	'course_backward_fill_checksum': 'cf2b2d1d58c1a64b'
	'compute_checksum':              '3df697f628fcafc9'
}

struct Gate {
	root     string
	work     string
	compiler string
	env      map[string]string
}

fn (gate Gate) run(program string, args []string) !string {
	return testrun.capture(program, args, gate.root, gate.env, gate_timeout)!.stdout
}

fn (gate Gate) script(name string, args []string) ! {
	mut command := ['run', 'scripts/${name}.vsh']
	command << args
	print(gate.run(gate.compiler, command)!)
}

fn (gate Gate) compile(args []string) ! {
	mut command := ['--', gate.compiler]
	command << args
	gate.script('check_compiler_diagnostics', command)!
}

fn check_sources(root string) ! {
	for removed in ['game', 'util/gl', 'util/usdl', 'thirdparty/glad', '.gitmodules', 'submodule',
		'thirdparty/bulletml'] {
		if os.exists(os.join_path(root, removed)) {
			return error('Inactive legacy path returned: ${removed}')
		}
	}
	mut paths := [os.join_path(root, 'v.mod'), os.join_path(root, 'torus_trooper.v')]
	for folder in ['runtime', 'sim'] {
		paths << os.walk_ext(os.join_path(root, folder), '')
	}
	for path in paths {
		for index, source in os.read_lines(path)! {
			line := source.to_lower_ascii()
			mut start := 0
			mut legacy_word := false
			for end in 0 .. line.len + 1 {
				if end < line.len && (line[end].is_alnum() || line[end] == `_`) {
					continue
				}
				if line[start..end] in ['sdl', 'sdl2', 'vgl'] {
					legacy_word = true
					break
				}
				start = end + 1
			}
			if legacy_word || (line.contains('#flag')
				&& line.all_after('#flag').fields().any(it in ['-lgl', '-lopengl'])) {
				return error('SDL, VGL or OpenGL returned at ${path}:${index + 1}: ${source}')
			}
		}
	}
}

fn read_fields(output string) map[string]string {
	mut fields := map[string]string{}
	for line in output.split_into_lines() {
		key, value := line.split_once('=') or { continue }
		fields[key] = value
	}
	return fields
}

fn match_fields(actual map[string]string, expected map[string]string) ! {
	for name, value in expected {
		if actual[name] != value {
			return error('Expected ${name}=${value}, got ${actual[name]}')
		}
	}
}

fn positive(fields map[string]string, name string) ! {
	if strconv.atoi(fields[name])! <= 0 {
		return error('Expected a positive ${name}, got ${fields[name]}')
	}
}

fn (gate Gate) headless(binary string, extra []string) !map[string]string {
	mut command := ['--headless', '--ticks', smoke_ticks]
	command << extra
	command << muted
	output := gate.run(binary, command)!
	print(output)
	return read_fields(output)
}

fn (gate Gate) opencl() ! {
	binary := os.join_path(gate.work, 'torus_trooper_opencl')
	gate.compile(['-d', 'opencl_compute', '-cc', 'gcc', '-o', binary, '.'])!
	actual := gate.headless(binary, ['--compute', 'opencl'])!
	match_fields(actual, {
		'checksum':                            baseline['checksum']
		'compute_active':                      'opencl'
		'compute_particle_mismatched_batches': '0'
		'compute_shot_mismatched_batches':     '0'
		'compute_enemy_mismatched_batches':    '0'
		'compute_checksum':                    baseline['compute_checksum']
	})!
	positive(actual, 'compute_verified_batches')!
	fallback := strconv.atoi(actual['compute_fallback_batches'])!
	if fallback != strconv.atoi(actual['compute_mismatched_batches'])!
		|| fallback != strconv.atoi(actual['compute_bullet_mismatched_batches'])! {
		return error('Unexpected OpenCL fallback outside the affected bullet batches')
	}
	println('OpenCL verified ${actual['compute_verified_batches']} batches with ${fallback} checked fallbacks.')
	dynamic := os.join_path(gate.work, 'torus_trooper_opencl_dynamic')
	gate.compile(['-d', 'opencl_compute', '-d', 'opencl_dynamic', '-cc', 'gcc', '-o', dynamic,
		'.'])!
	gate.script('test_opencl_runtime', [dynamic, '--require-opencl'])!
}

fn require_text(output string, expected string) ! {
	if !output.contains(expected) {
		return error('Missing ${expected}\n${output}')
	}
}

fn check_allocator(output string) ! {
	for line in output.split_into_lines() {
		if line.starts_with('Vulkan allocator: ') {
			parts := line['Vulkan allocator: '.len..].fields()
			if parts.len >= 2 && parts[0].starts_with('blocks=') && parts[1] == 'allocations=3'
				&& strconv.atoi(parts[0].all_after('='))! > 0 {
				return
			}
		}
	}
	return error('Missing GPU allocator startup receipt\n${output}')
}

fn (gate Gate) rendering(binary string) ! {
	mut args := muted.clone()
	args << standard_resolution
	mut probe := args.clone()
	probe << ['--reverse', '--brightness', '70', '--luminosity', '40', '--probe']
	explicit_output := gate.run(binary, probe)!
	print(explicit_output)
	check_allocator(explicit_output)!
	mut launch := ['run', '.']
	launch << args
	launch << '--probe'
	output := gate.run(gate.compiler, launch)!
	require_text(output, 'GLFW: Vulkan surface creation succeeded')!
	check_allocator(output)!
	mut invalid := muted.clone()
	invalid << ['--res', '0', '600', '--probe']
	result := testrun.capture_status(binary, invalid, gate.root, gate.env, gate_timeout)!
	if result.exit_code != 2 {
		return error('Invalid resolution returned ${result.exit_code}, expected 2')
	}
	require_text(result.stdout + result.stderr, 'resolution width and height must be positive')!
}

fn (gate Gate) visual(binary string) ! {
	timeout := os.find_abs_path_of_executable('timeout')!
	// Let the actual effects scene run for 16 seconds and request Ctrl-C shutdown.
	mut args := ['--signal=INT', '--kill-after=3s', '16s', binary]
	args << muted
	args << '--test-effects'
	effects := testrun.capture_status(timeout, args, gate.root, gate.env, gate_timeout)!
	print(effects.stdout)
	eprint(effects.stderr)
	if effects.exit_code !in [0, 124] {
		return error('Effects scene exited with status ${effects.exit_code}')
	}
	mut tuning := muted.clone()
	tuning << ['--res', '1000', '700', '--test-object-tuning', '--data-file',
		os.join_path(gate.work, 'tuning-player.json'), '--object-sizes-file',
		os.join_path(gate.work, 'object-sizes.json')]
	output := gate.run(binary, tuning)!
	require_text(output, 'TUNE opened.')!
	require_text(output, 'simulation ticks=0')!
}

fn run(args []string) ! {
	if args in [['--help'], ['-h']] {
		println('Usage: xvfb-run -a v run scripts/check.vsh')
		return
	}
	if args.len != 0 {
		return error('Usage: v run scripts/check.vsh')
	}
	root := os.dir(@DIR)
	work := testrun.temporary_directory('torus-check-')!
	defer { os.rmdir_all(work) or {} }
	gate := Gate{ root: root, work: work, compiler: @VEXE, env: os.environ() }
	gate.script('check_guide_links', [])!
	check_sources(root)!
	gate.compile(['-cc', 'gcc', 'test', 'torus_trooper_test.v'])!
	gate.compile(['-cc', 'gcc', 'test', 'font5x7', 'sim', 'runtime'])!
	binary := os.join_path(work, 'torus_trooper')
	gate.compile(['-cc', 'gcc', '-o', binary, '.'])!
	linkage := gate.run(os.find_abs_path_of_executable('ldd')!, [binary])!
	libraries := linkage.to_lower_ascii()
	if ['libsdl', 'libopengl', 'libglx', 'libgl.'].any(libraries.contains(it)) {
		return error('SDL or OpenGL returned to the native runtime linkage\n${linkage}')
	}
	match_fields(gate.headless(binary, [])!, baseline)!
	fallback := gate.headless(binary, ['--compute', 'opencl'])!
	match_fields(fallback, {
		'checksum':          baseline['checksum']
		'compute_requested': 'opencl'
		'compute_active':    'cpu'
		'compute_checksum':  baseline['compute_checksum']
	})!
	positive(fallback, 'compute_fallback_batches')!
	if gate.env['TT_OPENCL_SMOKE'] == '1' {
		gate.opencl()!
	}
	gate.rendering(binary)!
	if gate.env['TT_VISUAL_SMOKE'] == '1' {
		gate.visual(binary)!
	}
	if gate.env['TT_REPLAY_UI_SMOKE'] == '1' {
		gate.script('test_replay_ui', [binary])!
	}
	println('Repository verification passed.')
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
