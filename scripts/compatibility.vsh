// Print or verify the exact compiler, SDK, and module revisions used by Torus Trooper.
import compatpins
import flag
import os
import rand
import x.json2

fn self_test(root string) ! {
	windows := compatpins.resolve(root, platform: 'windows')!
	linux := compatpins.resolve(root, platform: 'linux')!
	assert windows['v'] == linux['v']
	assert linux['vc'] == (windows['linux_vc'] or { windows['vc'] })
	assert linux['project_version'] == windows['project_version']
	work := os.join_path(os.temp_dir(), 'torus-compat-' + rand.uuid_v4())
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(os.join_path(work, 'v.mod'),
		"Module { version: '0.1.0' dependencies: ['antono2.opencl@v99.0.0'] }")!
	os.cp(os.join_path(root, 'compatibility.json'), os.join_path(work, 'compatibility.json'))!
	compatpins.resolve(work, platform: 'windows') or {
		if !err.msg().contains('disagree') {
			return err
		}
		println('Compatibility pins and refusal checks passed.')
		return
	}
	return error('compatibility accepted a mismatched module pin')
}

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('compatibility')
	parser.description('Validate and resolve tested build pins.')
	root := parser.string('root', 0, os.dir(@DIR), 'project root')
	platform := parser.string('platform', 0, '', 'windows or linux, defaults to the current host')
	variant := parser.string('variant', 0, 'docking', 'docking or standard')
	compiler := parser.string('compiler', 0, 'stable', 'stable or v3')
	output_path := parser.string('github-output', 0, '', 'append pins to this GitHub output file')
	key := parser.string('get', 0, '', 'print a single pin')
	modules := parser.string('modules', 0, '', 'verify module checkouts')
	test := parser.bool('self-test', 0, false,
		'check pin resolution and reject a dependency mismatch')
	if parser.bool('help', `h`, false, 'show help') {
		println(parser.usage())
		return
	}
	if parser.finalize()!.len != 0 {
		return error('unexpected positional arguments')
	}
	if test {
		self_test(root)!
		return
	}
	outputs := compatpins.resolve(root, platform: platform, variant: variant, compiler: compiler)!
	if modules != '' {
		compatpins.verify_modules(outputs, modules)!
	}
	if output_path != '' {
		mut output := os.open_append(output_path)!
		defer { output.close() }
		for name, value in outputs {
			output.writeln('${name}=${value}')!
		}
	}
	if key != '' {
		println(outputs[key] or { return error('unknown compatibility output: ${key}') })
	} else {
		println(json2.encode(outputs, prettify: true))
	}
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
