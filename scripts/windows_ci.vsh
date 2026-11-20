// Provision Windows CI tools and run the Windows build and runtime checks.
import compress.szip
import os
import rand
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
	// The Windows PATH resolver probes extensions even on an absolute path.
	program := if os.is_abs_path(name) {
		name
	} else {
		os.find_abs_path_of_executable(name) or { return error('Cannot find ${name}') }
	}
	if !os.is_file(program) {
		return error('Cannot find executable: ${program}')
	}
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

fn add_path(directory string) ! {
	if !os.is_dir(directory) || directory.contains_any('\r\n') {
		return error('Invalid runner PATH directory: ${directory}')
	}
	mut output := os.open_append(required('GITHUB_PATH')!)!
	defer { output.close() }
	output.writeln(os.abs_path(directory))!
}

fn download_verified(url string, hash string, destination string, env map[string]string) ! {
	if hash.len != 64 || !hash.bytes().all(it.is_hex_digit()) {
		return error('Invalid SHA-256 pin for ${url}')
	}
	command('curl.exe', ['--fail', '--silent', '--show-error', '--location', '--retry', '3',
		'--output', destination, '--', url], env)!
	if releaseconsumer.file_sha256(destination)! != hash.to_lower_ascii() {
		return error('Checksum mismatch: ${url}')
	}
}

fn tool_staging(temporary string, name string) !string {
	// Stage beside the final destination so Windows can rename across directories.
	path := os.join_path(temporary, name + rand.uuid_v4())
	os.mkdir(path, mode: 0o700)!
	return path
}

fn install_clang(temporary string, env map[string]string) ! {
	layout := required('CLANG_DIRECTORY')!
	if os.file_name(layout) != layout || layout in ['.', '..'] {
		return error('Invalid Clang archive directory: ${layout}')
	}
	destination := os.join_path(temporary, 'llvm-mingw')
	if os.exists(destination) || os.is_link(destination) {
		return error('Clang destination already exists: ${destination}')
	}
	work := tool_staging(temporary, 'torus-clang-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	archive := os.join_path(work, 'llvm-mingw.zip')
	download_verified(required('CLANG_URL')!, required('CLANG_SHA256')!, archive, env)!
	extracted := os.join_path(work, 'extracted')
	os.mkdir(extracted)!
	// Stream the checksum-verified vendor ZIP. Its expanded size exceeds the
	// intentionally small limit for game release archives.
	if !szip.extract_zip_to_dir(archive, extracted)! {
		return error('Could not extract the verified Clang archive')
	}
	if !os.is_file(os.join_path(extracted, layout, 'bin', 'clang.exe')) {
		return error('The Clang archive is missing ${layout}/bin/clang.exe')
	}
	os.rename_dir(extracted, destination)!
	add_path(os.join_path(destination, layout, 'bin'))!
}

fn install_shader_tools(temporary string, env map[string]string) ! {
	version := required('SHADER_SDK_VERSION')!
	work := tool_staging(temporary, 'torus-shader-sdk-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	installer := os.join_path(work, 'shader-sdk.exe')
	url := 'https://sdk.lunarg.com/sdk/download/${version}/windows/vulkansdk-windows-X64-${version}.exe'
	destination := os.join_path(temporary, 'shader-sdk')
	if os.exists(destination) || os.is_link(destination) {
		return error('Shader SDK destination already exists: ${destination}')
	}
	download_verified(url, required('SHADER_SDK_SHA256')!, installer, env)!
	mut installed := false
	defer {
		if !installed && os.is_dir(destination) {
			os.rmdir_all(destination) or { eprintln(err) }
		}
	}
	command(installer, ['--root', destination, '--accept-licenses', '--default-answer',
		'--confirm-command', 'install', 'copy_only=1'], env)!
	bin := os.join_path(destination, 'Bin')
	if !os.is_file(os.join_path(bin, 'glslangValidator.exe'))
		&& !os.is_file(os.join_path(bin, 'glslang.exe')) {
		return error('The shader tools SDK does not contain glslang')
	}
	if !os.is_file(os.join_path(bin, 'spirv-val.exe')) {
		return error('The shader tools SDK does not contain spirv-val')
	}
	add_path(bin)!
	installed = true
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
			'clang' {
				install_clang(required('RUNNER_TEMP')!, env)!
			}
			'compiler-path' {
				directory := os.abs_path('toolchain/v')
				if !os.is_file(os.join_path(directory, 'v.exe')) {
					return error('The pinned compiler is missing from ${directory}')
				}
				add_path(directory)!
			}
			'shader-tools' {
				install_shader_tools(required('RUNNER_TEMP')!, env)!
			}
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
