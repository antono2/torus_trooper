// Compile and validate every game shader before publishing the first binary.
import flag
import os
import rand
import strconv

fn shader_tool(name string) !string {
	path := os.find_abs_path_of_executable(name) or { '' }
	if path != '' {
		return path
	}
	sdk := os.getenv('VULKAN_SDK')
	tool_filename := if os.user_os() == 'windows' { name + '.exe' } else { name }
	if sdk != '' {
		for directory in ['bin', 'Bin'] {
			candidate := os.join_path(sdk, directory, tool_filename)
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
	compiler := shader_tool('glslangValidator') or { shader_tool('glslang')! }
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

fn test_render_constants(root string) ! {
	mut gpu := map[string]f64{}
	for line in os.read_lines(os.join_path(root, 'shaders', 'render_codes.glsl'))! {
		if line.starts_with('const float ') {
			name, value := line.trim_string_left('const float ').split_once(' = ') or {
				return error('invalid shader constant: ${line}')
			}
			gpu[name] = strconv.atof64(value.trim_string_right(';'))!
		}
	}
	for file, prefix in {
		'render_codes.v': 'render_'
		'course.v':       'course_'
	} {
		mut count := 0
		for line in os.read_lines(os.join_path(root, 'sim', file))! {
			if !line.starts_with('const ' + prefix) {
				continue
			}
			name, assignment := line.trim_string_left('const ').split_once(' = ') or { continue }
			if file == 'course.v' && !name.ends_with('_brightness_base') {
				continue
			}
			if !assignment.starts_with('f32(') || !assignment.ends_with(')') {
				return error('${name} must declare a numeric render constant')
			}
			value := strconv.atof64(assignment[4..assignment.len - 1])!
			expected := gpu[name] or { return error('missing GLSL constant ${name}') }
			if value != expected {
				return error('CPU and GLSL values differ for ${name}: ${value} and ${expected}')
			}
			count++
		}
		if count == 0 {
			return error('no CPU render constants in ${file}')
		}
	}
}

fn test_menu_ids(root string) ! {
	mut ids := map[string]int{}
	menu := os.read_file(os.join_path(root, 'runtime', 'menu.v'))!
	_, declaration := menu.split_once('enum TitleMenuItem {') or {
		return error('missing TitleMenuItem')
	}
	for line in declaration.all_before('}').split_into_lines() {
		name, value := line.trim_space().split_once(' = ') or { continue }
		ids[name.to_upper()] = strconv.atoi(value)!
	}
	mut shader_ids := map[string]int{}
	for line in os.read_lines(os.join_path(root, 'shaders', 'hud_state.h'))! {
		if line.starts_with('#define TT_MENU_') {
			fields := line.trim_string_left('#define TT_MENU_').fields()
			if fields.len < 2 {
				return error('invalid shader menu ID: ${line}')
			}
			shader_ids[fields[0]] = strconv.atoi(fields[1])!
		}
	}
	// The HUD exposes eight title-menu actions through its shared CPU/GPU protocol.
	if ids.len != 8 || ids != shader_ids {
		return error('CPU and shader title-menu IDs differ')
	}
}

fn run_cli() ! {
	mut parser := flag.new_flag_parser(os.args[1..])
	parser.application('build_shaders')
	parser.description('Compile and validate the Torus Trooper shaders.')
	root := os.dir(@DIR)
	source := os.join_path(root, 'shaders')
	output := parser.string('output-dir', 0, source, 'directory for the compiled shaders')
	self_test := parser.bool('self-test', 0, false,
		'verify shader protocol constants and failure preservation')
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
		test_render_constants(root)!
		test_menu_ids(root)!
		test_failed_build(staging)!
	} else {
		build_shaders(source, output, staging)!
	}
}

run_cli() or {
	eprintln('Shader build failed: ${err}')
	exit(1)
}
