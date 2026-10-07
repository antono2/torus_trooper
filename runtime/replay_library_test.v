// Checks replay migration, portable files, selection/editing, and retained gameplay settings.
module runtime

import os
import json2
import sim

fn library_fixture(name string, score int, timestamp i64) StoredReplay {
	return StoredReplay{
		valid:                true
		name:                 name
		score:                score
		recorded_at:          timestamp
		grade:                1
		starting_level:       3
		random_seed:          91832
		inputs:               [u8(0), 1, 2, 16, 32, 63]
		player_shot_distance: 55
	}
}

fn test_replay_library_migrates_old_save_and_sorts_without_changing_storage() {
	old := library_fixture('Old run', 42, 0)
	mut data := PlayerData{ version: 13, replay: old }
	data.normalize()
	data.normalize()
	assert data.replays.len == 1
	data.replays << library_fixture('New', 20, 100)
	data.replays << library_fixture('Best', 90, 50)
	assert replay_library_order(data.replays, false) == [1, 2, 0]
	assert replay_library_order(data.replays, true) == [2, 0, 1]
	assert data.replays[0].name == 'Old run'
	assert replay_date(old).contains('UNKNOWN')
}

fn test_portable_replay_round_trip_and_invalid_files() {
	directory := os.join_path(os.temp_dir(), 'tt-replay-${os.getpid()}')
	os.mkdir_all(directory) or { panic(err) }
	defer { os.rmdir_all(directory) or {} }
	path := os.join_path(directory, 'run.ttr')
	replay := library_fixture('My best run', 12345, 100)
	export_replay_file(path, replay) or { panic(err) }
	loaded := import_replay_file(path) or { panic(err) }
	assert loaded.name == replay.name
	assert loaded.score == replay.score
	assert loaded.recorded_at == replay.recorded_at
	assert loaded.simulation_replay().inputs == replay.inputs
	assert loaded.simulation_replay().player_shot_distance == 55
	export_replay_file(path, replay) or {
		assert err.msg().contains('exists')
		os.write_file(path, '{"replay":{"valid":true}}') or { panic(err) }
		import_replay_file(path) or {
			assert err.msg().contains('format')
			mut invalid := replay
			invalid.inputs = [u8(128)]
			os.write_file(path, json2.encode(ReplayFile{ format: 'torus-trooper-replay', version: 1, replay: invalid })) or { panic(err) }
			import_replay_file(path) or {
				assert err.msg().contains('invalid')
				return
			}
			assert false, 'invalid input was accepted'
			return
		}
		assert false, 'missing format was accepted'
		return
	}
	assert false, 'export overwrote an existing file'
}

fn test_library_rename_selection_import_and_cancel() {
	mut data := PlayerData{
		replays: [library_fixture('Old', 100, 200), library_fixture('Other', 200, 100)]
	}
	mut library := ReplayLibrary{ open: true }
	assert library.event(-83, mut data, '', '') == -1
	assert library.by_score
	library.event(-82, mut data, '', '')
	assert library.mode == .rename
	library.text = '  My best run  '
	library.event(-257, mut data, '', '')
	assert library.data_changed
	assert data.replays[1].name == 'My best run'
	assert library.event(-257, mut data, '', '') == 1
	assert data.high_scores == [0, 0, 0]
	library.open = true
	library.event(-261, mut data, '', '')
	library.event(-256, mut data, '', '')
	assert data.replays.len == 2
	library.event(-261, mut data, '', '')
	library.event(-89, mut data, '', '')
	assert data.replays.len == 1
	assert library.event(-256, mut data, '', '') == -2
	assert !library.open
	assert replay_clean_name('  A\nB  ') == 'AB'
	assert replay_clean_name('ä'.repeat(50)).runes().len == 48
}

fn test_deleting_last_replay_does_not_restore_the_legacy_copy() {
	mut data := PlayerData{ replays: [library_fixture('Last', 10, 100)] }
	data.sync_latest_replay()
	mut library := ReplayLibrary{ open: true }
	library.event(-261, mut data, '', '')
	library.event(-257, mut data, '', '')
	data.normalize()
	assert data.replays.len == 0
	assert !data.replay.valid
}

fn test_text_selection_replaces_and_import_never_changes_scores() {
	mut data := PlayerData{ replays: [library_fixture('First', 10, 100)] }
	mut library := ReplayLibrary{ open: true }
	library.event(-82, mut data, '', '')
	library.event(-1001, mut data, '', '')
	library.event(int(`N`), mut data, '', '')
	library.event(-257, mut data, '', '')
	assert data.replays[0].name == 'N'
	directory := os.join_path(os.temp_dir(), 'tt-import-${os.getpid()}')
	os.mkdir_all(directory) or { panic(err) }
	defer { os.rmdir_all(directory) or {} }
	path := os.join_path(directory, 'best.ttr')
	export_replay_file(path, library_fixture('Best', 999999, 200)) or { panic(err) }
	library.import_file(path, mut data)
	assert library.data_changed
	assert data.replays.len == 2
	assert data.high_scores == [0, 0, 0]
	assert data.reached_levels == [1, 1, 1]
	assert library.event(-257, mut data, '', '') == 1
}

fn test_replay_captures_gameplay_settings_for_deterministic_playback() {
	mut live := sim.new_simulation(sim.SimulationConfig{
		...gameplay_config_with_seed(.normal, 1, 91)
		player_shot_distance: 55
	})
	mut inputs := []u8{}
	for tick in 0 .. 360 {
		input := sim.InputState{ left: tick % 80 < 40, right: tick % 80 >= 40, fire: tick % 3 != 0 }
		inputs << sim.encode_input(input)
		live.update_with_input(input)
	}
	replay := completed_run_replay(.normal, 1, &live, inputs)
	app := App{}
	mut playback := app.new_replay_simulation(replay)
	for input in replay.inputs {
		playback.update_with_input(sim.decode_input(input))
	}
	assert playback.score == live.score
	assert playback.ship.course_position == live.ship.course_position
	assert playback.ship.hits == live.ship.hits
	assert playback.config.player_shot_distance == 55
}
