// Sample Vulkan startup and gameplay on an X11 display.
import flag
import math
import os
import scripts.benchmarks
import scripts.testrun
import strconv
import time
import x.json2

$if linux {
	#flag -I @VMODROOT/scripts/benchmarks
	#flag -lX11
	#include "close_window.h"
}

fn C.tt_benchmark_close_window(window u64) int

const poll_interval = 50 * time.millisecond
const start_event = 'Run started: NORMAL'

struct RenderLog {
mut:
	text string
}

fn drain(mut child os.Process, mut log RenderLog) {
	log.text += child.stdout_read() + child.stderr_read()
}

fn wait_for_event(mut child os.Process, mut log RenderLog, marker string, timeout time.Duration) ! {
	deadline := time.sys_mono_now() + timeout
	for time.sys_mono_now() < deadline {
		drain(mut child, mut log)
		if !child.is_alive() {
			break
		}
		if log.text.contains(marker) {
			return
		}
		time.sleep(poll_interval)
	}
	return error('Timed out or exited while waiting for ${marker}\n${log.text}')
}

fn gameplay(root string, binary string, slot string, env map[string]string, duration time.Duration) !map[string]json2.Any {
	$if !linux {
		return error('The renderer benchmark requires X11 on Linux')
	}
	mut child := os.new_process(binary)
	child.set_args(benchmarks.player_arguments(slot))
	child.set_work_folder(root)
	child.set_environment(env)
	child.set_redirect_stdio()
	child.run()
	defer {
		if child.is_alive() {
			child.signal_kill()
			child.status = .running // Reap the child after signaling it on V 0.5.2.
		}
		child.wait()
		child.close()
	}
	mut log := RenderLog{}
	wait_for_event(mut child, mut log, 'Renderer bootstrap complete', benchmarks.probe_timeout)!
	windows := benchmarks.command(root, ['xdotool', 'search', '--sync', '--onlyvisible', '--pid',
		child.pid.str(), '--name', '^Torus Trooper'])!.fields()
	if windows.len == 0 {
		return error('Cannot find the benchmark window')
	}
	window := windows[0]
	benchmarks.command(root, ['xdotool', 'windowfocus', '--sync', window])!
	benchmarks.command(root, ['xdotool', 'keydown', 'Return'])!
	// Hold Start until a rendered frame acknowledges the key.
	wait_for_event(mut child, mut log, start_event, 30 * time.second) or {
		benchmarks.command(root, ['xdotool', 'keyup', 'Return']) or {}
		return err
	}
	benchmarks.command(root, ['xdotool', 'keyup', 'Return'])!
	end := time.sys_mono_now() + duration
	for time.sys_mono_now() < end && child.is_alive() {
		drain(mut child, mut log)
		time.sleep(poll_interval)
	}
	$if linux {
		if C.tt_benchmark_close_window(strconv.parse_uint(window, 10, 64)!) == 0 {
			return error('Window close request failed')
		}
	}
	deadline := time.sys_mono_now() + 20 * time.second
	for child.is_alive() && time.sys_mono_now() < deadline {
		drain(mut child, mut log)
		time.sleep(poll_interval)
	}
	if child.is_alive() {
		return error('Benchmark window did not close.\n${log.text}')
	}
	child.wait()
	drain(mut child, mut log)
	if child.code != 0 {
		return error(log.text)
	}
	record := benchmarks.profile(log.text)!
	timestamp_bits := record['timestamp_bits'] or {
		return error('Missing timestamp_bits in profile')
	}
	samples := record['samples'] or { return error('Missing samples in profile') }
	if timestamp_bits.f64() != 0 && samples.f64() <= 0 {
		return error('Supported GPU queries produced no samples.\n${log.text}')
	}
	return record
}

fn run() ! {
	mut parser := flag.new_flag_parser(os.args[1..])
	parser.application('benchmark_renderer')
	parser.arguments_description('BINARY')
	runs := parser.int('runs', 0, 5, 'startup measurements')
	seconds := parser.float('seconds', 0, 3, 'duration of the gameplay sample')
	output := parser.string('output', 0, '', 'JSON report path')
	if parser.bool('help', `h`, false, 'show usage') {
		println(parser.usage())
		return
	}
	args := parser.finalize()!
	if args.len != 1 || runs < 1 || !math.is_finite(seconds) || seconds <= 0 || output == '' {
		return error(parser.usage())
	}
	root := os.dir(@DIR)
	binary := benchmarks.executable(os.abs_path(args[0]))!
	work := testrun.temporary_directory('torus-renderer-benchmark-')!
	defer { os.rmdir_all(work) or {} }
	env := benchmarks.profiling_environment()
	mut records := []json2.Any{}
	for index in 0 .. runs {
		mut record :=
			benchmarks.probe(root, binary, os.join_path(work, 'probe-${index}.json'), env)!
		record['kind'] = json2.Any('startup')
		record['run'] = json2.Any(index + 1)
		records << json2.Any(record)
	}
	mut sample := gameplay(root, binary, os.join_path(work, 'game.json'), env,
		time.Duration(seconds * f64(time.second)))!
	sample['kind'] = json2.Any('gameplay')
	records << json2.Any(sample)
	mut report := benchmarks.renderer_report(root, binary)!
	report['validation_layers'] = json2.Any(env['VK_INSTANCE_LAYERS'])
	report['records'] = json2.Any(records)
	benchmarks.write_report(output, report)!
	println('Saved renderer measurements to ${output}')
}

run() or {
	eprintln(err)
	exit(1)
}
