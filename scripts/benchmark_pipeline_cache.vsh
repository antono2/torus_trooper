// Use unique executable copies so a driver cache does not mask first use.
import flag
import os
import rand
import scripts.benchmarks
import scripts.testrun
import x.json2

fn run() ! {
	mut parser := flag.new_flag_parser(os.args[1..])
	parser.application('benchmark_pipeline_cache')
	parser.arguments_description('BINARY')
	runs := parser.int('runs', 0, 5, 'pairs of cached and uncached probes')
	output := parser.string('output', 0, '', 'JSON report path')
	if parser.bool('help', `h`, false, 'show usage') {
		println(parser.usage())
		return
	}
	args := parser.finalize()!
	if args.len != 1 || runs < 1 || output == '' {
		return error(parser.usage())
	}
	binary := benchmarks.executable(os.abs_path(args[0]))!
	root := os.dir(@DIR)
	work := testrun.temporary_directory('torus-cache-benchmark-')!
	defer { os.rmdir_all(work) or {} }
	cache := os.join_path(work, 'application.cache')
	binary_metadata := os.stat(binary)!
	nonce := rand.uuid_v4().replace('-', '')[..12]
	suffix := if os.user_os() == 'windows' { '.exe' } else { '' }
	mut records := []json2.Any{}
	mut env := benchmarks.profiling_environment()
	for index in 0 .. runs * 2 + 1 {
		seed := index == 0
		// Seed the application cache, then alternate the order within each pair.
		run_index := (index - 1) / 2
		cached := seed || index % 2 == run_index % 2
		kind := if seed {
			'seed'
		} else if cached {
			'cached'
		} else {
			'uncached'
		}
		name := if seed { kind } else { '${kind}-${run_index}' }
		copy := os.join_path(work, name + '-' + nonce + suffix)
		os.cp(binary, copy)!
		$if !windows {
			os.chmod(copy, int(binary_metadata.mode & 0o777))!
		}
		os.utime(copy, binary_metadata.atime, binary_metadata.mtime)!
		env['TT_PIPELINE_CACHE_FILE'] = if cached { cache } else { '' }
		mut record := benchmarks.probe(root, copy, os.join_path(work, name + '.json'), env)!
		if seed {
			if !os.is_file(cache) {
				return error('Driver did not export a pipeline cache')
			}
		} else {
			loaded := record['cache_loaded'] or { return error('Missing cache_loaded in profile') }
			if loaded.f64() != f64(int(cached)) {
				return error('Unexpected cache state in ${name}: ${record}')
			}
			record['run'] = json2.Any(run_index + 1)
		}
		record['kind'] = json2.Any(kind)
		records << json2.Any(record)
	}
	mut report := benchmarks.renderer_report(root, binary)!
	report['benchmark_sha256'] = json2.Any(benchmarks.digest(@FILE)!)
	report['cache_bytes'] = json2.Any(os.file_size(cache))
	report['executable_nonce'] = json2.Any(nonce)
	report['records'] = json2.Any(records)
	benchmarks.write_report(output, report)!
	println('Saved pipeline cache comparison to ${output}')
}

run() or {
	eprintln(err)
	exit(1)
}
