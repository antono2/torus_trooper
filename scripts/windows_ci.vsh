// Run Windows CI checks once the compiler and platform SDK are available.
import os
import scripts.releaseconsumer
import scripts.testrun
import scripts.windowsbuild
import time

const installed_glfw = 'glfw3:x64-mingw-static'
const candidate = 'torus_trooper.exe'

fn required(name string) !string {
	value := os.getenv(name)
	if value == '' {
		return error('Set ${name} for this Windows CI check')
	}
	return value
}

fn command(name string, args []string, env map[string]string) ! {
	program := os.find_abs_path_of_executable(name) or { return error('Cannot find ${name}') }
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_environment(env)
	child.run()
	child.wait()
	if child.code != 0 {
		return error('${name} exited with status ${child.code}')
	}
}

fn script(name string, args []string, env map[string]string) ! {
	mut command_args := ['run', 'scripts/${name}.vsh']
	command_args << args
	command('v.exe', command_args, env)!
}

fn copy_contents(source string, destination string) ! {
	os.mkdir_all(destination)!
	for name in os.ls(source)! {
		os.cp_all(os.join_path(source, name), os.join_path(destination, name), true)!
	}
}

fn sdk_headers() ! {
	include_dir := os.join_path(required('VULKAN_SDK')!, 'Include')
	for name in ['vulkan', 'vk_video'] {
		copy_contents(os.join_path('dependencies', 'Vulkan-Headers', 'include', name), os.join_path(include_dir,
			name))!
	}
	volk := os.join_path(include_dir, 'volk')
	os.mkdir_all(volk)!
	for name in ['volk.h', 'volk.c'] {
		os.cp(os.join_path('dependencies', 'volk', name), os.join_path(volk, name))!
	}
}

fn native_cache(env map[string]string) ! {
	root := required('VCPKG_INSTALLATION_ROOT')!
	path := required('GITHUB_OUTPUT')!
	temporary := required('RUNNER_TEMP')!
	git := os.find_abs_path_of_executable('git')!
	commit :=
		testrun.capture(git, ['-C', root, 'rev-parse', 'HEAD'], os.getwd(), env, time.minute)!.stdout.trim_space()
	if commit.len != 40 || !commit.bytes().all(it.is_hex_digit()) {
		return error('Cannot identify the vcpkg ports revision')
	}
	os.mkdir_all(os.join_path(temporary, 'vcpkg-binary-cache'))!
	mut output := os.open_append(path)!
	defer { output.close() }
	output.writeln('commit=${commit}')!
}

fn opencl_headers(temporary string, env map[string]string) ! {
	module_path := os.join_path('modules', 'antono2', 'opencl')
	revision := os.read_file(os.join_path(module_path, 'HEADERS_COMMIT'))!.trim_space()
	if revision.len != 40 || !revision.bytes().all(it.is_hex_digit()) {
		return error('Invalid OpenCL header revision')
	}
	root := os.join_path(temporary, 'opencl-headers')
	command('git', ['init', root], env)!
	command('git', ['-C', root, 'fetch', '--depth', '1',
		'https://github.com/KhronosGroup/OpenCL-Headers.git', revision], env)!
	command('git', ['-C', root, 'checkout', '--detach', 'FETCH_HEAD'], env)!
	copy_contents(os.join_path(root, 'CL'), os.join_path(module_path, 'include', 'CL'))!
}

fn runtime_check(kind string, temporary string, environment map[string]string) ! {
	env := windowsbuild.with_glfw(environment)!
	opencl := kind == 'opencl'
	mut flags := ['--', 'v.exe', '-subsystem', 'console']
	flags << windowsbuild.compiler_flags
	if opencl {
		opencl_headers(temporary, env)!
		flags << ['-d', 'opencl_compute', '-d', 'opencl_dynamic']
	}
	binary := os.join_path(temporary, if opencl {
		'torus-opencl-dynamic.exe'
	} else {
		'torus-cache-probe.exe'
	})
	flags << ['-o', binary, '.']
	script('check_compiler_diagnostics', flags, env)!
	script(if opencl { 'test_opencl_runtime' } else { 'test_pipeline_cache' }, [
		binary,
	], env)!
}

fn package_and_probe(archive string, temporary string, env map[string]string) ! {
	script('package_windows', [archive, os.join_path(temporary, candidate)], env)!
	work := testrun.temporary_directory('torus-windows-package-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	releaseconsumer.extract(os.abs_path(archive), work)!
	directory := os.join_path(work, 'torus-trooper')
	windowsbuild.probe(os.join_path(directory, candidate), directory, env)!
}

fn run(args []string) ! {
	env := os.environ()
	if args.len == 1 {
		match args[0] {
			'sdk-headers' {
				sdk_headers()!
			}
			'native-cache' {
				native_cache(env)!
			}
			'glfw' {
				command('vcpkg', ['install', installed_glfw], env)!
			}
			'build' {
				windowsbuild.build(os.getwd(), os.join_path(required('RUNNER_TEMP')!, candidate),
					true, env)!
			}
			'opencl', 'pipeline-cache' {
				runtime_check(args[0], required('RUNNER_TEMP')!, env)!
			}
			else {
				return error('Unknown Windows CI check: ${args[0]}')
			}
		}

		return
	}
	if args.len == 2 && args[0] == 'package' {
		package_and_probe(args[1], required('RUNNER_TEMP')!, env)!
		return
	}
	return error('Pass a Windows CI check name and its arguments')
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
