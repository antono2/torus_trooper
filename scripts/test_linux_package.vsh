// Prove the Linux package starts with the bundled libraries hidden on the host.
import os
import scripts.testrun
import time
import x.json2

const probe_timeout = 60 * time.second
const missing_glfw = 'error while loading shared libraries: libglfw.so.3'
const headless_ticks = '600'
const reference_checksum = 'checksum=490efd84cf12692f'

struct LibraryNotice {
	library string
}

fn output(executable string, args []string, directory string) !string {
	result := testrun.capture(executable, args, directory, os.environ(), probe_timeout)!
	return result.stdout + result.stderr
}

fn host_library_paths(cache string, notices []LibraryNotice) ![]string {
	mut found := map[string]string{}
	for line in cache.split_into_lines() {
		description, installed := line.split_once(' => ') or { continue }
		parts := description.fields()
		if parts.len > 0 && description.contains('x86-64') && parts[0] !in found {
			found[parts[0]] = installed.trim_space()
		}
	}
	mut paths := []string{}
	for notice in notices {
		installed := found[notice.library] or {
			return error('Host library missing from test fixture: ${notice.library}')
		}
		path := os.real_path(installed)
		if !os.is_abs_path(path) || !os.is_file(path) {
			return error('Host library could not be resolved: ${installed}')
		}
		if path !in paths {
			paths << path
		}
	}
	return paths
}

fn run(args []string) ! {
	usage := 'Usage: xvfb-run -a v run scripts/test_linux_package.vsh ARCHIVE'
	if args in [['--help'], ['-h']] {
		println(usage)
		return
	}
	if args.len != 1 {
		return error(usage)
	}
	archive := os.real_path(args[0])
	if !os.is_file(archive) {
		return error('Package archive missing: ${archive}')
	}
	bwrap := os.find_abs_path_of_executable('bwrap')!
	tar := os.find_abs_path_of_executable('tar')!
	work := testrun.temporary_directory('torus-package-test-')!
	defer { os.rmdir_all(work) or {} }
	base := ['--ro-bind', '/', '/', '--dev-bind', '/dev', '/dev', '--proc', '/proc']
	// The extractor can only write to the fresh staging directory.
	mut extract := base.clone()
	extract << ['--bind', work, work, '--chdir', work, '--', tar, '--no-same-owner',
		'--no-same-permissions', '-xzf', archive]
	output(bwrap, extract, work)!
	package := os.join_path(work, 'torus-trooper')
	manifest := os.join_path(package, 'thirdparty', 'linux-runtime', 'libraries.json')
	notices := json2.decode[[]LibraryNotice](os.read_file(manifest)!)!
	if notices.len == 0 || !notices.any(it.library == 'libglfw.so.3') {
		return error('Expected a bundled GLFW library in the package manifest')
	}
	cache := output('/sbin/ldconfig', ['-p'], work)!
	mut namespace := base.clone()
	namespace << ['--chdir', package]
	for path in host_library_paths(cache, notices)! {
		namespace << ['--ro-bind', '/dev/null', path]
	}
	namespace << '--'
	bare := os.join_path(work, 'unbundled')
	player := os.join_path(package, 'torus_trooper')
	os.cp(player, bare)!
	os.chmod(bare, 0o700)!
	mut failed_as_expected := false
	output(bwrap, namespace_command(namespace, [bare, '--headless', '--ticks', '1']), work) or {
		if !err.msg().contains(missing_glfw) {
			return err
		}
		failed_as_expected = true
		''
	}
	if !failed_as_expected {
		return error('Bare player still found the hidden system libraries')
	}
	headless := output(bwrap, namespace_command(namespace, [player, '--headless', '--ticks',
		headless_ticks, '--no-sound', '--volume', '0']), work)!
	if !headless.contains(reference_checksum) {
		return error('Unexpected headless output\n${headless}')
	}
	probe := output(bwrap, namespace_command(namespace, ['./play.sh', '--probe', '--no-sound',
		'--volume', '0', '--data-file', os.join_path(work, 'player.json')]), work)!
	if !probe.contains('GLFW: Vulkan surface creation succeeded') {
		return error('Vulkan probe did not create a GLFW surface\n${probe}')
	}
	println('Linux package passed with all bundled libraries hidden on the host.')
}

fn namespace_command(namespace []string, command []string) []string {
	mut args := namespace.clone()
	args << command
	return args
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
