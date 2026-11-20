// Build the game from a configured Windows toolchain.
import flag
import os
import scripts.windowsbuild

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('build_windows')
	parser.description('Build Torus Trooper with the Windows x64 Clang and Vulkan SDK.')
	verify := parser.bool('verify', 0, false, 'run shaders, tests and smoke probes')
	output := parser.string('output', 0, 'torus_trooper.exe', 'output executable')
	if parser.bool('help', `h`, false, 'show help') {
		println(parser.usage())
		return
	}
	if parser.finalize()!.len != 0 {
		return error(parser.usage())
	}
	windowsbuild.build(os.dir(@DIR), output, verify, os.environ())!
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
