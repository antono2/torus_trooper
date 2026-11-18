// Exercise native Vulkan pipeline cache reuse and recovery through the game CLI.
import encoding.binary
import flag
import os
import scripts.testrun
import time

const cache_magic = 'TTPCACHE'
const cache_header_bytes = 16
const minimum_cache_bytes = 48
const vendor_id_offset = 8
const uuid_offset = 16
const fnv64_basis = u64(14695981039346656037)
const fnv64_prime = u64(1099511628211)
const probe_pipelines = 8

fn require(ok bool, detail string) ! {
	if !ok {
		return error(detail)
	}
}

fn payload_checksum(data []u8) u64 {
	mut value := fnv64_basis
	for byte in data {
		value = (value ^ u64(byte)) * fnv64_prime
	}
	return value
}

struct Fixture {
	binary string
	root   string
	player string
}

fn (fixture Fixture) probe(path string, loaded bool, default_root string) ! {
	mut environment := os.environ()
	environment['TT_GPU_PROFILE'] = '1'
	environment['TT_PIPELINE_CACHE_FILE'] = path
	if default_root != '' {
		environment.delete('TT_PIPELINE_CACHE_FILE')
		key := if os.user_os() == 'windows' { 'LocalAppData' } else { 'XDG_CACHE_HOME' }
		for existing in environment.keys() {
			if existing.to_upper_ascii() == key.to_upper_ascii() {
				environment.delete(existing)
			}
		}
		environment[key] = default_root
	}
	result := testrun.capture(fixture.binary, ['--probe', '--no-sound', '--volume', '0', '--res',
		'800', '600', '--data-file', fixture.player], fixture.root, environment, 60 * time.second)!
	output := result.stdout + result.stderr
	diagnostics := output.to_lower_ascii()
	require(!diagnostics.contains('validation error') && !diagnostics.contains('vuid-'), output)!
	require(output.contains('cache_loaded=${int(loaded)}')
		&& output.contains('pipelines=${probe_pipelines}'), output)!
}

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('test_pipeline_cache')
	parser.arguments_description('BINARY')
	if parser.bool('help', `h`, false, 'show this help') {
		println(parser.usage())
		return
	}
	paths := parser.finalize()!
	require(paths.len == 1, parser.usage())!
	temporary := testrun.temporary_directory('torus-pipeline-')!
	defer { os.rmdir_all(temporary) or {} }
	fixture := Fixture{
		binary: os.abs_path(paths[0])
		root:   os.dir(@DIR)
		player: os.join_path(temporary, 'player.json')
	}
	cache := os.join_path(temporary, 'pipeline.cache')
	fixture.probe(cache, false, '')!
	saved := os.read_bytes(cache)!
	require(saved.len >= minimum_cache_bytes && saved[..cache_magic.len].bytestr() == cache_magic,
		'Missing Torus pipeline cache header')!
	require(binary.little_endian_u64_at(saved, cache_magic.len) == payload_checksum(saved[cache_header_bytes..]),
		'Pipeline cache checksum differs')!
	fixture.probe(cache, true, '')!
	os.write_file(cache, 'truncated cache')!
	fixture.probe(cache, false, '')!
	mut corrupt := saved.clone()
	corrupt[corrupt.len - 1] ^= 1
	os.write_file_array(cache, corrupt)!
	fixture.probe(cache, false, '')!
	// Alter both native device identifiers, with a valid outer checksum in each case.
	for offset in [vendor_id_offset, uuid_offset] {
		mut stale := saved.clone()
		stale[cache_header_bytes + offset] ^= 1
		binary.little_endian_put_u64_at(mut stale, payload_checksum(stale[cache_header_bytes..]),
			cache_magic.len)
		os.write_file_array(cache, stale)!
		fixture.probe(cache, false, '')!
	}
	fixture.probe(cache, true, '')!
	missing := os.join_path(temporary, 'missing-parent')
	fixture.probe(os.join_path(missing, 'cache'), false, '')!
	require(!os.exists(missing) && !os.ls(temporary)!.any(it.ends_with('.tmp')),
		'Failed cache write left files behind')!
	default_root := os.join_path(temporary, 'default-cache-home')
	fixture.probe(cache, false, default_root)!
	require(os.is_file(os.join_path(default_root, 'torus_trooper', 'pipelines.cache')),
		'The default user cache was not written')!
	fixture.probe(cache, true, default_root)!
	blocked := os.join_path(temporary, 'not-a-directory')
	os.write_file(blocked, 'original')!
	fixture.probe(cache, false, blocked)!
	require(os.read_file(blocked)! == 'original', 'Cache creation modified an unrelated file')!
	println('Pipeline cache roundtrip, corrupt/stale fallback and failed-write startup passed.')
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
