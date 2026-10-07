// Creates seeded game/replay sessions and transfers completed run data into persistent records.
module runtime

import sim

// Construct live and recorded sessions without sharing mutable replay input.

fn gameplay_config(grade sim.Grade, starting_level int) sim.SimulationConfig {
	return gameplay_config_with_seed(grade, starting_level, u64(0x6d2b79f5))
}

fn next_game_seed(mut source sim.Mt19937) u64 {
	return u64(source.next_u32())
}

fn completed_run_replay(grade sim.Grade, starting_level int, simulation &sim.Simulation,
	inputs []u8) sim.Replay {
	return sim.Replay{
		grade:                grade
		starting_level:       starting_level
		random_seed:          simulation.config.random_seed
		inputs:               inputs.clone()
		player_shot_distance: simulation.config.player_shot_distance
		god_mode:             simulation.god_mode
	}
}

fn replay_for_title_return(previous sim.Replay, grade sim.Grade, starting_level int,
	simulation &sim.Simulation, inputs []u8) sim.Replay {
	if inputs.len == 0 {
		return previous
	}
	return completed_run_replay(grade, starting_level, simulation, inputs)
}

fn gameplay_config_with_seed(grade sim.Grade, starting_level int, random_seed u64) sim.SimulationConfig {
	return sim.SimulationConfig{
		grade:                 grade
		starting_level:        starting_level
		random_seed:           random_seed
		collisions:            true
		enemy_interval:        90
		enemy_fire_interval:   75
		stage_progression:     true
		procedural_course:     true
		run_time_ms:           sim.default_run_time_ms
		release_before_action: true
		barrage:               sim.Barrage{ name: 'enemy_owned_fire', emitters: [] }
	}
}

fn replay_gameplay_config_with_seed(grade sim.Grade, starting_level int, random_seed u64) sim.SimulationConfig {
	config := gameplay_config_with_seed(grade, starting_level, random_seed)
	return sim.SimulationConfig{
		...config
		replay_mode: true
	}
}

fn with_compute_backend(config sim.SimulationConfig, backend sim.ComputeBackend) sim.SimulationConfig {
	return sim.SimulationConfig{
		...config
		compute_backend: backend
	}
}

fn (app &App) new_simulation(config sim.SimulationConfig) sim.Simulation {
	calibrated_config := sim.SimulationConfig{
		...config
		player_shot_distance: app.object_sizes.player_shot_distance
	}
	mut simulation := sim.new_simulation(calibrated_config)
	simulation.attach_compute_session(app.compute_session)
	simulation.god_mode = app.god_mode
	return simulation
}

fn (app &App) new_replay_simulation(replay sim.Replay) sim.Simulation {
	base := with_compute_backend(replay_gameplay_config_with_seed(replay.grade, replay.starting_level, replay.random_seed), app.compute_backend)
	mut simulation := sim.new_simulation(sim.SimulationConfig{
		...base
		player_shot_distance: replay.player_shot_distance
	})
	simulation.attach_compute_session(app.compute_session)
	simulation.god_mode = replay.god_mode
	return simulation
}

