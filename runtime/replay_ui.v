// Connects replay-library input and rendering to the platform overlay and saved player data.
module runtime

import os
import font5x7

// Drain platform events until the library chooses a replay or closes. Leaving
// later events queued preserves the release-before-action boundary in App.run.
fn (app &App) take_replay_library_choice(mut library ReplayLibrary, mut data PlayerData) int {
	for {
		event := C.tt_platform_take_replay_event(app.platform)
		if event == 0 {
			return -1
		}
		clipboard := if event == -1000 {
			unsafe { C.tt_platform_clipboard(app.platform).vstring() }
		} else {
			''
		}
		export_directory := os.join_path(os.dir(app.player_data_path), 'replays')
		chosen := library.event(event, mut data, export_directory, clipboard)
		if library.data_changed { app.save_player_data_if_enabled(data) }
		if chosen != -1 { return chosen }
	}
	return -1
}

fn (app &App) draw_replay_library(replay_library ReplayLibrary, player_data PlayerData) {
	if replay_library.open {
		lines, selected_line := replay_library.lines(player_data)
		C.tt_platform_replay_overlay(app.platform, true, replay_library.mode in [
			.rename,
			.import_path,
			.export_path,
		], selected_line)
		for line in lines {
			codes := line.runes().map(u8(font5x7.code_for_rune(it)))
			C.tt_platform_replay_line(app.platform, codes.data, codes.len)
		}
	}
}
