// Build and verify the Windows game with the MinGW GLFW and Vulkan SDK layout.
module windowsbuild

import os
import scripts.testrun
import time

pub const compiler_flags = ['-cc', 'clang', '-cflags', '-Wno-incompatible-pointer-types']
const smoke_timeout = 2 * time.minute
const headless_ticks = '600'

fn run(binary string, args []string, root string, env map[string]string) ! {
	mut child := os.new_process(binary)
	defer { child.close() }
	child.set_args(args)
	child.set_work_folder(root)
	child.set_environment(env)
	child.run()
	child.wait()
	if child.code != 0 {
		return error('${binary} exited with status ${child.code}')
	}
}

fn valid_glfw(include_dir string, library_dir string) bool {
	return include_dir != '' && library_dir != ''
		&& os.is_file(os.join_path(include_dir, 'GLFW', 'glfw3.h'))
		&& os.is_file(os.join_path(library_dir, 'libglfw3.a'))
}

pub fn with_glfw(env map[string]string) !map[string]string {
	mut result := env.clone()
	include_dir := env['GLFW_INCLUDE'] or { '' }
	library_dir := env['GLFW_LIB'] or { '' }
	if valid_glfw(include_dir, library_dir) {
		return result
	}
	for root in [env['VCPKG_ROOT'] or { '' }, env['VCPKG_INSTALLATION_ROOT'] or { '' },
		os.join_path(os.home_dir(), '.cache', 'antono2', 'glfw', 'vcpkg')] {
		if root == '' {
			continue
		}
		prefix := os.join_path(root, 'installed', 'x64-mingw-static')
		include_path := os.join_path(prefix, 'include')
		library_path := os.join_path(prefix, 'lib')
		if valid_glfw(include_path, library_path) {
			result['GLFW_INCLUDE'] = include_path
			result['GLFW_LIB'] = library_path
			return result
		}
	}
	return error('MinGW GLFW 3 was not found. Set GLFW_INCLUDE and GLFW_LIB, or install glfw3:x64-mingw-static in VCPKG_ROOT.')
}

fn quoted_flag(prefix string, path string) string {
	// V forwards the quotes in C and linker flags to Clang.
	return '${prefix}"${path}"'
}

fn test_files(root string) ![]string {
	mut files := ['torus_trooper_test.v']
	for directory in ['font5x7', 'sim', 'runtime'] {
		for name in os.ls(os.join_path(root, directory))!.sorted() {
			path := os.join_path(root, directory, name)
			if name.ends_with('_test.v') && os.is_file(path) {
				files << path
			}
		}
	}
	return files
}

fn verify_tests(compiler string, diagnostic string, work string, root string, sdk string, env map[string]string) ! {
	mut flags := compiler_flags.clone()
	flags << ['-cflags', quoted_flag('-I', os.join_path(sdk, 'Include')), '-cflags',
		quoted_flag('-I', env['GLFW_INCLUDE']), '-ldflags',
		quoted_flag('-L', os.join_path(sdk,
			'Lib')), '-ldflags',
		quoted_flag('-L',
			env['GLFW_LIB'])]
	files := test_files(root)!
	for index, file in files {
		binary := os.join_path(work, 'torus-test-${index}.exe')
		mut args := ['--', compiler]
		args << flags
		args << ['-o', binary, file]
		run(diagnostic, args, root, env) or { return error('Could not compile ${file}: ${err}') }
		result := testrun.capture(binary, [], root, env, smoke_timeout) or {
			return error('Test failed: ${file}\n${err}')
		}
		print(result.stdout)
		eprint(result.stderr)
	}
	println('Windows V3 tests passed: ${files.len}')
}

pub fn probe(binary string, root string, env map[string]string) ! {
	result := testrun.capture(binary, ['--probe', '--no-sound', '--volume', '0'], root, env,
		smoke_timeout)!
	print(result.stdout)
	eprint(result.stderr)
}

pub fn build(root string, output string, verify bool, environment map[string]string) ! {
	compiler := os.find_abs_path_of_executable(if os.user_os() == 'windows' {
		'v.exe'
	} else {
		'v'
	}) or { return error('The V compiler was not found on PATH.') }
	clang := os.find_abs_path_of_executable('clang') or {
		return error('Clang with a Windows x64 MinGW target was not found on PATH.')
	}
	target :=
		testrun.capture(clang, ['-dumpmachine'], root, environment, smoke_timeout)!.stdout.trim_space()
	if !target.starts_with('x86_64-') || !(target.ends_with('windows-gnu')
		|| target.ends_with('mingw32')) {
		return error("Clang must target Windows x64 MinGW; found '${target}'.")
	}
	sdk := environment['VULKAN_SDK'] or { '' }
	if sdk == '' || !os.is_file(os.join_path(sdk, 'Include', 'vulkan', 'vulkan.h'))
		|| !os.is_file(os.join_path(sdk, 'Lib', 'vulkan-1.lib')) {
		return error('VULKAN_SDK must contain Include/vulkan/vulkan.h and Lib/vulkan-1.lib.')
	}
	env := with_glfw(environment)!
	output_path := if os.is_abs_path(output) {
		os.abs_path(output)
	} else {
		os.abs_path(os.join_path(root, output))
	}
	mut args := compiler_flags.clone()
	args << ['-o', output_path, '.']
	if verify {
		run(compiler, ['run', 'scripts/build_shaders.vsh', '--self-test'], root, env)!
		run(compiler, ['run', 'scripts/build_shaders.vsh'], root, env)!
		work := testrun.temporary_directory('torus-windows-tests-')!
		defer { os.rmdir_all(work) or { eprintln(err) } }
		diagnostic := os.join_path(work, 'check_compiler_diagnostics.exe')
		run(compiler, ['-skip-running', '-cc', 'clang', '-o', diagnostic,
			'scripts/check_compiler_diagnostics.vsh'], root, env)!
		run(diagnostic, ['--self-test'], root, env)!
		verify_tests(compiler, diagnostic, work, root, sdk, env)!
		mut checked := ['--', compiler]
		checked << args
		run(diagnostic, checked, root, env)!
		headless := testrun.capture(output_path, ['--headless', '--ticks', headless_ticks,
			'--no-sound', '--volume', '0'], root, env, smoke_timeout)!
		print(headless.stdout)
		eprint(headless.stderr)
		probe(output_path, root, env)!
	} else {
		run(compiler, args, root, env)!
	}
	println('Built Torus Trooper: ${output_path}')
	println('GLFW headers: ${env['GLFW_INCLUDE']}')
	println('GLFW library: ${env['GLFW_LIB']}')
	if verify {
		println('Windows tests, headless run and Vulkan probe passed.')
	}
}
