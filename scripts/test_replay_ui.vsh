// Drive the real X11 replay menus and check the saved and exported recordings.
import os
import scripts.testrun
import time
import x.json2

const test_resolution = ['640', '360']
const launch_timeout = 60 * time.second
const frame_timeout = 30 * time.second
const poll_interval = 250 * time.millisecond
const frames_per_input = 2
const settings_menu_offset = 3
const replay_menu_offset = 4
const replay_name = 'First flight'
const start_event = 'Run started:'
const suspend_event = 'Run suspended: '
const resume_event = 'Run resumed: '
const library_commands = ['r', 'e', 'i', 'p', 's', 'y', 'Delete']

struct TestSettings {
	version              int = 14
	antialiasing_samples int = 1
	near_blur_percent    int
	// Limit geometry so software Vulkan can render enough frames to sample held keys.
	track_draw_distance  int = 16
	wire_draw_distance   int = 16
	border_draw_distance int = 16
}

// Use typed numbers so the saved random seed retains all 64 bits.
struct ReplayRecord {
	name                 string
	recorded_at          i64
	score                int
	valid                bool
	grade                int
	starting_level       int
	random_seed          u64
	inputs               []u8
	player_shot_distance f32
	god_mode             bool
}

struct PlayerData {
	replays     []ReplayRecord
	high_scores []int
}

struct ExportedReplay {
	replay ReplayRecord
}

struct TestWindow {
	root        string
	work        string
	screenshots string
mut:
	id         string
	game       &os.Process
	properties &os.Process
	rendered   int
	log        string
}

fn require(ok bool, message string) ! {
	if !ok {
		return error(message)
	}
}

fn path_for(command string) !string {
	if os.is_abs_path(command) {
		return command
	}
	return os.find_abs_path_of_executable(command)
}

fn (window TestWindow) command(args []string) !string {
	result := testrun.capture(path_for(args[0])!, args[1..], window.root, os.environ(),
		8 * time.second)!
	return result.stdout.trim_space()
}

fn (window TestWindow) xdo(args ...string) !string {
	mut command := ['xdotool']
	command << args
	return window.command(command)
}

fn (mut window TestWindow) collect_game() {
	window.log += window.game.stdout_read() + window.game.stderr_read()
}

fn (mut window TestWindow) game_running() ! {
	window.collect_game()
	require(window.game.is_alive(), 'The game quit before the replay check finished')!
}

fn (mut window TestWindow) wait_for_event(event string, count int, timeout time.Duration) ! {
	deadline := time.sys_mono_now() + timeout
	for time.sys_mono_now() < deadline {
		window.game_running()!
		if window.log.count(event) >= count {
			return
		}
		time.sleep(poll_interval)
	}
	return error('Timed out waiting for ${event}')
}

fn (mut window TestWindow) wait_frames(target int) ! {
	deadline := time.sys_mono_now() + frame_timeout
	for time.sys_mono_now() < deadline {
		window.game_running()!
		require(window.properties.is_alive(), 'The X11 frame observer exited')!
		window.rendered += window.properties.stdout_read().count('\n')
		if window.rendered >= target {
			return
		}
		time.sleep(poll_interval)
	}
	return error('Timed out waiting for rendered input frames')
}

fn (mut window TestWindow) press(key string) ! {
	window.rendered += window.properties.stdout_read().count('\n')
	target := window.rendered + frames_per_input
	if key.starts_with('ctrl+') || key in library_commands {
		// A held letter can repeat into the text field opened by the command.
		window.xdo('key', '--clearmodifiers', key)!
		window.wait_frames(target)!
		return
	}
	window.xdo('keydown', key)!
	window.wait_frames(target) or {
		window.xdo('keyup', key) or {}
		return err
	}
	window.rendered += window.properties.stdout_read().count('\n')
	window.xdo('keyup', key)!
	window.wait_frames(window.rendered + frames_per_input)!
}

fn (mut window TestWindow) start_run(count int, timeout time.Duration) ! {
	window.xdo('keydown', 'Return')!
	window.wait_for_event(start_event, count, timeout) or {
		window.xdo('keyup', 'Return') or {}
		return err
	}
	window.xdo('keyup', 'Return')!
}

fn (mut window TestWindow) wait_for_progress() ! {
	// A clock change proves that gameplay ticked before the suspend recording.
	deadline := time.sys_mono_now() + frame_timeout
	for time.sys_mono_now() < deadline {
		window.game_running()!
		title := window.xdo('getwindowname', window.id)!
		if title.contains('TIME 1:') || title.contains('TIME 0:') {
			return
		}
		time.sleep(poll_interval)
	}
	return error('No game time elapsed before suspension')
}

fn (window TestWindow) screenshot(name string) ! {
	if window.screenshots != '' {
		os.mkdir_all(window.screenshots)!
		window.command(['import', '-window', window.id, os.join_path(window.screenshots, name +
			'.png')])!
	}
}

fn (window TestWindow) player_data() !PlayerData {
	return json2.decode[PlayerData](os.read_file(os.join_path(window.work, 'player.json'))!)!
}

fn (window TestWindow) check_export() !string {
	data := window.player_data()!
	require(data.replays.len == 1 && data.replays[0].name == replay_name,
		'The replay library did not save the renamed recording')!
	dir := os.join_path(window.work, 'replays')
	files := os.ls(dir)!.filter(it.ends_with('.ttr'))
	require(files.len == 1, 'Expected one exported replay, found ${files}')!
	path := os.join_path(dir, files[0])
	exported := json2.decode[ExportedReplay](os.read_file(path)!)!
	require(exported.replay.inputs == data.replays[0].inputs, 'Export changed the recorded inputs')!
	return path
}

fn (window TestWindow) check_import() ! {
	data := window.player_data()!
	require(data.replays.len == 2 && data.replays[0] == data.replays[1],
		'Import did not exactly duplicate the exported recording')!
	require(data.high_scores.len > 0 && data.high_scores[0] == data.replays[0].score,
		'Import changed the saved best score')!
}

fn first_event(log string, prefix string) !string {
	for line in log.split_into_lines() {
		if line.starts_with(prefix) {
			return line[prefix.len..]
		}
	}
	return error('Missing event ${prefix}')
}

fn (mut window TestWindow) check_resume() ! {
	time.sleep(3 * time.second) // Let the startup title fade reach its interactive frame.
	window.start_run(1, 10 * time.second)!
	window.wait_for_progress()!
	window.press('Escape')!
	window.screenshot('suspended-start-menu')!
	for _ in 0 .. settings_menu_offset {
		window.press('Down')!
	}
	window.screenshot('selected-settings-menu')!
	window.press('Return')!
	window.screenshot('selected-setting')!
	window.press('Escape')!
	require(window.log.contains('Settings closed.'), 'Escape did not close nested settings')!
	window.press('Escape')!
	window.collect_game()
	suspended := first_event(window.log, suspend_event)!
	resumed := first_event(window.log, resume_event)!
	require(suspended == resumed && window.log.count(start_event) == 1,
		'Resume changed the suspended tick, score, or checksum')!
}

fn (mut window TestWindow) check_library() ! {
	window.press('Escape')!
	window.start_run(2, frame_timeout)!
	time.sleep(500 * time.millisecond)
	window.press('Escape')!
	for _ in 0 .. replay_menu_offset {
		window.press('Down')!
	}
	window.screenshot('title-screen')!
	window.press('Return')!
	window.screenshot('replay-library')!
	window.press('r')!
	window.press('ctrl+a')!
	window.xdo('type', '--delay', '80', replay_name)!
	window.press('Return')!
	window.screenshot('replay-library')!
	window.press('e')!
	window.press('Return')!
	path := window.check_export()!
	window.press('i')!
	window.screenshot('file-browser')!
	window.press('p')!
	window.press('ctrl+a')!
	window.xdo('type', '--delay', '30', path)!
	window.press('Return')!
	window.screenshot('imported-replay')!
	window.check_import()!
	window.press('s')!
	window.press('Return')!
	time.sleep(time.second)
	window.screenshot('replay-playback')!
	window.press('Escape')!
	window.game_running()!
	window.screenshot('back-to-library')!
	window.press('Delete')!
	window.press('y')!
	require(window.player_data()!.replays.len == 1,
		'Deleting an imported replay did not preserve one copy')!
	window.press('Escape')!
	window.game_running()!
}

fn stop(mut child os.Process) {
	if child.status == .not_started {
		return
	}
	if child.is_alive() {
		child.signal_term()
		deadline := time.sys_mono_now() + 2 * time.second
		for child.is_alive() && time.sys_mono_now() < deadline {
			time.sleep(10 * time.millisecond)
		}
		if child.is_alive() {
			child.signal_kill()
			child.status = .running
		}
	}
	child.wait()
}

fn run(args []string) ! {
	root := os.dir(@DIR)
	if args in [['--help'], ['-h']] {
		println('usage: xvfb-run -a v run scripts/test_replay_ui.vsh [PLAYER]')
		return
	}
	require(args.len <= 1 && os.getenv('DISPLAY') != '',
		'Use xvfb-run -a v run scripts/test_replay_ui.vsh [PLAYER]')!
	player := if args.len == 1 { os.abs_path(args[0]) } else { os.join_path(root, 'torus_trooper') }
	require(os.is_file(player) && os.is_executable(player), 'Build the player first: ${player}')!
	work := testrun.temporary_directory('torus-replay-ui-')!
	defer { os.rmdir_all(work) or {} }
	player_data := os.join_path(work, 'player.json')
	os.write_file(player_data, json2.encode(TestSettings{}))!
	mut window := TestWindow{
		root:        root
		work:        work
		screenshots: os.getenv('TT_REPLAY_SCREENSHOTS')
		game:        os.new_process(player)
		properties:  os.new_process(path_for('stdbuf')!)
	}
	mut arguments := ['--no-sound', '--volume', '0', '--res']
	arguments << test_resolution
	arguments << ['--data-file', player_data]
	window.game.set_work_folder(root)
	window.game.set_args(arguments)
	window.game.set_redirect_stdio()
	window.game.run()
	mut passed := false
	defer {
		stop(mut window.properties)
		stop(mut window.game)
		window.collect_game()
		window.properties.close()
		window.game.close()
		if !passed {
			eprintln(window.log)
		}
	}
	window.wait_for_event('Renderer bootstrap complete', 1, launch_timeout)!
	ids := window.xdo('search', '--sync', '--onlyvisible', '--name', '^Torus Trooper')!.fields()
	require(ids.len == 1, 'Expected one visible Torus window, found ${ids}')!
	window.id = ids[0]
	window.xdo('windowfocus', '--sync', window.id)!
	// The window title is updated once per menu/playback frame, even when unchanged.
	window.properties.set_args(['-oL', 'xprop', '-spy', '-id', window.id, '_NET_WM_NAME'])
	window.properties.set_redirect_stdio()
	window.properties.run()
	window.wait_frames(1)!
	window.check_resume()!
	window.check_library()!
	require(!window.log.to_lower_ascii().contains('validation error')
		&& !window.log.contains('VUID-'), 'Vulkan diagnostics were reported during replay')!
	if window.screenshots != '' {
		os.write_file(os.join_path(window.screenshots, 'game.log'), window.log)!
	}
	passed = true
	println('Replay UI passed: keyboard menu/resume, save, rename, export, import, sort, playback, remove, back.')
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
