// Package the Windows executable, fresh shaders, assets, and license notices.
import compress.szip
import flag
import os
import rand

$if windows {
	#include <fcntl.h>
	#include <io.h>
	#include <sys/stat.h>
}

fn C._write(fd int, data voidptr, count u32) int
fn C._close(fd int) int

const package_directory = 'torus-trooper'

struct Entry {
	source string
	name   string
}

fn validate_binary(binary string) ! {
	if !os.is_file(binary) {
		return error('Build the game first. Executable not found at ${binary}')
	}
	mut file := os.open(binary)!
	defer { file.close() }
	mut magic := []u8{len: 2}
	size := file.read(mut magic) or { 0 }
	if size != magic.len || magic.bytestr() != 'MZ' {
		return error('The executable is not a Windows binary')
	}
}

fn add_assets(root string, subdirectory string, mut entries []Entry) ! {
	directory := os.join_path(root, subdirectory)
	for name in os.ls(directory)!.sorted() {
		relative := '${subdirectory}/${name}'
		path := os.join_path(root, relative)
		if os.is_dir(path) && !os.is_link(path) {
			add_assets(root, relative, mut entries)!
		} else if os.is_file(path) && !name.ends_with('.spv') {
			entries << Entry{path, '${package_directory}/${relative}'}
		}
	}
}

fn create_zip(staging string, entries []Entry) !string {
	// The ZIP library opens a narrow path on Windows. Use an ASCII filename
	// relative to the staging directory so its absolute path can contain Unicode.
	previous := os.getwd()
	os.chdir(staging)!
	defer { os.chdir(previous) or {} }
	name := 'payload.zip'
	mut archive := szip.open(name, .default_compression, .write)!
	defer { archive.close() }
	// The file-based ZIP API records usable filesystem permissions.
	staged_entry := 'entry.bin'
	for entry in entries {
		os.cp(entry.source, staged_entry)!
		$if !windows {
			os.chmod(staged_entry, if entry.name.ends_with('.exe') { 0o755 } else { 0o644 })!
		}
		archive.open_entry(entry.name)!
		archive.create_entry(staged_entry)!
		archive.close_entry()
	}
	return os.join_path(staging, name)
}

fn publish_archive(source string, destination string) ! {
	bytes := os.read_bytes(source)!
	if bytes.len == 0 {
		return error('generated ZIP is empty')
	}
	mut complete := false
	$if windows {
		// The wide CRT path preserves Unicode and O_EXCL preserves existing files.
		flags := C._O_WRONLY | C._O_CREAT | C._O_EXCL | C._O_BINARY
		fd := C._wopen(destination.to_wide(), flags, int(C._S_IREAD | C._S_IWRITE))
		if fd < 0 {
			return error('Cannot create archive at ${destination}')
		}
		written := C._write(fd, bytes.data, u32(bytes.len))
		status := C._close(fd)
		complete = written == bytes.len && status == 0
	} $else {
		file := os.vfopen(destination, 'wbx')!
		written := C.fwrite(bytes.data, 1, usize(bytes.len), file)
		status := C.fclose(file)
		complete = written == usize(bytes.len) && status == 0
	}
	if !complete {
		os.rm(destination) or {}
		return error('Incomplete ZIP write at ${destination}')
	}
}

fn package(archive_arg string, binary_arg string) ! {
	root := os.dir(@DIR)
	archive := os.abs_path(archive_arg)
	binary := os.abs_path(binary_arg)
	validate_binary(binary)!
	if os.exists(archive) || os.is_link(archive) {
		return error('Refusing to overwrite ${archive}')
	}
	mut entries := [Entry{binary, '${package_directory}/torus_trooper.exe'}]
	for name in ['LICENSE', 'README.md', 'CHANGELOG.md', 'TUNING.md', 'thirdparty/miniaudio/LICENSE'] {
		entries << Entry{os.join_path(root, name), '${package_directory}/${name}'}
	}
	for directory in ['shaders', 'sounds', 'models', 'docs'] {
		add_assets(root, directory, mut entries)!
	}
	stage := os.join_path(os.temp_dir(), 'torus-package-${rand.uuid_v4()}')
	os.mkdir(stage)!
	defer { os.rmdir_all(stage) or {} }
	shaders := os.join_path(stage, 'shaders')
	result := os.exec([@VEXE, '-o', os.join_path(stage, 'shader_builder'), 'run',
		os.join_path(root, 'scripts', 'build_shaders.vsh'), '--output-dir', shaders])
	if result.exit_code != 0 {
		return error('Shader generation failed\n${result.output}')
	}
	for name in os.ls(shaders)!.sorted() {
		if name.ends_with('.spv') {
			entries << Entry{os.join_path(shaders, name), '${package_directory}/shaders/${name}'}
		}
	}
	publish_archive(create_zip(stage, entries)!, archive)!
	println('Packaged ${archive}')
}

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('package_windows')
	parser.description('Package the game executable, assets, and freshly compiled shaders.')
	parser.arguments_description('ARCHIVE BINARY')
	if parser.bool('help', `h`, false, 'show help') {
		println(parser.usage())
		return
	}
	paths := parser.finalize()!
	if paths.len != 2 {
		return error(parser.usage())
	}
	package(paths[0], paths[1])!
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
