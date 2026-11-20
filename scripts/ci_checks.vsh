// Run the repository checks used by the Linux CI lane and shared dependency gate.
import os
import scripts.testrun
import time

const validation_layer = 'VK_LAYER_KHRONOS_validation'
const validation_log = 'validation.log'
const validation_seconds = 3 // Exercise effects for a few rendered seconds.
const termination_grace_seconds = 2
const smoke_ticks = '120'
const invalid_diagnostics = ['validation error', 'vuid-', 'segmentation', 'assert', 'fatal']
const muted = ['--no-sound', '--volume', '0']
const game = './torus_trooper'

fn launch(program string, args []string, environment map[string]string) ! {
	path := os.find_abs_path_of_executable(program) or { return error('Cannot find ${program}') }
	mut child := os.new_process(path)
	defer { child.close() }
	child.set_args(args)
	child.set_environment(environment)
	child.run()
	child.wait()
	if child.code != 0 {
		return error('${program} exited with status ${child.code}')
	}
}

fn script(name string, args []string, environment map[string]string) ! {
	mut command := ['run', 'scripts/${name}.vsh']
	command << args
	$if windows {
		launch('v.exe', command, environment)!
	} $else {
		launch(@VEXE, command, environment)!
	}
}

fn compile(args []string, environment map[string]string) ! {
	mut command := ['--', @VEXE]
	command << args
	script('check_compiler_diagnostics', command, environment)!
}

fn bootstrap(environment map[string]string) ! {
	output := os.getenv('GITHUB_PATH')
	if output == '' {
		return error('Set GITHUB_PATH to the runner path file')
	}
	// V run exports the bootstrap compiler. Direct make to its own checkout
	// and skip problem matcher registration from paths the runner cannot access.
	mut env := environment.clone()
	env.delete('VEXE')
	env.delete('GITHUB_JOB')
	launch('make', ['-C', 'toolchain/v', 'local=1', 'VEXE=./v'], env)!
	mut path := os.open_append(output)!
	defer { path.close() }
	path.writeln(os.abs_path('toolchain/v'))!
}

fn linux_setup(environment map[string]string) ! {
	temporary := os.getenv('RUNNER_TEMP')
	if temporary == '' {
		return error('Set RUNNER_TEMP to the runner temporary directory')
	}
	mut env := environment.clone()
	env.delete('VEXE')
	env['PATH'] = '/usr/bin:/bin'
	env['TT_V3_TOOLCHAIN_DIR'] = os.join_path(temporary, 'Linux toolchain with spaces')
	// Exercise the public entry point on PATH with no installed V compiler.
	launch('/bin/sh', ['scripts/build_linux_v3.sh'], env)!
}

fn startup(environment map[string]string) ! {
	temporary := os.getenv('RUNNER_TEMP')
	if temporary == '' {
		return error('Set RUNNER_TEMP to the runner temporary directory')
	}
	check := os.join_path(temporary, 'window-startup-check')
	launch(@VEXE, ['-cc', 'tcc', '-o', check, 'tests/window_startup.v'], environment)!
	launch(check, [os.abs_path(game), os.join_path(temporary, 'window-startup-logs'), '--probe',
		'--window', '--compute', 'cpu', '--no-sound', '--volume', '0', '--data-file',
		os.join_path(temporary,
			'startup-player.cfg')], environment)!
}

fn validation_smoke(environment map[string]string) ! {
	mut env := environment.clone()
	env['VK_INSTANCE_LAYERS'] = validation_layer
	timer := os.find_abs_path_of_executable('timeout')!
	mut args := ['--signal=INT', '--kill-after=${termination_grace_seconds}s',
		'${validation_seconds}s', 'xvfb-run', '-a', game]
	args << muted
	args << '--test-effects'
	result := testrun.capture_status(timer, args, os.getwd(), env, 20 * time.second)!
	output := result.stdout + result.stderr
	os.write_file(validation_log, output)!
	print(output)
	if result.exit_code !in [0, 124] {
		return error('Vulkan validation smoke exited with status ${result.exit_code}')
	}
	if invalid_diagnostics.any(output.to_lower_ascii().contains(it)) {
		return error('Vulkan validation smoke reported a runtime error, see ${validation_log}')
	}
}

fn profiling(environment map[string]string) ! {
	mut env := environment.clone()
	env['VK_INSTANCE_LAYERS'] = validation_layer
	prefix := ['-a', @VEXE, 'run']
	mut args := prefix.clone()
	args << ['scripts/benchmark_renderer.vsh', game, '--runs', '1', '--seconds', '1', '--output',
		'gpu-profile.json']
	launch('xvfb-run', args, env)!
	args = prefix.clone()
	args << ['scripts/benchmark_pipeline_cache.vsh', game, '--runs', '1', '--output',
		'cache-profile.json']
	launch('xvfb-run', args, env)!
	args = prefix.clone()
	args << ['scripts/test_pipeline_cache.vsh', game]
	launch('xvfb-run', args, env)!
}

fn opencl_tinycc(environment map[string]string) ! {
	static_binary := 'torus_trooper_opencl_tcc'
	dynamic_binary := 'torus_trooper_opencl_dynamic_tcc'
	compile(['-d', 'opencl_compute', '-cc', 'tcc', '-o', static_binary, '.'], environment)!
	result := testrun.capture(os.abs_path(static_binary), ['--headless', '--ticks', smoke_ticks,
		'--compute', 'opencl'], os.getwd(), environment, time.minute)!
	if !result.stdout.contains('compute_active=opencl') {
		return error('TinyCC smoke did not activate OpenCL\n${result.stdout}')
	}
	println('compute_active=opencl')
	compile(['-d', 'opencl_compute', '-d', 'opencl_dynamic', '-cc', 'tcc', '-o', dynamic_binary,
		'.'], environment)!
	script('test_opencl_runtime', ['./' + dynamic_binary, '--require-opencl'], environment)!
}

fn main() {
	gate := os.args[1] or { '' }
	if os.args.len != 2 {
		eprintln('Pass one CI check name')
		exit(2)
	}
	run(gate) or {
		eprintln(err)
		exit(1)
	}
}

fn run(gate string) ! {
	env := os.environ()
	match gate {
		'bootstrap' {
			bootstrap(env)!
		}
		'dependency-graph' {
			script('check_installed_deps', [], env)!
			script('compatibility', ['--modules', 'modules'], env)!
		}
		'linux-dependencies' {
			launch('sudo', ['apt-get', 'update'], env)!
			launch('sudo', ['apt-get', 'install', '-y', 'libasound2-dev', 'libglfw3-dev',
				'libvulkan-dev', 'libvulkan-volk-dev', 'mesa-vulkan-drivers',
				'vulkan-validationlayers', 'xvfb', 'xdotool', 'x11-utils', 'bubblewrap', 'patchelf',
				'libxxf86vm1', 'libx11-xcb1', 'ocl-icd-opencl-dev', 'pocl-opencl-icd',
				'glslang-tools', 'spirv-tools', 'libx11-dev', 'openbox', 'xauth'], env)!
		}
		'shaders' {
			script('check_compiler_diagnostics', ['--self-test'], env)!
			script('build_shaders', ['--self-test'], env)!
			script('build_shaders', [], env)!
		}
		'linux-tests' {
			compile(['-cc', 'gcc', 'test', 'torus_trooper_test.v'], env)!
			compile(['-cc', 'gcc', 'test', 'font5x7', 'sim', 'runtime'], env)!
		}
		'linux-startup' {
			startup(env)!
		}
		'linux-setup' {
			linux_setup(env)!
		}
		'vulkan-validation' {
			validation_smoke(env)!
		}
		'profiling' {
			profiling(env)!
		}
		'tinycc' {
			compile(['-cc', 'tcc', '-o', 'torus_trooper_tcc', '.'], env)!
			launch('./torus_trooper_tcc', ['--headless', '--ticks', smoke_ticks], env)!
		}
		'opencl-tinycc' {
			opencl_tinycc(env)!
		}
		else {
			return error('Unknown CI check: ${gate}')
		}
	}
}
