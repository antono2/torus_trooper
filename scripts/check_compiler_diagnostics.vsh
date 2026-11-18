// Stream compiler output and reject warnings or notices in maintained game sources.
import os
import regex
import time

const owned_directories = ['runtime', 'sim', 'font5x7', 'shaders']
const owned_root_files = ['torus_trooper.v', 'torus_trooper_test.v']
const poll_interval = 20 * time.millisecond

struct DiagnosticFilter {
mut:
	color   regex.RE
	seen    bool
	partial [2]string
}

fn new_filter() !DiagnosticFilter {
	return DiagnosticFilter{
		color: regex.regex_opt('\x1b\\[[0-9;]*[A-Za-z]')!
	}
}

fn is_windows_path(path string) bool {
	return path.len > 2 && path[0].is_letter() && path[1..3] == ':/'
}

fn digits(text string) bool {
	return text != '' && text.bytes().all(it.is_digit())
}

fn diagnostic_source(line string) string {
	fields := line.split(':')
	for i in 1 .. fields.len {
		severity := fields[i].trim_space().to_lower()
		if severity in ['warning', 'notice'] && i >= 2 && i < fields.len - 1
			&& digits(fields[i - 1]) {
			// V and GCC diagnostics use path:line or path:line:column.
			mut end := i - 1
			if end > 1 && digits(fields[end - 1]) {
				end--
			}
			return fields[..end].join(':')
		}
		if !severity.starts_with('warning')
			|| (severity.len > 7 && (severity[7].is_alnum() || severity[7] == `_`)) {
			continue
		}
		// MSVC uses path(line) or path(line,column). Locate the final parentheses
		// so parentheses in a checkout directory are handled normally.
		location := fields[..i].join(':').trim_right(' \t')
		if location.ends_with(')') {
			if open := location.last_index('(') {
				numbers := location[open + 1..location.len - 1].split(',')
				if numbers.len <= 2 && numbers.all(digits(it)) {
					return location[..open]
				}
			}
		}
	}
	return ''
}

fn (mut filter DiagnosticFilter) is_project_diagnostic(raw string, working_root string) bool {
	line := filter.color.replace(raw, '').trim_space()
	source := diagnostic_source(line)
	if source == '' {
		return false
	}
	mut root := working_root.replace('\\', '/').trim_right('/')
	mut path := source.replace('\\', '/')
	if !path.starts_with('/') && !is_windows_path(path) {
		path = '${root}/${path}'
	}
	path = os.norm_path(path).replace('\\', '/')
	if is_windows_path(root) {
		path = path.to_lower()
		root = root.to_lower()
	}
	if !path.starts_with('${root}/') {
		return false
	}
	relative := path[root.len + 1..]
	return relative in owned_root_files || relative.all_before('/') in owned_directories
}

fn (mut filter DiagnosticFilter) accept(chunk string, stream int, root string) {
	print(chunk)
	flush_stdout()
	buffer := filter.partial[stream] + chunk
	lines := buffer.split('\n')
	for line in lines[..lines.len - 1] {
		if filter.is_project_diagnostic(line, root) {
			filter.seen = true
		}
	}
	filter.partial[stream] = lines.last()
}

fn check_command(command []string, root string) !int {
	mut filter := new_filter()!
	compiler_path := os.find_abs_path_of_executable(command[0]) or {
		return error('could not find compiler ${command[0]}')
	}
	mut process := os.new_process(compiler_path)
	process.set_args(command[1..])
	process.set_work_folder(root)
	process.set_redirect_stdio()
	process.run()
	if process.pid <= 0 {
		return error('could not start compiler: ${process.err}')
	}
	defer { process.close() }
	for {
		alive := process.is_alive()
		mut received := false
		for i, pipe in [os.ChildProcessPipeKind.stdout, .stderr] {
			if chunk := process.pipe_read(pipe) {
				filter.accept(chunk, i, root)
				received = true
			}
		}
		if !received {
			if !alive {
				break
			}
			time.sleep(poll_interval)
		}
	}
	process.wait()
	if process.code != 0 {
		return process.code
	}
	for remaining in filter.partial {
		if filter.is_project_diagnostic(remaining, root) {
			filter.seen = true
		}
	}
	if filter.seen {
		return error('Game compilation produced project warnings or notices; fix them before merging.')
	}
	return 0
}

fn self_test(root string) ! {
	mut filter := new_filter()!
	for path in ['sim/simulation.v', './runtime/menu.v', 'torus_trooper.v',
		os.join_path(root, 'runtime', 'vulkan_bridge.h')] {
		assert filter.is_project_diagnostic('${path}:12:4: warning: example', root)
	}
	assert filter.is_project_diagnostic('\x1b[33mruntime/menu.v:12: notice: unused\x1b[0m', root)
	assert filter.is_project_diagnostic(r'C:\Game\runtime\menu.v:12:4: notice: unused', 'C:/game')
	assert filter.is_project_diagnostic(r'C:\Game (test)\runtime\bridge.h(12,4): warning C1234: example',
		'C:/game (test)')
	for path in ['toolchain/v/cmd/v/toolcache.v', 'modules/antono2/vulkan/api.v',
		'thirdparty/miniaudio/miniaudio.h', '../another-game/runtime/app.v'] {
		assert !filter.is_project_diagnostic('${path}:12:4: warning: example', root)
	}
	assert !filter.is_project_diagnostic('simulation tick=12: warning: game message', root)

	for fixture, expected in {
		'clean':      0
		'warning':    1
		'dependency': 0
		'failed':     7
	} {
		status := check_command([os.executable(), '--fixture', fixture], root) or {
			if fixture != 'warning' || !err.msg().contains('project warnings or notices') {
				return err
			}
			1
		}
		assert status == expected
	}
	println('Compiler diagnostic paths and exit status passed')
}

fn run(args []string) !int {
	root := os.dir(@DIR)
	if args.len == 2 && args[0] == '--fixture' {
		match args[1] {
			'clean' {
				println('compiled')
			}
			'warning' {
				eprintln('runtime/menu.v:12:4: notice: unused')
			}
			'dependency' {
				println('toolchain/v/cmd/v/toolcache.v:12:4: notice: unused')
			}
			'failed' {
				println('compile failed')
				return 7
			}
			else {
				return error('unknown compiler diagnostic fixture')
			}
		}

		return 0
	}
	if args == ['--self-test'] {
		self_test(root)!
		return 0
	}
	command := if args.len > 0 && args[0] == '--' { args[1..] } else { args }
	if command.len == 0 || command == ['--help'] {
		println('Usage: v run scripts/check_compiler_diagnostics.vsh -- COMMAND [ARGUMENT ...]')
		return if command.len == 0 { 1 } else { 0 }
	}
	return check_command(command, root)
}

status := run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
exit(status)
