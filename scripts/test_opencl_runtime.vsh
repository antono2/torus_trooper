// Verify dynamic OpenCL execution, missing-loader fallback and checksum parity.
import flag
import os
import scripts.testrun
import time

const parity_ticks = 600
const parity_fields = ['checksum', 'render_checksum', 'course_checksum', 'course_fill_checksum',
	'course_backward_checksum', 'course_backward_fill_checksum', 'compute_checksum']

fn require(ok bool, detail string) ! {
	if !ok {
		return error(detail)
	}
}

fn run_compute(binary string, backend string, environment map[string]string) !map[string]string {
	result := testrun.capture(binary, ['--headless', '--ticks', parity_ticks.str(), '--compute',
		backend, '--no-sound', '--volume', '0'], os.getwd(), environment, 60 * time.second)!
	mut fields := map[string]string{}
	for line in result.stdout.split_into_lines() {
		key, value := line.split_once('=') or { continue }
		fields[key] = value
	}
	require(fields['compute_requested'] == backend, result.stdout)!
	return fields
}

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('test_opencl_runtime')
	parser.arguments_description('BINARY')
	require_opencl := parser.bool('require-opencl', 0, false, 'require a verified OpenCL batch')
	if parser.bool('help', `h`, false, 'show this help') {
		println(parser.usage())
		return
	}
	paths := parser.finalize()!
	require(paths.len == 1, parser.usage())!
	binary := os.abs_path(paths[0])
	$if linux {
		result := os.exec(['ldd', binary])
		require(result.exit_code == 0 && !result.output.contains('libOpenCL'),
			'Dynamic build must omit a direct OpenCL dependency.\n${result.output}')!
	}
	mut environment := os.environ()
	environment.delete('OPENCL_LIBRARY')
	cpu := run_compute(binary, 'cpu', environment)!
	available := run_compute(binary, 'opencl', environment)!
	if require_opencl {
		require(available['compute_active'] == 'opencl'
			&& available['compute_verified_batches'].int() > 0,
			'OpenCL did not verify work: ${available}')!
	}
	temporary := testrun.temporary_directory('torus-opencl-')!
	defer { os.rmdir_all(temporary) or {} }
	environment['OPENCL_LIBRARY'] = os.join_path(temporary, 'missing-opencl-runtime')
	missing := run_compute(binary, 'opencl', environment)!
	require(missing['compute_active'] == 'cpu'
		&& missing['opencl_fallback'].contains('OpenCL runtime unavailable')
		&& missing['compute_fallback_batches'].int() > 0
		&& missing['compute_verified_batches'] == '0',
		'Expected CPU fallback when the loader is missing: ${missing}')!
	for key in parity_fields {
		require(cpu[key] != '' && cpu[key] == available[key] && cpu[key] == missing[key],
			'${key}: CPU=${cpu[key]}, with loader=${available[key]}, missing loader=${missing[key]}')!
	}
	println('Dynamic OpenCL execution and missing-loader CPU fallback preserve all checksums.')
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
