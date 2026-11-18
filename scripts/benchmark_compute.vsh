// Measure real OpenCL work and CPU verification in fresh game-test processes.
import flag
import os
import rand
import scripts.benchmarks
import scripts.testrun
import time
import x.json2

const expected_records = 6 // Startup, program cache, and four particle pool sizes.

fn run() ! {
	mut parser := flag.new_flag_parser(os.args[1..])
	parser.application('benchmark_compute')
	compiler_name := parser.string('v', 0, 'v', 'V compiler for the benchmark')
	runs := parser.int('runs', 0, 5, 'fresh-process samples')
	output := parser.string('output', 0, '', 'JSON report path')
	if parser.bool('help', `h`, false, 'show usage') {
		println(parser.usage())
		return
	}
	if parser.finalize()!.len != 0 || runs < 1 || output == '' {
		return error(parser.usage())
	}
	root := os.dir(@DIR)
	compiler := benchmarks.executable(compiler_name)!
	mut env := os.environ()
	env.delete('VEXE')
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	work := testrun.temporary_directory('torus-compute-')!
	defer { os.rmdir_all(work) or {} }
	binary := os.join_path(work, if os.user_os() == 'windows' {
		'benchmark.exe'
	} else {
		'benchmark'
	})
	template := os.join_path(@DIR, 'benchmarks', 'compute.v.template')
	source := os.join_path(root, 'sim', 'binding_benchmark_' + rand.uuid_v4().replace('-', '') +
		'_test.v')
	os.cp(template, source)!
	defer { os.rm(source) or {} }
	testrun.capture(compiler, ['-no-skip-unused', '-d', 'opencl_compute', '-d', 'opencl_dynamic',
		'-cc', 'gcc', '-skip-running', '-o', binary, source], root, env, 5 * time.minute)!
	mut records := []json2.Any{}
	for index in 0 .. runs {
		result := testrun.capture(binary, [], root, env, 2 * time.minute)!
		lines := result.stdout.split_into_lines().filter(it.starts_with('BENCH '))
		if lines.len != expected_records {
			return error('Expected ${expected_records} measurements.\n${result.stdout}${result.stderr}')
		}
		for line in lines {
			mut record := json2.decode[map[string]json2.Any](line['BENCH '.len..])!
			record['run'] = json2.Any(index + 1)
			records << json2.Any(record)
		}
		println('Completed fresh-process run ${index + 1}/${runs}')
	}
	version :=
		testrun.capture(compiler, ['version'], root, env, benchmarks.probe_timeout)!.stdout.trim_space()
	benchmarks.write_report(output, {
		'compiler':             json2.Any(version)
		'source_commit':        json2.Any(benchmarks.command(root, ['git', 'rev-parse', 'HEAD'])!)
		'template_sha256':      json2.Any(benchmarks.digest(template)!)
		'working_tree_changes': json2.Any(benchmarks.command(root, ['git', 'diff', '--stat'])!)
		'records':              json2.Any(records)
	})!
	println('Saved ${output}')
}

run() or {
	eprintln(err)
	exit(1)
}
