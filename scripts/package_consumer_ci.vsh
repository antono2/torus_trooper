// Drive package checks on CI hosts and in runtime-only Ubuntu containers.
import os
import rand
import scripts.releaseconsumer

const downloads = 'downloads'
const logs = 'package-smoke-logs'
const checksum_file = 'SHA256SUMS'
const consumer = '/consumer'
const usage = 'Usage: package_consumer_ci.vsh download linux|windows | windows|linux [--checksums] | hidden-runtime|ubuntu26 ARCHIVE'

fn child_status(binary string, args []string) int {
	mut child := os.new_process(binary)
	defer { child.close() }
	child.set_args(args)
	child.run()
	child.wait()
	return child.code
}

fn run_command(name string, args []string) ! {
	binary := os.find_abs_path_of_executable(name)!
	status := child_status(binary, args)
	if status != 0 {
		return error('${name} exited with status ${status}')
	}
}

fn select_archive(directory string, suffixes []string) !string {
	mut archives := []string{}
	for name in os.ls(directory)! {
		path := os.join_path(directory, name)
		if suffixes.any(name.ends_with(it)) && os.is_file(path) && !os.is_link(path) {
			archives << path
		}
	}
	if archives.len != 1 {
		return error('Expected exactly one package archive in ${directory}, found ${archives.len}')
	}
	return os.abs_path(archives[0])
}

fn download(platform string) ! {
	if platform !in ['linux', 'windows'] {
		return error(usage)
	}
	mut args := ['release', 'download', '--repo', 'antono2/torus_trooper', '--pattern',
		'torus-trooper-*-${platform}-x86_64.*', '--pattern', checksum_file, '--dir', downloads]
	tag := os.getenv('RELEASE_TAG')
	if tag != '' && tag != 'latest' {
		args << ['--', tag]
	}
	run_command('gh', args)!
}

fn package_args(archive string, output string, checksums string) []string {
	mut args := [archive, '--project', 'torus', '--logs', output]
	if checksums != '' {
		args << ['--checksums', checksums]
	}
	return args
}

fn windows_consumer(with_checksums bool) ! {
	archive := select_archive(downloads, ['.zip'])!
	sdk := os.getenv('VULKAN_SDK')
	if sdk == '' {
		return error('VULKAN_SDK must point to the Windows runtime')
	}
	checksums := if with_checksums { os.join_path(downloads, checksum_file) } else { '' }
	mut args := package_args(archive, logs, checksums)
	args << ['--vulkan-loader', os.join_path(sdk, 'Bin', 'vulkan-1.dll')]
	releaseconsumer.smoke(args)!
}

fn runtime_consumer(profile string, archive string, output string, checksums string) ! {
	mut packages := ['mesa-vulkan-drivers']
	if profile == 'ubuntu24' {
		packages << ['xvfb', 'xauth', 'libvulkan1', 'vulkan-validationlayers']
	}
	run_command('apt-get', ['update'])!
	mut install := ['install', '-y', '--no-install-recommends']
	install << packages
	run_command('apt-get', install)!
	if profile == 'ubuntu24' {
		for tool in ['v', 'cmake', 'cc'] {
			if _ := os.find_abs_path_of_executable(tool) {
				return error('Runtime container unexpectedly provides ${tool}')
			}
		}
	}
	dpkg := os.find_abs_path_of_executable('dpkg-query')!
	match child_status(dpkg, ['-W', 'libglfw3']) {
		0 { return error('Runtime container unexpectedly provides system GLFW') }
		1 {}
		else { return error('Could not verify whether system GLFW is installed') }
	}

	println('Verified runtime package isolation for ${profile}.')
	mut args := ['--kill-after=10s', '8m']
	if profile == 'ubuntu24' {
		os.setenv('VK_INSTANCE_LAYERS', 'VK_LAYER_KHRONOS_validation', true)
		args << ['xvfb-run', '-a']
	}
	args << [os.executable(), 'smoke']
	args << package_args(archive, output, checksums)
	run_command('timeout', args)!
}

fn hidden_runtime(archive string) ! {
	stage := os.join_path(os.temp_dir(), 'torus-hidden-runtime-' + rand.uuid_v4())
	os.mkdir(stage, mode: 0o700)!
	defer { os.rmdir_all(stage) or {} }
	tester := os.join_path(stage, 'test-linux-package')
	run_command(@VEXE,
		['-skip-running', '-o', tester, os.join_path(@DIR, 'test_linux_package.vsh')])!
	run_command('xvfb-run', ['-a', 'sudo', '--preserve-env=DISPLAY,XAUTHORITY', tester, archive])!
}

fn linux_container(profile string, archive string, with_checksums bool) ! {
	stage := os.join_path(os.temp_dir(), 'torus-consumer-' + rand.uuid_v4())
	os.mkdir(stage, mode: 0o700)!
	defer { os.rmdir_all(stage) or {} }
	runner := os.join_path(stage, 'package-consumer-ci')
	run_command(@VEXE, ['-cc', 'gcc', '-skip-running', '-o', runner, @FILE])!
	output := os.abs_path(if profile == 'ubuntu26' { os.join_path(logs, profile) } else { logs })
	os.mkdir_all(output)!
	mut args := ['run', '--rm', '--init', '--volume', '${stage}:${consumer}/bin:ro', '--volume',
		'${archive}:${consumer}/archive/${os.file_name(archive)}:ro', '--volume',
		'${output}:${consumer}/logs']
	mut checksums := ''
	if with_checksums {
		path := os.join_path(os.dir(archive), checksum_file)
		if !os.is_file(path) {
			return error('Missing archive checksums at ${path}')
		}
		checksums = '${consumer}/${checksum_file}'
		args << ['--volume', '${path}:${checksums}:ro']
	}
	cookie := os.join_path(stage, 'authority')
	if profile == 'ubuntu26' {
		args << ['--uts=host', '--ipc=host', '--env', 'DISPLAY', '--env',
			'XAUTHORITY=/tmp/game-xauthority', '--volume', '/tmp/.X11-unix:/tmp/.X11-unix:ro',
			'--volume', '${cookie}:/tmp/game-xauthority:ro']
	}
	args << [if profile == 'ubuntu26' { 'ubuntu:26.04' } else { 'ubuntu:24.04' },
		'${consumer}/bin/package-consumer-ci', 'runtime', profile,
		'${consumer}/archive/${os.file_name(archive)}', '${consumer}/logs', checksums]
	if profile == 'ubuntu26' {
		docker := os.find_abs_path_of_executable('docker')!
		mut display_args := ['-a', '-f', cookie, docker]
		display_args << args
		run_command('xvfb-run', display_args)!
	} else {
		run_command('docker', args)!
	}
}

fn run(args []string) ! {
	command := args[0] or { return error(usage) }
	match command {
		'download' {
			if args.len != 2 { return error(usage) }
			download(args[1])!
		}
		'linux', 'windows' {
			if args.len > 2 || (args.len == 2 && args[1] != '--checksums') { return error(usage) }
			if command == 'windows' {
				windows_consumer(args.len == 2)!
			} else {
				linux_container('ubuntu24', select_archive(downloads, ['.zip', '.tar.gz'])!,
					args.len == 2)!
			}
		}
		'hidden-runtime', 'ubuntu26' {
			if args.len != 2 || !os.is_file(args[1]) { return error(usage) }
			archive := os.abs_path(args[1])
			if command == 'ubuntu26' {
				linux_container('ubuntu26', archive, false)!
			} else {
				hidden_runtime(archive)!
			}
		}
		'smoke' {
			releaseconsumer.smoke(args[1..])!
		}
		'runtime' {
			if args.len != 5 || args[1] !in ['ubuntu24', 'ubuntu26'] { return error(usage) }
			runtime_consumer(args[1], args[2], args[3], args[4])!
		}
		else {
			return error(usage)
		}
	}
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
