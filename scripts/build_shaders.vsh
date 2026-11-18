// Compile and validate every game shader before publishing the first binary.
import flag
import os
import rand

fn shader_tool(name string) !string {
	path := os.find_abs_path_of_executable(name) or { '' }
	if path != '' {
		return path
	}
	sdk := os.getenv('VULKAN_SDK')
	executable := if os.user_os() == 'windows' { name + '.exe' } else { name }
	if sdk != '' {
		for directory in ['bin', 'Bin'] {
			candidate := os.join_path(sdk, directory, executable)
			if os.is_file(candidate) && os.is_executable(candidate) {
				return os.abs_path(candidate)
			}
		}
	}
	return error('${name} was not found. Install glslang and SPIR-V tools or the Vulkan SDK.')
}

fn check_command(path string, args []string) ! {
	mut command := os.new_process(path)
	command.set_args(args)
	command.run()
	command.wait()
	status := command.code
	command.close()
	if status != 0 {
		return error('Shader command failed (${status}): ${path} ${args.join(' ')}')
	}
}

fn build_shaders(source_directory string, output_directory string, staging string) ! {
	compiler := shader_tool('glslangValidator')!
	validator := shader_tool('spirv-val')!
	sources :=
		os.ls(source_directory)!.filter(it.ends_with('.vert') || it.ends_with('.frag')).sorted()
	if sources.len == 0 {
		return error('No shader sources found in ${source_directory}')
	}
	for name in sources {
		source := os.join_path(source_directory, name)
		binary := os.join_path(staging, name + '.spv')
		check_command(compiler, ['-V', source, '-o', binary])!
		check_command(validator, [binary])!
	}
	os.mkdir_all(output_directory)!
	for name in sources {
		binary := name + '.spv'
		os.cp(os.join_path(staging, binary), os.join_path(output_directory, binary))!
	}
	println('Compiled and validated ${sources.len} shaders')
}

fn test_failed_build(staging string) ! {
	source := os.join_path(staging, 'source with spaces')
	output := os.join_path(staging, 'output')
	os.mkdir(source)!
	os.mkdir(output)!
	os.write_file(os.join_path(source, 'a-first.vert'),
		'#version 450\nvoid main() { gl_Position = vec4(0); }\n')!
	os.write_file(os.join_path(source, 'z-last.frag'), '#version 450\ninvalid shader\n')!
	existing := os.join_path(output, 'a-first.vert.spv')
	before := 'previous shader binary'
	os.write_file(existing, before)!
	mut failed := false
	build_shaders(source, output, staging) or {
		if !err.msg().contains('z-last.frag') {
			return err
		}
		failed = true
	}
	assert failed
	assert os.read_file(existing)! == before
	assert os.ls(output)! == ['a-first.vert.spv']
	println('A late shader compilation failure preserved all outputs.')
}

fn run_cli() ! {
	mut parser := flag.new_flag_parser(os.args[1..])
	parser.application('build_shaders')
	parser.description('Compile and validate the Torus Trooper shaders.')
	source := os.join_path(os.dir(@DIR), 'shaders')
	output := parser.string('output-dir', 0, source, 'directory for the compiled shaders')
	self_test := parser.bool('self-test', 0, false,
		'verify failure preservation with temporary fixtures')
	if parser.bool('help', `h`, false, 'show help') {
		println(parser.usage())
		return
	}
	if parser.finalize()!.len != 0 {
		return error('unexpected positional arguments')
	}
	staging := os.join_path(os.temp_dir(), 'torus-shaders-' + rand.uuid_v4())
	os.mkdir(staging)!
	defer { os.rmdir_all(staging) or {} }
	if self_test {
		test_failed_build(staging)!
	} else {
		build_shaders(source, output, staging)!
	}
}

run_cli() or {
	eprintln('Shader build failed: ${err}')
	exit(1)
}
