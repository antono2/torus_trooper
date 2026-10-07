// Imports, exports, sorts, and edits saved replay records without changing recorded gameplay.
module runtime

import json2
import os
import sim
import time

// Version the portable format separately from preferences. Tick inputs require
// the same simulation rules; reject future formats rather than misplaying them.
const replay_file_version = 1
const replay_max_ticks = 60 * 60 * 60
const replay_max_file_bytes = 16 * 1024 * 1024

struct ReplayFile {
	format  string
	version int
	replay  StoredReplay
}

fn replay_is_valid(replay StoredReplay) bool {
	return replay.valid && replay.grade >= 0 && replay.grade <= 2
		&& replay.starting_level >= 1 && replay.starting_level <= 999
		&& replay.player_shot_distance >= player_shot_distance_min && replay.player_shot_distance <= player_shot_distance_max
		&& replay.score >= 0 && replay.inputs.len > 0 && replay.inputs.len <= replay_max_ticks
		&& replay.inputs.all(it <= 63)
}

fn (replay StoredReplay) simulation_replay() sim.Replay {
	return sim.Replay{
		grade:                unsafe { sim.Grade(replay.grade) }
		starting_level:       replay.starting_level
		random_seed:          replay.random_seed
		inputs:               replay.inputs.clone()
		player_shot_distance: replay.player_shot_distance
		god_mode:             replay.god_mode
	}
}

fn import_replay_file(path string) !StoredReplay {
	if !os.is_file(path) || os.file_size(path) > replay_max_file_bytes {
		return error('Choose a replay file smaller than 16 MB.')
	}
	file := json2.decode[ReplayFile](os.read_file(path)!)!
	if file.format != 'torus-trooper-replay' || file.version != replay_file_version {
		return error('This replay format is not supported.')
	}
	if !replay_is_valid(file.replay) {
		return error('Replay data is invalid or exceeds one hour.')
	}
	return file.replay
}

fn export_replay_file(path string, replay StoredReplay) ! {
	if !replay_is_valid(replay) {
		return error('Replay data is invalid.')
	}
	if os.exists(path) {
		return error('File exists. Choose another filename.')
	}
	os.write_file(path, json2.encode(ReplayFile{ format: 'torus-trooper-replay', version: replay_file_version, replay: replay },
		prettify: true
	))!
}

fn replay_library_order(replays []StoredReplay, by_score bool) []int {
	mut order := []int{}
	for index in 0 .. replays.len {
		order << index
	}
	// Stable insertion sort keeps equal scores in recording order.
	for i in 1 .. order.len {
		mut j := i
		for j > 0 {
			a := replays[order[j]]
			b := replays[order[j - 1]]
			comes_first := if by_score {
				a.score > b.score || (a.score == b.score && a.recorded_at > b.recorded_at)
			} else {
				a.recorded_at > b.recorded_at
			}
			if !comes_first {
				break
			}
			order[j], order[j - 1] = order[j - 1], order[j]
			j--
		}
	}
	return order
}

fn replay_date(replay StoredReplay) string {
	if replay.recorded_at <= 0 {
		return 'OLD REPLAY - DATE UNKNOWN'
	}
	return time.unix(replay.recorded_at).local().format_ss()
}

fn replay_clean_name(value string) string {
	runes := value.trim_space().runes().filter(it >= 32 && it != 127)
	return runes[..int_min(runes.len, 48)].map(it.str()).join('')
}

enum ReplayLibraryMode {
	list
	rename
	browse
	import_path
	export_path
	delete_confirm
}

struct ReplayLibrary {
mut:
	data_changed  bool
	open          bool
	mode          ReplayLibraryMode
	selected      int
	by_score      bool
	text          string
	select_all    bool
	message       string
	directory     string
	files         []string
	file_selected int
}

fn (mut library ReplayLibrary) browse(directory string) {
	library.directory = directory
	library.files = ['..']
	mut names := os.ls(directory) or {
		library.message = 'Cannot read directory.'
		return
	}
	names.sort()
	for name in names {
		if os.is_dir(os.join_path(directory, name)) || name.ends_with('.ttr') || name.ends_with('.json') {
			library.files << name
		}
	}
	library.file_selected = 0
	library.mode = .browse
}

// Return a storage index to play, -2 to close, or -1 to keep browsing.
fn (mut library ReplayLibrary) event(event int, mut data PlayerData, export_directory string, clipboard string) int {
	library.data_changed = false
	order := replay_library_order(data.replays, library.by_score)
	library.selected = clamp_int(library.selected, 0, int_max(order.len - 1, 0))
	index := if order.len > 0 { order[library.selected] } else { -1 }
	editing := library.mode in [.rename, .import_path, .export_path]
	if editing {
		if event > 0 && library.text.runes().len < 1024 {
			if library.select_all {
				library.text = ''
				library.select_all = false
			}
			library.text += rune(event).str()
		} else if event == -1001 {
			library.select_all = true
		} else if event == -1000 {
			if library.select_all {
				library.text = ''
				library.select_all = false
			}
			library.text += clipboard.replace('\n', '').replace('\r', '').limit(1024)
		} else if event == -259 {
			if library.select_all {
				library.text = ''
				library.select_all = false
				return -1
			}
			runes := library.text.runes()
			if runes.len > 0 {
				library.text = runes[..runes.len - 1].map(it.str()).join('')
			}
		} else if event == -256 {
			library.mode = .list
		} else if event == -257 {
			match library.mode {
				.rename {
					name := replay_clean_name(library.text)
					if name.len == 0 {
						library.message = 'Enter a name.'
						return -1
					}
					data.replays[index].name = name
					library.data_changed = true
					data.sync_latest_replay()
					library.message = 'Replay renamed.'
				}
				.import_path {
					return library.import_file(library.text, mut data)
				}
				.export_path {
					export_replay_file(library.text, data.replays[index]) or {
						library.message = err.msg()
						return -1
					}
					library.message = 'Replay exported.'
				}
				else {}
			}
			library.mode = .list
		}
		return -1
	}
	library.select_all = false
	if library.mode == .delete_confirm {
		if event == -89 || event == -257 {
			data.replays.delete(index)
			data.sync_latest_replay()
			library.data_changed = true
			library.selected = int_max(library.selected - 1, 0)
			library.message = 'Replay removed from library.'
		}
		library.mode = .list
		return -1
	}
	if library.mode == .browse {
		if event == -256 {
			library.mode = .list
		}
		if event == -265 {
			library.file_selected = int_max(0, library.file_selected - 1)
		}
		if event == -264 {
			library.file_selected = int_min(library.files.len - 1, library.file_selected + 1)
		}
		if event == -80 {
			library.mode = .import_path
			library.text = library.directory + os.path_separator
		}
		if event == -257 {
			path := os.real_path(os.join_path(library.directory, library.files[library.file_selected]))
			if os.is_dir(path) {
				library.browse(path)
			} else {
				return library.import_file(path, mut data)
			}
		}
		return -1
	}
	match event {
		-256 {
			library.open = false
			return -2
		}
		-265 { library.selected = int_max(0, library.selected - 1) }
		-264 { library.selected = int_min(int_max(order.len - 1, 0), library.selected + 1) }
		-83, -262, -263 {
			library.by_score = !library.by_score
			library.selected = 0
		}
		-73 {
			library.message = ''
			library.browse(os.home_dir())
		}
		-257 {
			if index >= 0 {
				library.open = false
				return index
			}
		}
		-82 {
			if index >= 0 {
				library.mode = .rename
				library.text = data.replays[index].name
				library.message = ''
			}
		}
		-69 {
			if index >= 0 {
				os.mkdir_all(export_directory) or {
					library.message = err.msg()
					return -1
				}
				library.mode = .export_path
				library.text = os.join_path(export_directory, 'replay-${data.replays[index].recorded_at}-${index}.ttr')
				library.message = ''
			}
		}
		-261 {
			if index >= 0 {
				library.mode = .delete_confirm
			}
		}
		else {}
	}
	return -1
}

fn (mut library ReplayLibrary) import_file(path string, mut data PlayerData) int {
	replay := import_replay_file(path) or {
		library.message = err.msg()
		return -1
	}
	data.replays << replay
	data.sync_latest_replay()
	library.data_changed = true
	library.mode = .list
	library.by_score = false
	order := replay_library_order(data.replays, false)
	library.selected = order.index(data.replays.len - 1)
	library.message = 'Imported. Press ENTER to play.'
	return -1
}

fn (library ReplayLibrary) lines(data PlayerData) ([]string, int) {
	mut lines := ['REPLAY LIBRARY', '']
	mut active := -1
	if library.mode in [.rename, .import_path, .export_path] {
		label := match library.mode {
			.rename { 'NAME YOUR REPLAY' }
			.import_path { 'IMPORT REPLAY - FILE PATH' }
			else { 'EXPORT REPLAY - FILE PATH' }
		}
		lines << label
		lines << ''
		// Show the end of long paths while typing; the filesystem uses the full text.
		runes := library.text.runes()
		tail := if runes.len > 61 {
			runes[runes.len - 61..].map(it.str()).join('')
		} else {
			library.text
		}
		lines << tail + '_'
		if library.select_all { lines << 'ALL TEXT SELECTED' } else { lines << '' }
		active = 4
		lines << ''
		lines << 'TYPE TO EDIT - CTRL+A: SELECT ALL - CTRL+V: PASTE'
		lines << 'ENTER TO CONFIRM - ESC TO CANCEL'
	} else if library.mode == .browse {
		lines << 'IMPORT REPLAY - CHOOSE A FILE'
		lines << library.directory
		start := (library.file_selected / 12) * 12
		for i in start .. int_min(start + 12, library.files.len) {
			name := library.files[i]
			prefix := if os.is_dir(os.join_path(library.directory, name)) {
				'[DIR] '
			} else {
				'      '
			}
			if i == library.file_selected {
				active = lines.len
			}
			lines << prefix + name
		}
		lines << ''
		lines << 'UP/DOWN: CHOOSE - ENTER: OPEN - P: TYPE OR PASTE PATH'
		lines << 'ESC: BACK'
	} else if library.mode == .delete_confirm {
		lines << 'REMOVE THIS REPLAY FROM YOUR LIBRARY?'
		lines << 'Y OR ENTER: REMOVE - ANY OTHER KEY: CANCEL'
	} else {
		lines << 'SORT: ' + if library.by_score {
			'HIGHEST SCORE FIRST'
		} else {
			'NEWEST RECORDING FIRST'
		}
		lines << 'NAME / RECORDING TIME / SCORE / DURATION'
		order := replay_library_order(data.replays, library.by_score)
		if order.len == 0 { lines << 'NO SAVED REPLAYS. FINISH A RUN OR IMPORT A FILE.' }
		start := (library.selected / 5) * 5
		for i in start .. int_min(start + 5, order.len) {
			replay := data.replays[order[i]]
			if i == library.selected {
				active = lines.len
			}
			name := if replay.name.len > 0 { replay.name } else { 'Unnamed replay' }
			lines << '${i + 1}. ${name}'
			seconds := replay.inputs.len / 60
			grade := ['NORMAL', 'HARD', 'EXTREME'][replay.grade]
			lines << '   ${replay_date(replay)}  SCORE ${replay.score}  ${seconds / 60}:${seconds % 60:02}  ${grade} LV ${replay.starting_level}'
		}
		lines << ''
		lines << 'UP/DOWN: CHOOSE - ENTER: PLAY - S OR LEFT/RIGHT: SORT'
		lines << 'R: RENAME - I: IMPORT FILE - E: EXPORT FILE'
		lines << 'DELETE: REMOVE - ESC: BACK'
		lines << 'IMPORTED SCORES DO NOT CHANGE YOUR PERSONAL BEST.'
	}
	lines << ''
	lines << library.message
	return lines, active
}

fn (mut data PlayerData) sync_latest_replay() {
	order := replay_library_order(data.replays, false)
	data.replay = if order.len > 0 { data.replays[order[0]] } else { StoredReplay{} }
}
