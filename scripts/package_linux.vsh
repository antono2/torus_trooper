// Assemble the Linux game, fresh shaders, runtime libraries, and license notices.
import crypto.sha256
import os
import rand
import x.json2

// GLFW loads these X11 extensions at runtime, beyond the libraries ldd reports.
const runtime_roots = ['libglfw.so.3', 'libvulkan.so.1', 'libXrandr.so.2', 'libXinerama.so.1',
	'libXcursor.so.1', 'libXi.so.6', 'libXxf86vm.so.1', 'libX11-xcb.so.1']
const system_libraries = ['libc.so', 'libm.so', 'libdl.so', 'libpthread.so', 'librt.so',
	'libresolv.so', 'libutil.so']
const common_license_directory = '/usr/share/common-licenses/'
const package_directory = 'torus-trooper'
const launcher = r'#!/bin/sh
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
cd -- "$package_dir" || exit 1
LD_LIBRARY_PATH="$package_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec ./torus_trooper "$@"
'

struct Library {
	name   string
	source string
}

struct LibraryNotice {
	library        string
	package        string
	version        string
	source_package string
	source_version string
	sha256         string
}

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args[0]} exited with status ${result.exit_code}\n${result.output}')
	}
	return result.output
}

fn dependencies(path string) ![]Library {
	text := command(['ldd', path])!
	if text.contains('=> not found') {
		return error('Missing dependencies for ${path}\n${text}')
	}
	mut libraries := []Library{}
	for line in text.split_into_lines() {
		fields := line.fields()
		if fields.len >= 3 && fields[1] == '=>' && fields[2].starts_with('/') {
			libraries << Library{fields[0], fields[2]}
		}
	}
	return libraries
}

fn installed_runtime_paths() !map[string]string {
	ldconfig := os.find_abs_path_of_executable('ldconfig') or { '/sbin/ldconfig' }
	cache := command([ldconfig, '-p'])!
	mut available := map[string]string{}
	for line in cache.split_into_lines() {
		if !line.contains('x86-64') {
			continue
		}
		fields := line.fields()
		if fields.len >= 4 && fields[fields.len - 2] == '=>' && fields.last().starts_with('/') {
			available[fields[0]] = fields.last()
		}
	}
	return available
}

fn bundle_library(package string, library Library, source string) !LibraryNotice {
	owners := command(['dpkg-query', '-S', source])!.split_into_lines()
	if owners.len == 0 || !owners[0].contains(': ') {
		return error('No installed package owns ${source}')
	}
	owner := owners[0].all_before_last(': ')
	metadata := command(['dpkg-query', '-W',
		r'-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}', owner])!.split('\t')
	if metadata.len != 4 {
		return error('Invalid package metadata for ${owner}')
	}
	notice := os.join_path('/usr/share/doc', owner.all_before(':'), 'copyright')
	if !os.is_file(notice) {
		return error('License notice missing for ${source}: ${notice}')
	}
	notices := os.join_path(package, 'thirdparty', 'linux-runtime')
	os.cp(notice, os.join_path(notices, owner.replace(':', '-') + '.copyright'))!
	for mention in os.read_file(notice)!.split(common_license_directory)[1..] {
		mut end := 0
		for end < mention.len
			&& (mention[end].is_alnum() || mention[end] in [u8(`_`), `.`, `+`, `-`]) {
			end++
		}
		name := mention[..end]
		path := common_license_directory + name
		if name != '' && os.is_file(path) {
			os.cp(path, os.join_path(notices, name))!
		}
	}
	os.cp(source, os.join_path(package, 'lib', library.name))!
	return LibraryNotice{
		library:        library.name
		package:        metadata[0]
		version:        metadata[1]
		source_package: metadata[2]
		source_version: metadata[3]
		sha256:         sha256.sum(os.read_bytes(source)!).hex()
	}
}

fn bundle_runtime(package string, binary string) ! {
	os.mkdir(os.join_path(package, 'lib'))!
	notices := os.join_path(package, 'thirdparty', 'linux-runtime')
	os.mkdir(notices)!
	available := installed_runtime_paths()!
	mut pending := dependencies(binary)!
	for name in runtime_roots {
		path := available[name] or { return error('Linux runtime library ${name} is missing') }
		pending << Library{name, path}
	}
	mut copied := map[string]bool{}
	mut manifest := []LibraryNotice{}
	for pending.len > 0 {
		library := pending.pop()
		if library.name in copied || library.name.starts_with('ld-linux')
			|| library.name.starts_with('libnss_')
			|| system_libraries.any(library.name.starts_with(it)) {
			continue
		}
		source := os.real_path(library.source)
		manifest << bundle_library(package, library, source)!
		copied[library.name] = true
		pending << dependencies(source)!
	}
	manifest.sort(a.library < b.library)
	os.write_file(os.join_path(notices, 'libraries.json'), json2.encode(manifest,
		prettify:      true
		indent_string: '  '
	) + '\n')!
	println('Bundled ${manifest.len} runtime libraries and their license notices')
}

fn package_linux(output string, binary_arg string) ! {
	root := os.dir(@DIR)
	archive := os.abs_path(output)
	binary := os.abs_path(binary_arg)
	if !os.is_file(binary) || !os.is_executable(binary) {
		return error('Build the game first. Executable not found at ${binary}')
	}
	if os.exists(archive) || os.is_link(archive) {
		return error('Refusing to overwrite ${archive}')
	}
	// Stage beside the destination so the completed archive can be published
	// atomically with an exclusive hard link on the same filesystem.
	stage := os.join_path(os.dir(archive), '.torus-package-' + rand.uuid_v4())
	os.mkdir(stage)!
	defer { os.rmdir_all(stage) or {} }
	package := os.join_path(stage, package_directory)
	os.mkdir_all(os.join_path(package, 'thirdparty', 'miniaudio'))!
	game := os.join_path(package, 'torus_trooper')
	os.cp(binary, game)!
	for directory in ['shaders', 'sounds', 'models', 'docs'] {
		os.cp_all(os.join_path(root, directory), os.join_path(package, directory), false)!
	}
	for name in ['LICENSE', 'README.md', 'CHANGELOG.md', 'TUNING.md', 'thirdparty/miniaudio/LICENSE'] {
		os.cp(os.join_path(root, name), os.join_path(package, name))!
	}
	shaders := os.join_path(package, 'shaders')
	for compiled in os.walk_ext(shaders, '.spv') {
		os.rm(compiled)!
	}
	print(command([@VEXE, '-o', os.join_path(stage, 'shader_builder'), 'run',
		os.join_path(root, 'scripts', 'build_shaders.vsh'), '--output-dir', shaders])!)
	bundle_runtime(package, binary)!
	command(['patchelf', '--force-rpath', '--set-rpath', r'$ORIGIN/lib', game])!
	play := os.join_path(package, 'play.sh')
	os.write_file(play, launcher)!
	os.chmod(play, 0o755)!
	os.chmod(game, 0o755)!
	payload := os.join_path(stage, 'payload.tar.gz')
	command(['tar', '-C', stage, '-czf', payload, package_directory])!
	os.link(payload, archive)!
	println('Packaged ${archive}')
}

fn run(args []string) ! {
	root := os.dir(@DIR)
	if args == ['--help'] || args == ['-h'] {
		println('Usage: v run scripts/package_linux.vsh OUTPUT_TAR_GZ [GAME_BINARY]')
		return
	}
	if args.len < 1 || args.len > 2 {
		return error('Usage: v run scripts/package_linux.vsh OUTPUT_TAR_GZ [GAME_BINARY]')
	}
	binary := if args.len == 2 { args[1] } else { os.join_path(root, 'torus_trooper') }
	package_linux(args[0], binary)!
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
