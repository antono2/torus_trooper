module runtime

import sim

struct SuspendedRun {
	valid          bool
	simulation     sim.Simulation
	inputs         []u8
	grade          sim.Grade
	starting_level int
	paused         bool
	music          MusicSequence
}

fn suspend_run(simulation &sim.Simulation, inputs []u8, grade sim.Grade,
	starting_level int, paused bool, music MusicSequence) SuspendedRun {
	return SuspendedRun{
		valid:          true
		// The menu replaces its simulation with a separate replay instance.
		// Preserve a value copy rather than the heap-promoted live variable.
		simulation:     sim.Simulation{ ...simulation }
		inputs:         inputs.clone()
		grade:          grade
		starting_level: starting_level
		paused:         paused
		music:          music
	}
}

fn (app &App) finish_suspended_run(saved SuspendedRun, mut data PlayerData) {
	if !saved.valid || saved.inputs.len == 0 {
		return
	}
	replay := completed_run_replay(saved.grade, saved.starting_level, &saved.simulation, saved.inputs)
	data.record_result(saved.grade, saved.starting_level, int(saved.simulation.level), saved.simulation.score, replay)
	app.save_player_data_if_enabled(data)
}

fn controller_menu_input_mask(mask u32, title_mode bool, nested_menu bool,
	can_resume bool, controller_back bool, controller_start bool) u32 {
	if !title_mode {
		return mask
	}
	if controller_start && !controller_back && !nested_menu && !can_resume {
		return (mask & ~(input_back_bit | sim.input_charge_bit)) | sim.input_fire_bit
	}
	if !controller_back {
		return mask
	}
	// Cancel wins over confirm/charge, and must not open a replay at the root.
	return (mask & ~(sim.input_fire_bit | sim.input_charge_bit | input_restart_bit)) | if nested_menu || can_resume {
		input_back_bit
	} else {
		u32(0)
	}
}
