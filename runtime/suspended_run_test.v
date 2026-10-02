module runtime

import sim

fn test_menu_replay_does_not_change_the_suspended_game() {
	config := gameplay_config_with_seed(.hard, 2, 12345)
	mut continuous := sim.new_simulation(config)
	mut live := sim.new_simulation(config)
	mut inputs := []u8{}
	for tick in 0 .. 180 {
		input := sim.InputState{ fire: true, left: tick % 30 < 15, brake: tick % 60 < 40 }
		continuous.update_with_input(input)
		live.update_with_input(input)
		inputs << sim.encode_input(input)
	}
	saved := suspend_run(&live, inputs, .hard, 2, true, MusicSequence{ track: 2, direction: -1 })
	checksum := live.checksum()
	live = sim.new_simulation(gameplay_config_with_seed(.normal, 1, 98765))
	inputs.clear()
	for _ in 0 .. 600 {
		live.update_with_input(sim.InputState{})
	}
	assert saved.simulation.tick == 180
	assert saved.simulation.checksum() == checksum
	assert saved.inputs.len == 180
	assert saved.grade == .hard && saved.starting_level == 2
	assert saved.paused
	assert saved.music.track == 2 && saved.music.direction == -1
	live = sim.Simulation{ ...saved.simulation }
	for tick in 0 .. 180 {
		input := sim.InputState{ fire: tick % 2 == 0, right: true }
		continuous.update_with_input(input)
		live.update_with_input(input)
	}
	assert live.checksum() == continuous.checksum()
	assert live.remaining_time_ms == continuous.remaining_time_ms
	assert live.score == continuous.score
}

fn test_controller_b_cancels_nested_menus_without_charging_or_confirming() {
	assert controller_menu_input_mask(32, false, false, false, true, false) == 32
	assert controller_menu_input_mask(32, true, false, false, true, false) == 0
	assert controller_menu_input_mask(16 | 32 | 128, true, true, false, true, false) == 256
	assert controller_menu_input_mask(32, true, false, true, true, false) == 256
	assert controller_menu_input_mask(1 | 32, true, true, false, false, false) == 1 | 32
	assert controller_menu_input_mask(256, true, false, false, false, true) == 16
	assert controller_menu_input_mask(256, true, false, true, false, true) == 256
	assert controller_menu_input_mask(256, true, true, false, false, true) == 256
	assert controller_menu_input_mask(256, false, false, false, false, true) == 256
	assert controller_menu_input_mask(256, true, false, true, false, false) == 256
}
