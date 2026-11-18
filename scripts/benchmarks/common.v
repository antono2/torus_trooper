// Shared subprocess, report and Vulkan profiling support.
module benchmarks

import crypto.sha256
import os
import scripts.testrun
import strconv
import time
import x.json2

pub const probe_timeout = 60 * time.second

pub fn executable(name string) !string {
	path := if os.is_abs_path(name) || name.contains_any('/\\') {
		os.abs_path(name)
	} else {
		os.find_abs_path_of_executable(name)!
	}
	if !os.is_file(path) || !os.is_executable(path) {
		return error('Expected an executable at ${path}')
	}
	return path
}

pub fn command(root string, args []string) !string {
	return testrun.capture(executable(args[0])!, args[1..], root, os.environ(), probe_timeout)!.stdout.trim_space()
}

pub fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

pub fn profiling_environment() map[string]string {
	mut env := os.environ()
	env['TT_GPU_PROFILE'] = '1'
	env['TT_PIPELINE_CACHE_FILE'] = ''
	return env
}

pub fn player_arguments(slot string) []string {
	// Use the same 800×600 framebuffer for all renderer measurements.
	return ['--no-sound', '--volume', '0', '--res', '800', '600', '--data-file', slot]
}

pub fn profile(log string) !map[string]json2.Any {
	diagnostics := log.to_lower_ascii()
	if diagnostics.contains('validation error') || diagnostics.contains('vuid-') {
		return error(log)
	}
	for line in log.split_into_lines() {
		if !line.starts_with('GPU_PROFILE ') {
			continue
		}
		mut record := map[string]json2.Any{}
		for item in line['GPU_PROFILE '.len..].fields() {
			key, value := item.split_once('=') or {
				return error('Invalid profiling field ${item}')
			}
			record[key] = json2.Any(strconv.atof64(value)!)
		}
		if record.len > 0 {
			return record
		}
	}
	return error('Renderer did not report profiling results.\n${log}')
}

pub fn probe(root string, binary string, slot string, env map[string]string) !map[string]json2.Any {
	mut args := ['--probe']
	args << player_arguments(slot)
	result := testrun.capture(binary, args, root, env, probe_timeout)!
	return profile(result.stdout + result.stderr)
}

pub fn renderer_report(root string, binary string) !map[string]json2.Any {
	return {
		'source_commit': json2.Any(command(root, ['git', 'rev-parse', 'HEAD'])!)
		'binary_sha256': json2.Any(digest(binary)!)
		'bridge_sha256': json2.Any(digest(os.join_path(root, 'runtime', 'vulkan_bridge.h'))!)
	}
}

pub fn write_report(path string, report map[string]json2.Any) ! {
	os.write_file(path, json2.encode(report, prettify: true, indent_string: '  ') + '\n')!
}
