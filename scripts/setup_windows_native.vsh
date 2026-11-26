// Stage the pinned SDK and build GLFW after the Windows compiler bootstrap.
import flag
import os
import scripts.compatpins
import scripts.windowsbuild

fn command(program string, args []string) ! {
	mut child := os.new_process(os.find_abs_path_of_executable(program)!)
	defer { child.close() }
	child.set_args(args)
	child.run()
	child.wait()
	if child.code != 0 {
		return error('${program} failed with exit status ${child.code}')
	}
}

fn prepare(cache string, sdk string) ! {
	include_dir := os.join_path(cache, 'sdk', 'Include')
	library_dir := os.join_path(cache, 'sdk', 'Lib')
	os.mkdir_all(os.join_path(include_dir, 'volk'))!
	os.mkdir_all(library_dir)!
	for name in ['vulkan', 'vk_video'] {
		os.cp_all(os.join_path(cache, 'Vulkan-Headers', 'include', name),
			os.join_path(include_dir, name), true)!
	}
	for name in ['volk.h', 'volk.c'] {
		os.cp(os.join_path(cache, 'volk', name), os.join_path(include_dir, 'volk', name))!
	}
	source_library := os.join_path(sdk, 'Lib', 'vulkan-1.lib')
	staged_library := os.join_path(library_dir, 'vulkan-1.lib')
	if os.real_path(source_library).to_lower_ascii() != os.real_path(staged_library).to_lower_ascii() {
		os.cp(source_library, staged_library)!
	}
	os.setenv('VULKAN_SDK', os.join_path(cache, 'sdk'), true)
	install := os.join_path(cache, 'glfw-install')
	build := os.join_path(cache, 'glfw-build')
	command('cmake', ['-S', os.join_path(cache, 'glfw'), '-B', build, '-G', 'Ninja',
		'-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_C_COMPILER=clang', '-DCMAKE_INSTALL_PREFIX=${install}',
		'-DBUILD_SHARED_LIBS=OFF', '-DGLFW_BUILD_EXAMPLES=OFF', '-DGLFW_BUILD_TESTS=OFF',
		'-DGLFW_BUILD_DOCS=OFF'])!
	command('cmake', ['--build', build, '--parallel'])!
	command('cmake', ['--install', build])!
	os.setenv('GLFW_INCLUDE', os.join_path(install, 'include'), true)
	os.setenv('GLFW_LIB', os.join_path(install, 'lib'), true)
}

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('setup_windows_native')
	parser.description('Stage Vulkan headers and prepare GLFW using the bootstrapped Windows toolchain.')
	cache := parser.string('cache', 0, '', 'toolchain cache prepared by setup_windows.ps1')
	sdk := parser.string('sdk', 0, '', 'installed Vulkan SDK containing Lib/vulkan-1.lib')
	output := parser.string('output', 0, 'torus_trooper.exe', 'output game executable')
	prepare_only := parser.bool('prepare-only', 0, false, 'prepare native dependencies without building the game')
	verify := parser.bool('verify', 0, false, 'verify the game build and rendering')
	if parser.bool('help', `h`, false, 'show help') {
		println(parser.usage())
		return
	}
	if parser.finalize()!.len != 0 || cache == '' || sdk == '' {
		return error(parser.usage())
	}
	root := os.dir(@DIR)
	compatpins.resolve(root, platform: 'windows')!
	prepare(os.abs_path(cache), os.abs_path(sdk))!
	println('Prepared Windows toolchain: ${cache}')
	if !prepare_only {
		windowsbuild.build(root, output, verify, os.environ())!
	}
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
