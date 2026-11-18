// Collect the exact archives from successful release CI and prepare local release metadata.
import crypto.sha256
import flag
import os
import strconv
import x.json2

const repository = 'antono2/torus_trooper'
const required_jobs = [
	'Fresh Windows setup from ordinary PowerShell',
	'Windows V simulation and runtime tests',
	'V simulation and runtime tests',
	'Package consumer (windows)',
	'Package consumer (linux)',
	'ubuntu-latest C bridge',
	'windows-latest C bridge',
	'macos-latest C bridge',
]
const hash_chunk_bytes = 1024 * 1024

struct Job {
	name       string
	conclusion string
}

struct Run {
	head_sha    string @[json: 'headSha']
	head_branch string @[json: 'headBranch']
	status      string
	conclusion  string
	jobs        []Job
	url         string
}

struct Manifest {
	version       string
	source_commit string
	ci_run        string
	compatibility map[string]json2.Any
	sha256        map[string]string
}

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args[0]} exited with status ${result.exit_code}\n${result.output}')
	}
	return result.output.trim_space()
}

fn validate_run(run Run, commit string) ! {
	if run.head_sha != commit || run.head_branch != 'main' {
		return error('Use successful main CI for the exact checked-out release commit')
	}
	if run.status != 'completed' || run.conclusion != 'success' {
		return error('Release CI must complete successfully')
	}
	mut names := map[string]bool{}
	for job in run.jobs {
		names[job.name] = true
	}
	if required_jobs.any(it !in names) {
		return error('Release CI is missing required setup, runtime, or package-consumer jobs')
	}
	for job in run.jobs {
		if job.conclusion != 'success' {
			return error('Every release CI job must pass. ${job.name} concluded ${job.conclusion}')
		}
	}
}

fn checksum(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut remaining := os.file_size(path)
	mut buffer := []u8{len: hash_chunk_bytes}
	for remaining > 0 {
		size := file.read(mut buffer)!
		if size <= 0 || u64(size) > remaining {
			return error('archive changed while hashing ${path}')
		}
		digest.write(buffer[..size])!
		remaining -= u64(size)
	}
	return digest.sum([]u8{}).hex()
}

fn project_version(source string) !string {
	for line in source.split_into_lines() {
		if line.trim_space().starts_with('version:') {
			value := line.all_after('version:').trim_space()
			if value.starts_with("'") && value.ends_with("'") && value.len > 2 {
				version := value[1..value.len - 1]
				parts := version.split('.')
				if parts.len == 3 && parts.all(it.len > 0 && it.bytes().all(it.is_digit())) {
					return version
				}
			}
		}
	}
	return error('v.mod must declare a release version')
}

fn release_notes(changelog string, version string) !string {
	mut lines := []string{}
	mut in_section := false
	for line in changelog.split_into_lines() {
		if line.starts_with('## ') {
			if in_section {
				break
			}
			in_section = line[3..].trim_space() == version
		} else if in_section {
			lines << line
		}
	}
	if !in_section {
		return error('Changelog must describe release ${version}')
	}
	return lines.join('\n').trim_space() +
		'\n\nDownload the archive for your OS and keep its files together. A Vulkan-capable graphics driver is required.\n' +
		'SHA256SUMS verifies the downloads. The release manifest records the source and passing CI run.\n'
}

fn require_clean_checkout(root string) ! {
	status := command(['git', '-C', root, 'status', '--porcelain', '-z', '--untracked-files=all'])!
	current_executable := os.real_path(os.executable())
	for record in status.split('\0').filter(it != '') {
		// V run may create this script's untracked executable next to its source.
		if record.starts_with('?? ')
			&& os.real_path(os.join_path(root, record[3..])) == current_executable {
			continue
		}
		return error('Use a clean checkout of the release commit')
	}
}

fn prepare(root string, run_id string, output_arg string) ! {
	commit := command(['git', '-C', root, 'rev-parse', 'HEAD'])!
	require_clean_checkout(root)!
	version := project_version(os.read_file(os.join_path(root, 'v.mod'))!)!
	notes := release_notes(os.read_file(os.join_path(root, 'CHANGELOG.md'))!, version)!
	compatibility := json2.decode[map[string]json2.Any](os.read_file(os.join_path(root,
		'compatibility.json'))!)!
	provenance := command(['gh', 'run', 'view', run_id, '--repo', repository, '--json',
		'headSha,headBranch,status,conclusion,jobs,url'])!
	run := json2.decode[Run](provenance)!
	validate_run(run, commit)!
	output := os.abs_path(output_arg)
	os.mkdir_all(os.dir(output))!
	os.mkdir(output) or { return error('Cannot create new release directory ${output}: ${err}') }
	mut ready := false
	defer {
		if !ready {
			os.rmdir_all(output) or {}
		}
	}
	mut assets := map[string]string{}
	mut checksums := []string{}
	for item in [['windows', 'zip'], ['linux', 'tar.gz']] {
		platform, extension := item[0], item[1]
		artifact := 'torus-trooper-${platform}-x86_64'
		command(['gh', 'run', 'download', run_id, '--repo', repository, '--name', artifact, '--dir',
			output])!
		filename := 'torus-trooper-${version}-${platform}-x86_64.${extension}'
		archive := os.join_path(output, filename)
		if !os.is_file(archive) {
			return error('CI archive name disagrees with v.mod: ${filename}')
		}
		digest := checksum(archive)!
		assets[filename] = digest
		checksums << '${digest}  ${filename}'
	}
	manifest := Manifest{version, commit, run.url, compatibility, assets}
	os.write_file(os.join_path(output, 'SHA256SUMS'), checksums.join('\n') + '\n')!
	os.write_file(os.join_path(output, 'release-manifest.json'), json2.encode(manifest,
		prettify: true
	) + '\n')!
	os.write_file(os.join_path(output, 'release-notes.txt'), notes)!
	ready = true
	println('Prepared v${version} from ${commit} in ${output}')
	println('Review the assets and release notes using docs/releasing.md.')
}

fn reject(run Run, commit string, expected string) ! {
	validate_run(run, commit) or {
		if !err.msg().contains(expected) {
			return error('expected ${expected}, got ${err}')
		}
		return
	}
	return error('invalid release run accepted')
}

fn self_test() ! {
	jobs := required_jobs.map(Job{it, 'success'})
	run := Run{'tested', 'main', 'completed', 'success', jobs, ''}
	validate_run(run, 'tested')!
	reject(run, 'different', 'exact')!
	reject(Run{ ...run, head_branch: 'feature' }, 'tested', 'exact')!
	reject(Run{ ...run, jobs: jobs[..jobs.len - 1] }, 'tested', 'missing')!
	mut failed := jobs.clone()
	failed[0] = Job{jobs[0].name, 'cancelled'}
	reject(Run{ ...run, jobs: failed }, 'tested', 'Every')!
	reject(Run{ ...run, status: 'in_progress' }, 'tested', 'complete')!
	assert project_version("Module {\n  version: '1.2.3'\n}")! == '1.2.3'
	assert release_notes('## 1.2.3\n\n- Current\n\n## 1.2.2\n- Older\n', '1.2.3')!.starts_with('- Current\n\n')
	println('Release CI validation fixtures passed')
}

fn run_cli(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('prepare_release')
	parser.description('Prepare the exact desktop archives from successful GitHub CI.')
	parser.arguments_description('RUN_ID')
	output := parser.string('output', 0, '', 'new local release directory')
	test := parser.bool('self-test', 0, false, 'run release validation fixtures')
	if parser.bool('help', `h`, false, 'show help') {
		println(parser.usage())
		return
	}
	positional := parser.finalize()!
	if test && positional.len == 0 && output == '' {
		self_test()!
		return
	}
	if positional.len != 1 || output == '' {
		return error(parser.usage())
	}
	run_id := strconv.parse_uint(positional[0], 10, 64) or {
		return error('RUN_ID must be a positive number')
	}
	if run_id == 0 {
		return error('RUN_ID must be a positive number')
	}
	prepare(os.dir(@DIR), run_id.str(), output)!
}

run_cli(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
