// Fixed-step game state, entity lifecycles, collision resolution, scoring, and seeded gameplay.
module sim

import math

pub struct Vec2 {
pub mut:
	x f32
	y f32
}

pub struct InputState {
pub:
	left  bool
	right bool
	up    bool
	down  bool
	fire  bool
	brake bool
}

pub struct Ship {
pub mut:
	angle                    f32
	eye_angle                f32
	bank                     f32
	relative_depth           f32
	presentation_depth_step  f32
	presentation_eye_step    f32
	presentation_angle_step  f32
	presentation_bank_step   f32
	presentation_course_step f32
	target_speed             f32
	speed                    f32
	distance                 f32
	course_position          f32
	lap                      int = 1
	sight_depth              f32 = ship_base_sight_depth
	screen_shake_ticks       int
	screen_shake_intensity   f32
	camera_shake_angle       f32
	camera_shake_x           f32
	camera_shake_y           f32
	regenerative_charge      f32
	hits                     int
	invulnerable_ticks       int = ship_spawn_invulnerability_ticks
	lifecycle_counter        int = -ship_spawn_invulnerability_ticks
}

pub struct Bullet {
pub mut:
	alive             bool
	position          Vec2
	previous_position Vec2
	direction         f32
	speed             f32
	age               int
	program_id        int = -1
	next_step         int
	speed_delta       f32
	speed_ticks       int
	direction_delta   f32
	direction_ticks   int
	x_reverse         f32 = 1
	visual_shape      int
	visual_scale      f32 = 1
	long_range        bool
	speed_rank        f32 = 1
	disappear_ticks   int
}

struct BulletPatternState {
mut:
	active         bool
	runner         PatternRunner
	pipeline       PatternPipeline
	pipeline_index int
	morph_seed     bool
}

struct EnemyPatternRoot {
mut:
	active   bool
	runner   ParallelPatternRunner
	pipeline PatternPipeline
}

struct PendingPatternShot {
	position       Vec2
	program        PatternProgram
	rank           f32
	shot           PatternShot
	pipeline       PatternPipeline
	pipeline_index int
}

pub struct Shot {
pub mut:
	alive        bool
	position     Vec2
	direction    f32
	range        f32
	age          int
	charged      bool
	charging     bool
	charge_ticks int
	damage       int = 1
	multiplier   int = 1
	star_shell   bool
	size         f32 = 1
	target_size  f32 = 1
}

pub struct Enemy {
pub mut:
	alive             bool
	position          Vec2
	health            int
	age               int
	kind              int
	score             int = 100
	pattern           int
	base_turn         f32
	turn_speed        f32
	rank_counted      bool
	spec_index        int
	speed             f32
	limit_depth       f32
	previous_position Vec2
	flip_velocity     Vec2
	flip_ticks        int
	damaged           bool
	barrage_root      EnemyPatternRoot
	bit_barrage_roots []EnemyPatternRoot
}

struct EnemyFire {
	position   Vec2
	kind       int
	spec_index int
	age        int
}

pub struct Particle {
pub mut:
	alive                   bool
	position                Vec2
	velocity                Vec2
	life                    int
	initial_life            int
	kind                    ParticleKind
	visual_tier             int
	height                  f32
	height_velocity         f32
	in_course               bool = true
	luminosity              f32 = 1
	spin                    f32
	spin_velocity           f32
	secondary_spin          f32
	secondary_spin_velocity f32
	scale                   f32 = 1
	fragment_width          f32
	fragment_height         f32
}

// MultiplierPopup presents floating X2-X100 letters. It remains
// presentation-only: its independent RNG and fixed pool cannot perturb any
// gameplay stream or collision result.
pub struct MultiplierPopup {
pub mut:
	alive       bool
	position    Vec2
	velocity    Vec2
	life        int
	alpha       f32
	multiplier  int
	large_label bool
}

pub enum ParticleKind {
	spark
	jet
	star
	fragment
}

struct DestructionBurst {
	position       Vec2
	enemy_kind     int
	collision_size Vec2
}

pub enum StepKind {
	change_speed
	change_direction
	vanish
}

// MotionStep is native game data. It deliberately models gameplay operations,
// rather than the structure or execution rules of any external pattern format.
pub struct MotionStep {
pub:
	at_age   int
	kind     StepKind
	target   f32
	duration int
}

pub struct MotionProgram {
pub:
	name  string
	steps []MotionStep
}

pub struct Emitter {
pub:
	position           Vec2
	interval           int = 30
	first_shot_tick    int
	bullets_per_volley int = 1
	spread             f32
	direction          f32
	bullet_speed       f32 = 0.1
	program_id         int = -1
}

pub struct Barrage {
pub:
	name     string
	emitters []Emitter = [Emitter{}]
}

pub struct SimulationConfig {
pub:
	compute_backend       ComputeBackend = .cpu
	grade                 Grade
	starting_level        int = 1
	bullet_capacity       int = 512
	shot_capacity         int = 64
	player_shot_distance  f32 = source_player_shot_distance
	enemy_capacity        int = 64
	particle_capacity     int = 1024
	enemy_interval        int
	enemy_fire_interval   int
	enemy_bullet_speed    f32 = 0.055
	run_time_ms           int
	random_seed           u64 = 0x6d2b79f5
	barrage               Barrage = Barrage{}
	programs              []MotionProgram
	collisions            bool
	stage_progression     bool
	course_length         int = 5000
	procedural_course     bool
	replay_mode           bool
	release_before_action bool
}

pub struct Simulation {
pub:
	config SimulationConfig
pub mut:
	tick                     int
	bullets                  []Bullet
	bullet_patterns          []BulletPatternState
	shots                    []Shot
	enemies                  []Enemy
	passed_enemies           []Enemy
	particles                []Particle
	multiplier_popups        []MultiplierPopup
	ship                     Ship
	compute_stats            ComputeStats
	compute_session          &ComputeSession = unsafe { nil }
	fire_cooldown            int
	side_fire_cooldown       int = side_fire_idle_ticks
	charging_shot            int = -1
	fired_shots              int
	side_fired_shots         int
	bullets_cleared          int
	destroyed_enemies        int
	enemy_hits               int
	destroyed_small          int
	destroyed_middle         int
	destroyed_boss           int
	spawned_enemies          int
	enemy_shots_fired        int
	score                    int
	remaining_time_ms        int
	next_beep_time_ms        int = clock_warning_start_ms
	next_extend_score        int = 100000
	time_extensions          int
	time_change_ticks        int = -1
	time_change_seconds      int
	warning_beeps            int
	music_change_ticks       int = -1
	music_fades              int
	music_changes            int
	game_over                bool
	god_mode                 bool
	action_latched           bool
	level                    f32
	zone                     int = 1
	zone_advances            int
	stage                    StageProgression
	course                   CourseProfile
	zone_specs               ZoneEnemySpecs
	next_boss_spec           int
	next_small_distance      f32
	next_middle_distance     f32
	next_boss_distance       f32 = boss_distance_unscheduled
	zone_transition_ticks    int = -1
	palette_transition_ticks int = palette_transition_duration_ticks
	multiplier_popup_cursor  int
	next_star_distance       f32
	shot_cursor              int
	particle_cursor          int
	enemy_cursor             int
	passed_enemy_cursor      int
	// Independent streams keep gameplay subsystems from perturbing each other.
	// `random` remains the bullet/pattern stream for compatibility with callers.
	random                   Mt19937
	stage_random             Mt19937
	barrage_random           Mt19937
	enemy_random             Mt19937
	shot_random              Mt19937
	particle_random          Mt19937
	ship_random              Mt19937
	multiplier_popup_random  Mt19937
	ship_collision           Vec2
	default_enemy_collisions []Vec2
	shape_random             Mt19937
}

pub fn new_simulation(config SimulationConfig) Simulation {
	seed := u32(config.random_seed)
	mut stage_random := new_mt19937(seed)
	mut zone_specs := ZoneEnemySpecs{}
	mut next_small_distance := f32(0)
	mut next_middle_distance := f32(0)
	if config.stage_progression {
		setup := generate_zone_enemy_setup(f32(config.starting_level), config.grade, true, 0, mut stage_random)
		zone_specs = setup.specs
		next_small_distance = setup.next_small_distance
		next_middle_distance = setup.next_middle_distance
	}
	course := if config.procedural_course { generate_course(seed) } else { CourseProfile{} }
	shape_random := shape_random_after_zone(zone_specs, seed)
	return Simulation{
		config: config
		bullets: []Bullet{len: config.bullet_capacity}
		bullet_patterns: []BulletPatternState{len: config.bullet_capacity}
		shots: []Shot{len: config.shot_capacity}
		enemies: []Enemy{len: config.enemy_capacity}
		passed_enemies: []Enemy{len: config.enemy_capacity}
		particles: []Particle{len: config.particle_capacity}
		multiplier_popups: []MultiplierPopup{len: 16}
		remaining_time_ms: config.run_time_ms
		action_latched: config.release_before_action
		level: f32(config.starting_level)
		next_extend_score: extend_score_for_level(f32(config.starting_level))
		stage: new_stage_progression(config.grade, zone_specs.boss.len)
		course: course
		zone_specs: zone_specs
		next_small_distance: next_small_distance
		next_middle_distance: next_middle_distance
		random: new_mt19937(seed)
		stage_random: stage_random
		barrage_random: new_mt19937(seed)
		enemy_random: new_mt19937(seed)
		shot_random: new_mt19937(seed)
		particle_random: new_mt19937(seed)
		ship_random: new_mt19937(seed)
		multiplier_popup_random: new_mt19937(seed)
		ship_collision: ship_shape_collision(0, 1)
		default_enemy_collisions: [ship_shape_collision(0, 0), ship_shape_collision(1, 0),
			ship_shape_collision(2, 0)]
		shape_random: shape_random
	}
}

pub fn (mut simulation Simulation) update() {
	simulation.update_with_input(InputState{})
}

pub fn (mut simulation Simulation) update_with_input(input InputState) {
	previous_relative_depth := simulation.ship.relative_depth
	previous_eye_angle := simulation.ship.eye_angle
	previous_angle := simulation.ship.angle
	previous_bank := simulation.ship.bank
	previous_course_position := simulation.ship.course_position
	simulation.update_music_transition()
	mut active_input := input
	if simulation.action_latched {
		if active_input.fire || active_input.brake {
			active_input = InputState{
				...active_input
				fire: false
				brake: false
			}
		} else {
			simulation.action_latched = false
		}
	}
	next_lifecycle_counter := simulation.ship.lifecycle_counter + 1
	respawning := !simulation.game_over && simulation.ship.lifecycle_counter < -ship_spawn_invulnerability_ticks
		&& next_lifecycle_counter == -ship_spawn_invulnerability_ticks
	if simulation.game_over {
		active_input = InputState{}
		simulation.ship.speed *= 0.9
		simulation.clear_live_bullets()
		if next_lifecycle_counter < -ship_spawn_invulnerability_ticks {
			// The source holds a destroyed ship at the start of its restart delay
			// for as long as the game-over presentation remains active.
			simulation.ship.lifecycle_counter = -ship_respawn_protection_ticks - 1
		}
	} else if next_lifecycle_counter < -ship_spawn_invulnerability_ticks {
		active_input = InputState{}
		simulation.ship.relative_depth *= 0.99
		simulation.clear_live_bullets()
	}
	simulation.update_ship(active_input)
	// These render-only deltas preserve the fixed 60 Hz gameplay model while
	// allowing a high-refresh presentation to move the camera continuously.
	// Without them the nearest panels jump whenever depth or steering changes,
	// which reads as flashing on 144/165 Hz displays.
	simulation.ship.presentation_depth_step = simulation.ship.relative_depth - previous_relative_depth
	simulation.ship.presentation_eye_step = angle_delta(previous_eye_angle, simulation.ship.eye_angle)
	simulation.ship.presentation_angle_step = angle_delta(previous_angle, simulation.ship.angle)
	simulation.ship.presentation_bank_step = simulation.ship.bank - previous_bank
	simulation.ship.presentation_course_step = wrapped_course_delta(previous_course_position, simulation.ship.course_position, simulation.active_course_length())
	simulation.update_weapon(active_input)
	simulation.spawn_ship_particles()
	simulation.update_enemies()
	simulation.update_shots()
	for emitter in simulation.config.barrage.emitters {
		if simulation.tick < emitter.first_shot_tick
			|| (simulation.tick - emitter.first_shot_tick) % emitter.interval != 0 {
			continue
		}
		for shot in 0 .. emitter.bullets_per_volley {
			mut offset := f32(0)
			if emitter.bullets_per_volley > 1 {
				offset = (f32(shot) / f32(emitter.bullets_per_volley - 1) - 0.5) * emitter.spread
			}
			simulation.spawn(emitter.position, emitter.direction + offset, emitter.bullet_speed, emitter.program_id)
		}
	}
	// Enemy emitters still advance while the destroyed ship is hidden. Clear
	// everything after they run on the exact reappearance tick, otherwise a
	// newly emitted wave can survive the gradual death-window cleanup and meet
	// the player as one unavoidable cloud.
	if respawning {
		simulation.remove_live_bullets()
	}
	simulation.update_bullets()
	simulation.update_particles()
	simulation.update_multiplier_popups()
	simulation.update_clock()
	simulation.sample_screen_shake()
	simulation.tick++
}

fn (mut simulation Simulation) update_bullets() {
	mut pending := []PendingPatternShot{}
	for index in 0 .. simulation.bullets.len {
		mut bullet := simulation.bullets[index]
		mut pattern := simulation.bullet_patterns[index]
		if !bullet.alive {
			pattern.active = false
			simulation.bullet_patterns[index] = pattern
			continue
		}
		bullet.previous_position = bullet.position
		if pattern.active {
			pattern.runner.sync_owner(bullet.direction, bullet.speed, aim_direction_reversed(bullet.position, Vec2{ x: simulation.ship.angle, y: simulation.ship.relative_depth }, bullet.x_reverse))
			shots := pattern.runner.tick(mut simulation.random) or { []PatternShot{} }
			bullet.direction = pattern.runner.direction
			bullet.speed = pattern.runner.speed
			for shot in shots {
				pending << PendingPatternShot{
					position: bullet.position
					program: pattern.runner.program
					rank: pattern.runner.context.rank
					shot: shot
					pipeline: pattern.pipeline
					pipeline_index: pattern.pipeline_index
				}
			}
			if !pattern.runner.alive {
				if pattern.runner.vanished {
					pattern.active = false
					bullet.alive = false
				} else if pattern.morph_seed {
					pattern.active = false
					bullet.alive = false
				} else if !pattern.runner.has_pending_transitions() {
					pattern.active = false
				}
			}
		}
		if bullet.alive {
			simulation.apply_steps(mut bullet)
		}
		if bullet.alive && bullet.speed_ticks > 0 {
			bullet.speed += bullet.speed_delta
			bullet.speed_ticks--
		}
		if bullet.alive && bullet.direction_ticks > 0 {
			bullet.direction += bullet.direction_delta
			bullet.direction_ticks--
		}
		if !bullet.alive {
			pattern.active = false
		}
		simulation.bullets[index] = bullet
		simulation.bullet_patterns[index] = pattern
	}
	simulation.dispatch_bullet_motion()
	for index, mut bullet in simulation.bullets {
		if !bullet.alive {
			continue
		}
		if bullet.disappear_ticks <= 0 {
			if simulation.config.collisions && !simulation.god_mode
				&& simulation.ship.lifecycle_counter > 0
				&& simulation.bullet_hits_ship(bullet) {
				bullet.alive = false
				simulation.destroy_ship()
			} else if bullet.position.y < -2
				|| (!bullet.long_range && bullet.position.y > simulation.ship.sight_depth)
				|| !simulation.position_in_screen(bullet.position) {
				bullet.start_disappearing()
			}
		}
		if bullet.disappear_ticks > 0 {
			bullet.disappear_ticks++
			if bullet.disappear_ticks > bullet_disappear_duration_ticks {
				bullet.alive = false
				bullet.disappear_ticks = 0
			}
		} else if bullet.age > bullet_max_age_ticks {
			bullet.start_disappearing()
		}
		if !bullet.alive {
			mut pattern := simulation.bullet_patterns[index]
			pattern.active = false
			simulation.bullet_patterns[index] = pattern
		}
	}
	for child in pending {
		simulation.spawn_pipeline_shot(child.position, child.pipeline, child.pipeline_index, child.program, child.rank, child.shot)
	}
}

fn (simulation &Simulation) bullet_hits_ship(bullet Bullet) bool {
	movement_x := angle_delta(bullet.position.x, bullet.previous_position.x)
	movement_y := bullet.previous_position.y - bullet.position.y
	movement_length_squared := movement_x * movement_x + movement_y * movement_y
	if movement_length_squared <= 0.00001 {
		return false
	}
	ship_offset_x := angle_delta(bullet.position.x, simulation.ship.angle)
	ship_offset_y := simulation.ship.relative_depth - bullet.position.y
	projection := movement_x * ship_offset_x + movement_y * ship_offset_y
	if projection < 0 || projection > movement_length_squared {
		return false
	}
	distance_squared := ship_offset_x * ship_offset_x + ship_offset_y * ship_offset_y - projection * projection / movement_length_squared
	return distance_squared >= 0 && distance_squared <= 0.00025
}

fn (mut simulation Simulation) update_clock() {
	if simulation.config.run_time_ms <= 0 {
		return
	}
	for !simulation.game_over && simulation.score > simulation.next_extend_score {
		simulation.change_time(score_extend_seconds)
		simulation.next_extend_score += extend_score_for_level(simulation.level)
		simulation.time_extensions++
	}
	simulation.remaining_time_ms -= run_clock_tick_ms
	if simulation.time_change_ticks >= 0 {
		simulation.time_change_ticks--
	}
	if simulation.remaining_time_ms < 0 {
		simulation.remaining_time_ms = 0
		// God mode covers the run timer as well as collisions. Keep the clock at
		// zero so disabling it restores the ordinary game-over condition on the
		// next tick without inventing extra time.
		simulation.game_over = !simulation.god_mode
	} else if simulation.remaining_time_ms <= simulation.next_beep_time_ms {
		simulation.warning_beeps++
		simulation.next_beep_time_ms -= 1000
	}
}

fn (mut simulation Simulation) update_music_transition() {
	if simulation.music_change_ticks <= 0 {
		return
	}
	simulation.music_change_ticks--
	if simulation.music_change_ticks <= 0 {
		simulation.music_changes++
		simulation.music_change_ticks = -1
	}
}

fn (mut simulation Simulation) change_time(seconds int) {
	simulation.remaining_time_ms += seconds * 1000
	if simulation.remaining_time_ms > simulation.config.run_time_ms {
		simulation.remaining_time_ms = simulation.config.run_time_ms
	}
	simulation.next_beep_time_ms = (simulation.remaining_time_ms / 1000) * 1000
	if simulation.next_beep_time_ms > clock_warning_start_ms {
		simulation.next_beep_time_ms = clock_warning_start_ms
	}
	simulation.time_change_seconds = seconds
	simulation.time_change_ticks = time_change_display_ticks
}

fn steer_enemy_bank(bank f32, angle f32, target f32, bank_max f32) f32 {
	desired := clamp_f32(angle_delta(angle, target), -bank_max, bank_max)
	return bank + (desired - bank) * 0.1
}

fn (simulation &Simulation) enemy_movement_range(depth f32, visual_range f32) (bool, f32, f32) {
	current := simulation.course.slice_at(simulation.ship.course_position + depth)
	visible := simulation.course.slice_at(simulation.ship.course_position + depth + visual_range)
	if !current.full {
		mut left := current.left
		mut right := current.right
		if !visible.full {
			if course_side(left, visible) == -1 {
				left = visible.left
			}
			if course_side(right, visible) == 1 {
				right = visible.right
			}
		}
		return true, left, right
	}
	if !visible.full {
		return true, visible.left, visible.right
	}
	return false, 0, 0
}

fn (simulation &Simulation) position_in_screen(position Vec2) bool {
	ship_slice := simulation.course.slice_at(simulation.ship.course_position)
	horizontal_distance := wrapped_distance(position.x, simulation.ship.eye_angle) * ship_slice.rad / 21
	return horizontal_distance <= 0.03 * (position.y + 28)
}

fn (simulation &Simulation) generated_enemy_in_screen(enemy Enemy) bool {
	return simulation.position_in_screen(enemy.position)
}

fn (simulation &Simulation) generated_enemy_can_fire(enemy Enemy, spec EnemySpec) bool {
	angular_distance := f32(math.abs(enemy.position.x - simulation.ship.angle))
	depth_distance := f32(math.abs(enemy.position.y - simulation.ship.relative_depth))
	distance := if angular_distance > depth_distance {
		angular_distance + depth_distance / 2
	} else {
		depth_distance + angular_distance / 2
	}
	return simulation.generated_enemy_in_screen(enemy)
		&& distance > 20 + simulation.ship.relative_depth
		&& enemy.position.y > simulation.ship.relative_depth
		&& enemy.flip_ticks <= 0
		&& (spec.no_fire_depth_limit || enemy.position.y <= simulation.ship.sight_depth)
}

fn (simulation &Simulation) enemy_touches_ship(enemy Enemy, spec EnemySpec) bool {
	ship_slice := simulation.course.slice_at(simulation.ship.course_position)
	angular_distance := wrapped_distance(enemy.position.x, simulation.ship.angle) * ship_slice.rad / 21 * 3
	depth_distance := f32(math.abs(enemy.position.y - simulation.ship.relative_depth))
	enemy_collision := if spec.collision_size.x > 0 && spec.collision_size.y > 0 {
		spec.collision_size
	} else {
		ship_shape_collision(enemy.kind, spec.shape_seed)
	}
	return angular_distance <= enemy_collision.x + simulation.ship_collision.x
		&& depth_distance <= (enemy_collision.y + simulation.ship_collision.y) * simulation.ship.speed
}

fn (simulation &Simulation) shot_touches_enemy(shot Shot, enemy Enemy) bool {
	spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
	enemy_collision := if spec.collision_size.x > 0 && spec.collision_size.y > 0 {
		spec.collision_size
	} else {
		ship_shape_collision(enemy.kind, spec.shape_seed)
	}
	slice := simulation.course.slice_at(simulation.ship.course_position + enemy.position.y)
	angular_distance := wrapped_distance(enemy.position.x, shot.position.x) * slice.rad / 21 * 3
	depth_distance := f32(math.abs(enemy.position.y - shot.position.y))
	return angular_distance <= enemy_collision.x + 0.15 * shot.size
		&& depth_distance <= enemy_collision.y + 0.3 * shot.size
}

fn (simulation &Simulation) shot_touches_bullet(shot Shot, bullet Bullet) bool {
	slice := simulation.course.slice_at(simulation.ship.course_position + bullet.position.y)
	angular_distance := wrapped_distance(bullet.position.x, shot.position.x) * slice.rad / 21 * 3
	depth_distance := f32(math.abs(bullet.position.y - shot.position.y))
	return angular_distance <= 0.15 * shot.size && depth_distance <= 0.3 * shot.size
}

fn (simulation &Simulation) prepare_generated_enemy_motion(mut enemy Enemy, passed bool) (f32, f32) {
	spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
	if simulation.zone_transition_ticks >= 0 || simulation.stage.zone_complete_pending {
		enemy.speed += (0 - enemy.speed) * 0.05
		enemy.flip_ticks = 0
		enemy.flip_velocity = Vec2{}
	} else if simulation.ship.lifecycle_counter < -ship_spawn_invulnerability_ticks {
		enemy.speed += (1.5 - enemy.speed) * 0.15
	}
	aim_speed := if spec.has_limit_depth || (enemy.position.y > 5 && enemy.position.y < 70) {
		f32_max(spec.base_speed, simulation.ship.speed * spec.ship_speed_ratio)
	} else {
		spec.base_speed
	}
	enemy.speed += (aim_speed - enemy.speed) * 0.2
	mut depth_step := enemy.speed - simulation.ship.speed
	if passed && depth_step > 0 {
		depth_step = 0
	}
	mut next_depth := enemy.position.y + depth_step
	if !passed && spec.has_limit_depth {
		if next_depth > enemy.limit_depth {
			next_depth += (enemy.limit_depth - next_depth) * 0.05
		} else {
			enemy.limit_depth += (next_depth - enemy.limit_depth) * 0.05
		}
		enemy.limit_depth -= 0.01
		depth_step = next_depth - enemy.position.y
	}
	mut steer := false
	if simulation.config.procedural_course {
		has_range, left, right := simulation.enemy_movement_range(next_depth, spec.visual_range)
		if has_range {
			side := course_side(enemy.position.x, CourseSlice{
				left: left
				right: right
				rad: 21
			})
			if side != 0 {
				steer = true
				target := if side == -1 { left } else { right }
				enemy.turn_speed = steer_enemy_bank(enemy.turn_speed, enemy.position.x, target, spec.bank_max)
			}
		}
	}
	if !steer && spec.aim_ship
		&& wrapped_distance(enemy.position.x, simulation.ship.angle) > f32(math.pi) / 3 {
		enemy.turn_speed = steer_enemy_bank(enemy.turn_speed, enemy.position.x, simulation.ship.angle, spec.bank_max)
		steer = true
	}
	if !steer {
		enemy.turn_speed += (enemy.base_turn - enemy.turn_speed) * 0.2
	}
	enemy.turn_speed *= 0.9
	slice := simulation.course.slice_at(simulation.ship.course_position + next_depth)
	return enemy.turn_speed * 0.08 * (21 / slice.rad), depth_step
}

fn (simulation &Simulation) correct_enemy_course(mut enemy Enemy) {
	if !simulation.config.procedural_course {
		return
	}
	slice := simulation.course.slice_at(simulation.ship.course_position + enemy.position.y)
	side := course_side(enemy.position.x, slice)
	if side == 0 {
		return
	}
	mut correction := (-f32(side) - enemy.turn_speed) * 0.075
	correction = clamp_f32(correction, -1, 1)
	enemy.speed *= 1 - f32(math.abs(correction))
	enemy.turn_speed += correction
	enemy.position.x = if wrapped_distance(enemy.position.x, slice.left) < wrapped_distance(enemy.position.x, slice.right) {
		slice.left
	} else {
		slice.right
	}
}

fn (mut simulation Simulation) update_enemies() {
	mut firing_enemies := []EnemyFire{}
	mut newly_passed := []Enemy{}
	if simulation.config.stage_progression {
		simulation.update_stage_spawning()
	}
	spawn_floor := int_min(45, simulation.config.enemy_interval)
	spawn_interval := int_max(spawn_floor, simulation.config.enemy_interval - (simulation.zone - 1) * 5)
	fire_floor := int_min(30, simulation.config.enemy_fire_interval)
	fire_interval := int_max(fire_floor, simulation.config.enemy_fire_interval - (simulation.zone - 1) * 4)
	if !simulation.config.stage_progression && simulation.config.enemy_interval > 0
		&& simulation.tick % spawn_interval == 0 {
		for mut enemy in simulation.enemies {
			if enemy.alive {
				continue
			}
			kind := if simulation.spawned_enemies % 20 == 19 {
				2
			} else if simulation.spawned_enemies % 5 == 4 {
				1
			} else {
				0
			}
			spawn_angle := simulation.next_random_f32() * f32(math.pi * 2)
			turn_scale := if kind == 2 {
				f32(0)
			} else if kind == 1 {
				f32(0.005)
			} else {
				f32(0.003)
			}
			base_turn := (simulation.next_random_f32() * 2 - 1) * turn_scale
			enemy = Enemy{
				alive: true
				position: Vec2{
					x: spawn_angle
					y: 28
				}
				health: if kind == 2 {
					30
				} else if kind == 1 {
					10
				} else {
					1
				}
				kind: kind
				score: if kind == 2 {
					2000
				} else if kind == 1 {
					500
				} else {
					100
				}
				pattern: simulation.spawned_enemies % 3
				base_turn: base_turn
			}
			simulation.spawned_enemies++
			break
		}
	}
	mut moving_enemies := new_enemy_motion_slots(simulation.enemies.len)
	for index, mut enemy in simulation.enemies {
		if !enemy.alive {
			continue
		}
		if simulation.config.stage_progression && !enemy.rank_counted
			&& enemy.position.y <= simulation.ship.relative_depth {
			enemy.rank_counted = true
			simulation.record_enemy_rank_up(enemy.kind == 2)
		} else if simulation.config.stage_progression && enemy.rank_counted
			&& enemy.position.y > simulation.ship.relative_depth {
			enemy.rank_counted = false
			simulation.stage.rank_down()
		}
		enemy.previous_position = enemy.position
		mut motion_enemy := enemy
		mut depth_step := f32(0)
		if simulation.config.stage_progression {
			angle_step, generated_depth_step := simulation.prepare_generated_enemy_motion(mut enemy, false)
			depth_step = generated_depth_step
			motion_enemy.turn_speed = angle_step
		} else {
			depth_step = -(0.035 + simulation.ship.speed * 0.02)
			mut desired_turn := enemy.base_turn
			if enemy.kind == 1 {
				desired_turn += f32(math.sin(f32(enemy.age + 1) * 0.035 + f32(enemy.pattern))) * 0.004
			} else if enemy.kind == 2 {
				desired_turn = clamp_f32(angle_delta(enemy.position.x, simulation.ship.angle) * 0.025, -0.01, 0.01)
			}
			enemy.turn_speed += (desired_turn - enemy.turn_speed) * if enemy.kind == 2 {
				f32(0.08)
			} else {
				f32(0.15)
			}
			motion_enemy.turn_speed = enemy.turn_speed
		}
		moving_enemies.set(index, motion_enemy, depth_step)
	}
	simulation.dispatch_enemy_motion(moving_enemies)
	for mut enemy in simulation.enemies {
		if !enemy.alive {
			continue
		}
		if enemy.flip_ticks > 0 {
			enemy.flip_ticks--
			enemy.position.x += enemy.flip_velocity.x
			enemy.position.y += enemy.flip_velocity.y
			enemy.flip_velocity.x *= 0.95
			enemy.flip_velocity.y *= 0.95
		}
		enemy.position.x = wrap_angle(enemy.position.x)
		generated_spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
		if simulation.config.collisions && enemy.flip_ticks <= 0
			&& simulation.zone_transition_ticks < 0 && simulation.ship.lifecycle_counter >= -ship_spawn_invulnerability_ticks
			&& simulation.enemy_touches_ship(enemy, generated_spec) {
			direction := f32(math.atan2(angle_delta(simulation.ship.angle, enemy.previous_position.x), enemy.previous_position.y))
			enemy.flip_ticks = 48
			enemy.flip_velocity = Vec2{
				x: f32(math.sin(direction)) * simulation.ship.speed * 0.4
				y: f32(math.cos(direction)) * simulation.ship.speed * 7
			}
		}
		simulation.correct_enemy_course(mut enemy)
		can_fire := if simulation.config.stage_progression {
			simulation.generated_enemy_can_fire(enemy, generated_spec)
		} else {
			enemy.position.y <= simulation.ship.sight_depth
				&& enemy.position.y > simulation.ship.relative_depth
		}
		if simulation.config.stage_progression && simulation.config.enemy_fire_interval > 0 {
			simulation.update_generated_enemy_patterns(mut enemy, generated_spec, can_fire)
		} else if simulation.config.enemy_fire_interval > 0 && can_fire
			&& enemy.age >= fire_interval && enemy.age % fire_interval == 0 {
			firing_enemies << EnemyFire{
				position: enemy.position
				kind: enemy.kind
				spec_index: enemy.spec_index
				age: enemy.age
			}
		}
		if enemy.position.y <= simulation.ship.sight_depth {
			simulation.spawn_enemy_jet_particles(enemy.position, generated_spec)
		}
		disappearance_depth := if simulation.config.stage_progression { f32(-5) } else { f32(-2) }
		if enemy.position.y < disappearance_depth {
			if simulation.config.replay_mode && simulation.config.stage_progression {
				newly_passed << enemy
			}
			enemy.alive = false
		} else if simulation.config.stage_progression && !generated_spec.has_limit_depth
			&& enemy.position.y > 175 {
			enemy.alive = false
		}
		enemy.damaged = false
	}
	for firing in firing_enemies {
		simulation.fire_enemy_pattern(firing)
	}
	for enemy in newly_passed {
		simulation.spawn_passed_enemy(enemy)
	}
	simulation.update_passed_enemies()
}

fn (mut simulation Simulation) spawn_passed_enemy(source Enemy) bool {
	spec := simulation.enemy_spec_for(source.kind, source.spec_index)
	index := simulation.next_passed_enemy_index()
	if index < 0 {
		return false
	}
	simulation.passed_enemies[index] = Enemy{
		alive: true
		position: source.position
		previous_position: source.position
		health: spec.shield
		kind: source.kind
		score: source.score
		pattern: source.pattern
		base_turn: source.base_turn
		spec_index: source.spec_index
		limit_depth: source.position.y
	}
	return true
}

fn (mut simulation Simulation) next_passed_enemy_index() int {
	for _ in 0 .. simulation.passed_enemies.len {
		simulation.passed_enemy_cursor--
		if simulation.passed_enemy_cursor < 0 {
			simulation.passed_enemy_cursor = simulation.passed_enemies.len - 1
		}
		if !simulation.passed_enemies[simulation.passed_enemy_cursor].alive {
			return simulation.passed_enemy_cursor
		}
	}
	return -1
}

fn (mut simulation Simulation) update_passed_enemies() {
	if !simulation.config.replay_mode {
		return
	}
	for mut enemy in simulation.passed_enemies {
		if !enemy.alive {
			continue
		}
		angle_step, depth_step := simulation.prepare_generated_enemy_motion(mut enemy, true)
		enemy.position.x = wrap_angle(enemy.position.x + angle_step)
		enemy.position.y += depth_step
		enemy.age++
		simulation.correct_enemy_course(mut enemy)
		if enemy.position.y < -105 {
			enemy.alive = false
		}
	}
}

fn (simulation &Simulation) enemy_spec_for(kind int, index int) EnemySpec {
	if kind == 0 && index >= 0 && index < simulation.zone_specs.small.len {
		return simulation.zone_specs.small[index]
	}
	if kind == 1 && index >= 0 && index < simulation.zone_specs.middle.len {
		return simulation.zone_specs.middle[index]
	}
	if kind == 2 && index >= 0 && index < simulation.zone_specs.boss.len {
		return simulation.zone_specs.boss[index]
	}
	fallback_kind := int_max(0, int_min(2, kind))
	return EnemySpec{
		kind: kind
		shield: if kind == 2 {
			30
		} else if kind == 1 {
			10
		} else {
			1
		}
		score: if kind == 2 {
			2000
		} else if kind == 1 {
			500
		} else {
			100
		}
		base_speed: 0.1
		ship_speed_ratio: 0.5
		collision_size: simulation.default_enemy_collisions[fallback_kind]
		barrage: GeneratedBarrageSpec{
			base_pattern: if kind == 0 {
				'basic/straight'
			} else {
				'middle/nway'
			}
		}
	}
}

// boss_bits exposes the live derived bit poses without making them independent
// simulation actors. A renderer or future compute backend can consume this flat view.
pub fn (simulation &Simulation) boss_bits() []BossBitPose {
	mut poses := []BossBitPose{}
	for enemy in simulation.enemies {
		if !enemy.alive || enemy.kind != 2 {
			continue
		}
		spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
		for index in 0 .. spec.bit_count {
			poses << boss_bit_pose(spec, enemy.position, index, int_max(enemy.age - 1, 0))
		}
	}
	return poses
}

fn (mut simulation Simulation) update_stage_spawning() {
	if simulation.zone_transition_ticks >= 0 {
		simulation.clear_live_bullets()
		simulation.zone_transition_ticks--
		if simulation.zone_transition_ticks < 0 {
			simulation.install_next_zone()
		} else {
			return
		}
	}
	if simulation.palette_transition_ticks > 0 {
		simulation.palette_transition_ticks--
	}
	if simulation.stage.in_boss_mode {
		if simulation.next_boss_distance > boss_distance_unscheduled_threshold {
			simulation.next_boss_distance = f32(simulation.stage_random.next_int(first_boss_distance_variation) + first_boss_min_distance)
		}
		simulation.next_boss_distance -= simulation.ship.speed
		if simulation.stage.bosses_remaining > simulation.count_living_bosses()
			&& simulation.next_boss_distance <= 0 {
			_ = simulation.spawn_stage_enemy(2)
			// StageManager advances its boss counter even when the shared actor
			// pool is full and addEnemy cannot install the scheduled boss.
			simulation.next_boss_spec++
			simulation.next_boss_distance = f32(simulation.stage_random.next_int(following_boss_distance_variation) + following_boss_min_distance)
		}
		if simulation.next_boss_spec >= simulation.zone_specs.boss.len
			&& simulation.count_living_bosses() == 0 && simulation.stage.in_boss_mode {
			simulation.stage.force_zone_complete()
			simulation.zone_transition_ticks = zone_transition_duration_ticks
		}
		return
	}
	simulation.next_small_distance -= simulation.ship.speed
	simulation.next_middle_distance -= simulation.ship.speed
	if simulation.next_small_distance <= 0 {
		simulation.spawn_stage_enemy(0)
		simulation.next_small_distance += simulation.next_small_spawn_distance()
	}
	if simulation.next_middle_distance <= 0 {
		simulation.spawn_stage_enemy(1)
		simulation.next_middle_distance += simulation.next_middle_spawn_distance()
	}
}

fn (mut simulation Simulation) next_small_spawn_distance() f32 {
	return f32(simulation.stage_random.next_int(16) + 6)
}

fn (mut simulation Simulation) next_middle_spawn_distance() f32 {
	return f32(simulation.stage_random.next_int(200) + 33)
}

fn (mut simulation Simulation) spawn_stage_enemy(kind int) bool {
	mut spec_index := 0
	mut spec := EnemySpec{}
	if kind == 0 && simulation.zone_specs.small.len > 0 {
		spec_index = simulation.stage_random.next_int(simulation.zone_specs.small.len)
		spec = simulation.zone_specs.small[spec_index]
	} else if kind == 1 && simulation.zone_specs.middle.len > 0 {
		spec_index = simulation.stage_random.next_int(simulation.zone_specs.middle.len)
		spec = simulation.zone_specs.middle[spec_index]
	} else if kind == 2 && simulation.zone_specs.boss.len > 0 {
		spec_index = int_min(simulation.next_boss_spec, simulation.zone_specs.boss.len - 1)
		spec = simulation.zone_specs.boss[spec_index]
	} else {
		return false
	}
	// The source evaluates the small/middle spawn-depth argument before asking
	// the pool for a slot, so this draw is still consumed when the pool is full.
	spawn_depth := if kind == 2 {
		f32(140)
	} else {
		140 + simulation.stage_random.next_f32(17.5)
	}
	index := simulation.next_stage_enemy_index()
	if index < 0 {
		return false
	}
	spawn_slice := simulation.course.slice_at(simulation.ship.course_position + spawn_depth)
	mut spawn_angle := f32(0)
	if spawn_slice.full {
		spawn_angle = simulation.stage_random.next_f32(f32(math.pi))
	} else {
		mut width := spawn_slice.right - spawn_slice.left
		if width < 0 {
			width += f32(math.pi * 2)
		}
		spawn_angle = wrap_angle(spawn_slice.left + simulation.stage_random.next_f32(width))
	}
	simulation.enemies[index] = Enemy{
		alive: true
		position: Vec2{ x: spawn_angle, y: spawn_depth }
		health: spec.shield
		kind: kind
		score: spec.score
		pattern: spec_index
		spec_index: spec_index
		base_turn: simulation.stage_random.next_signed_f32(spec.base_bank)
		limit_depth: spawn_depth
	}
	simulation.spawned_enemies++
	return true
}

fn (mut simulation Simulation) next_stage_enemy_index() int {
	for _ in 0 .. simulation.enemies.len {
		simulation.enemy_cursor--
		if simulation.enemy_cursor < 0 {
			simulation.enemy_cursor = simulation.enemies.len - 1
		}
		if !simulation.enemies[simulation.enemy_cursor].alive {
			return simulation.enemy_cursor
		}
	}
	return -1
}

fn (simulation &Simulation) count_living_bosses() int {
	mut count := 0
	for enemy in simulation.enemies {
		if enemy.alive && enemy.kind == 2 {
			count++
		}
	}
	return count
}

fn (mut simulation Simulation) record_enemy_rank_up(is_boss bool) {
	if simulation.game_over {
		return
	}
	if simulation.stage.rank_up(is_boss) {
		if simulation.config.run_time_ms > 0 {
			bonus := if simulation.zone % 2 == 1 {
				odd_zone_bonus_seconds
			} else {
				even_zone_bonus_seconds
			}
			simulation.change_time(bonus)
		}
		if simulation.zone % 2 == 0 {
			simulation.music_change_ticks = music_transition_delay_ticks
			simulation.music_fades++
		}
		simulation.zone_transition_ticks = zone_transition_duration_ticks
	}
}

fn (mut simulation Simulation) clear_live_bullets() {
	for mut bullet in simulation.bullets {
		if bullet.alive && bullet.disappear_ticks <= 0 {
			bullet.start_disappearing()
		}
	}
}

fn (mut simulation Simulation) remove_live_bullets() {
	for index in 0 .. simulation.bullets.len {
		simulation.bullets[index].alive = false
		simulation.bullets[index].disappear_ticks = 0
		simulation.bullet_patterns[index].active = false
	}
}

fn (mut bullet Bullet) start_disappearing() {
	if !bullet.alive || bullet.disappear_ticks > 0 {
		return
	}
	bullet.disappear_ticks = 1
}

fn (mut simulation Simulation) clear_live_enemies() {
	for mut enemy in simulation.enemies {
		enemy.alive = false
	}
	simulation.enemy_cursor = 0
}

fn (mut simulation Simulation) install_next_zone() {
	simulation.zone++
	simulation.zone_advances++
	simulation.level += 0.5
	simulation.clear_live_enemies()
	setup := generate_zone_enemy_setup(simulation.level, simulation.config.grade, simulation.zone % 2 == 1, 0, mut simulation.stage_random)
	simulation.zone_specs = setup.specs
	simulation.stage.start_next_zone(simulation.zone_specs.boss.len)
	simulation.shape_random = shape_random_after_zone(simulation.zone_specs, u32(simulation.config.random_seed))
	simulation.next_boss_spec = 0
	simulation.palette_transition_ticks = palette_transition_duration_ticks
	simulation.next_small_distance = setup.next_small_distance
	simulation.next_middle_distance = setup.next_middle_distance
	simulation.next_boss_distance = boss_distance_unscheduled
}

fn (mut simulation Simulation) fire_enemy_pattern(firing EnemyFire) {
	spec := simulation.enemy_spec_for(firing.kind, firing.spec_index)
	if simulation.config.stage_progression {
		simulation.fire_generated_barrage(firing.position, f32(math.pi), spec.barrage)
		if firing.kind == 2 && spec.bit_count > 0 {
			for bit in 0 .. spec.bit_count {
				pose := boss_bit_pose(spec, firing.position, bit, firing.age)
				simulation.fire_generated_barrage(pose.position, pose.direction, spec.bit_barrage)
			}
		}
		return
	}
	program := if firing.kind == 0 {
		straight_pattern()
	} else {
		nway_pattern()
	}
	rank := if firing.kind == 2 { f32(0.2) } else { f32(0) }
	bullet_speed := simulation.config.enemy_bullet_speed + f32(simulation.zone - 1) * 0.003
	simulation.emit_pattern(firing.position, f32(math.pi), program, rank, bullet_speed)
}

fn (mut simulation Simulation) fire_generated_barrage(position Vec2, direction f32, barrage GeneratedBarrageSpec) {
	pipeline := simulation.generated_pattern_pipeline(barrage)
	simulation.emit_pattern_pipeline(position, direction, pipeline, 0)
}

fn (mut simulation Simulation) generated_pattern_pipeline(barrage GeneratedBarrageSpec) PatternPipeline {
	program := native_pattern_named(barrage.base_pattern) or { straight_pattern() }
	mut programs := [program]
	mut ranks := [barrage.rank]
	for name in barrage.morphs {
		morph := native_pattern_named(name) or { continue }
		programs << morph
		ranks << barrage.morph_rank
	}
	x_reverse := if barrage.no_x_reverse {
		f32(1)
	} else if simulation.barrage_random.next_int(2) == 0 {
		f32(-1)
	} else {
		f32(1)
	}
	return PatternPipeline{
		programs: programs
		ranks: ranks
		x_reverse: x_reverse
		visual_shape: barrage.bullet_shape
		visual_scale: barrage.visual_scale
		long_range: barrage.long_range
		speed_rank: barrage.speed_rank
		// BulletML converts its speed unit to the source simulation with 10 / 62.
		default_speed: f32(10.0 / 62.0)
		speed_scale: f32(10.0 / 62.0)
	}
}

fn (mut simulation Simulation) new_enemy_pattern_root(position Vec2, owner_direction f32,
	barrage GeneratedBarrageSpec) EnemyPatternRoot {
	pipeline := simulation.generated_pattern_pipeline(barrage)
	if pipeline.programs.len == 0 || pipeline.ranks.len == 0 {
		return EnemyPatternRoot{}
	}
	aim := aim_direction_reversed(position, Vec2{
		x: simulation.ship.angle
		y: simulation.ship.relative_depth
	}, pipeline.x_reverse)
	context := PatternContext{
		rank: pipeline.ranks[0]
		aim_direction: aim
		base_direction: owner_direction
		base_speed: 0
		default_speed: pipeline.default_speed
		speed_scale: pipeline.speed_scale
	}
	runner := new_parallel_pattern_runner(pipeline.programs[0], context, 0, barrage.interval) or {
		return EnemyPatternRoot{}
	}
	return EnemyPatternRoot{
		active: true
		runner: runner
		pipeline: pipeline
	}
}

fn (mut simulation Simulation) advance_enemy_pattern_root(mut root EnemyPatternRoot,
	position Vec2, owner_direction f32, emit bool) {
	if !root.active || root.pipeline.programs.len == 0 || root.pipeline.ranks.len == 0 {
		return
	}
	aim := aim_direction_reversed(position, Vec2{
		x: simulation.ship.angle
		y: simulation.ship.relative_depth
	}, root.pipeline.x_reverse)
	for mut looping in root.runner.runners {
		// An invisible top bullet is repositioned and re-aimed by its owner before
		// every BulletML tick. A freshly rewound parser also starts its sequence
		// directions from that current heading.
		if looping.wait_ticks == 0 && looping.runner.instruction == looping.entry_instruction {
			looping.runner.last_fire_direction = owner_direction
			looping.runner.last_direction_target = owner_direction
		}
		looping.runner.direction = owner_direction
		looping.runner.aim_direction = aim
	}
	shots := root.runner.tick(mut simulation.random) or { return }
	if !emit {
		return
	}
	for shot in shots {
		if simulation.spawn_pipeline_shot(position, root.pipeline, 0, root.pipeline.programs[0], root.pipeline.ranks[0], shot) {
			simulation.enemy_shots_fired++
		}
	}
}

fn (mut simulation Simulation) update_generated_enemy_patterns(mut enemy Enemy, spec EnemySpec,
	can_fire bool) {
	if !enemy.barrage_root.active {
		body_aim := aim_direction_reversed(enemy.position, Vec2{
			x: simulation.ship.angle
			y: simulation.ship.relative_depth
		}, 1)
		enemy.barrage_root = simulation.new_enemy_pattern_root(enemy.position, body_aim, spec.barrage)
		enemy.bit_barrage_roots = []EnemyPatternRoot{cap: spec.bit_count}
		for bit in 0 .. spec.bit_count {
			pose := boss_bit_pose(spec, enemy.position, bit, int_max(enemy.age - 1, 0))
			enemy.bit_barrage_roots << simulation.new_enemy_pattern_root(pose.position, pose.direction, spec.bit_barrage)
		}
	}
	body_aim := aim_direction_reversed(enemy.position, Vec2{
		x: simulation.ship.angle
		y: simulation.ship.relative_depth
	}, enemy.barrage_root.pipeline.x_reverse)
	simulation.advance_enemy_pattern_root(mut enemy.barrage_root, enemy.position, body_aim, can_fire)
	for bit in 0 .. int_min(spec.bit_count, enemy.bit_barrage_roots.len) {
		pose := boss_bit_pose(spec, enemy.position, bit, int_max(enemy.age - 1, 0))
		// The range check writes the body root rank even when it
		// is called for a bit root, leaving boss-bit roots active at long range.
		simulation.advance_enemy_pattern_root(mut enemy.bit_barrage_roots[bit], pose.position, pose.direction, true)
	}
}

fn (mut simulation Simulation) emit_pattern(position Vec2, direction f32, program PatternProgram, rank f32, bullet_speed f32) {
	simulation.emit_pattern_pipeline(position, direction, PatternPipeline{
		programs: [program]
		ranks: [rank]
	}, bullet_speed)
}

fn (mut simulation Simulation) emit_pattern_pipeline(position Vec2, direction f32, pipeline PatternPipeline, bullet_speed f32) {
	if pipeline.programs.len == 0 || pipeline.ranks.len != pipeline.programs.len {
		return
	}
	program := pipeline.programs[0]
	rank := pipeline.ranks[0]
	context := PatternContext{
		rank: rank
		aim_direction: aim_direction_reversed(position, Vec2{
			x: simulation.ship.angle
			y: simulation.ship.relative_depth
		}, pipeline.x_reverse)
		base_direction: direction
		base_speed: bullet_speed
		default_speed: pipeline.default_speed
		speed_scale: pipeline.speed_scale
	}
	mut shots := []PatternShot{}
	if program.entry_points.len > 1 {
		mut runner := new_parallel_pattern_runner(program, context, 0, 0) or { return }
		shots = runner.tick(mut simulation.random) or { return }
	} else {
		mut runner := new_pattern_runner(program, context)
		shots = runner.tick(mut simulation.random) or { return }
	}
	for shot in shots {
		if simulation.spawn_pipeline_shot(position, pipeline, 0, program, rank, shot) {
			simulation.enemy_shots_fired++
		}
	}
}

fn aim_direction_reversed(from Vec2, to Vec2, x_reverse f32) f32 {
	return f32(math.atan2(angle_delta(from.x, to.x) * x_reverse, to.y - from.y))
}

fn (mut simulation Simulation) next_random_f32() f32 {
	return simulation.stage_random.next_f32(1)
}

fn (mut simulation Simulation) update_weapon(input InputState) {
	rules := rules_for_grade(simulation.config.grade)
	if input.brake {
		if simulation.charging_shot < 0 {
			index := simulation.next_shot_index(true)
			if index >= 0 {
				simulation.shots[index] = Shot{
					alive: true
					position: Vec2{
						x: wrap_angle(simulation.ship.angle - simulation.ship.bank * shot_bank_angle_ratio)
						y: simulation.ship.relative_depth + shot_muzzle_depth_offset
					}
					charged: true
					charging: true
					damage:      charged_shot_damage
					size: 0
					target_size: 0
				}
				simulation.charging_shot = index
			}
		} else {
			simulation.shots[simulation.charging_shot].position.x = wrap_angle(simulation.ship.angle - simulation.ship.bank * shot_bank_angle_ratio)
			simulation.shots[simulation.charging_shot].position.y = simulation.ship.relative_depth + shot_muzzle_depth_offset
		}
	} else if simulation.charging_shot >= 0 {
		// Releasing before the minimum charge cancels the shot.
		if simulation.shots[simulation.charging_shot].charge_ticks < charged_shot_min_ticks {
			simulation.shots[simulation.charging_shot].alive = false
		} else {
			simulation.shots[simulation.charging_shot].charging = false
			simulation.shots[simulation.charging_shot].range = (charged_shot_base_range + f32(simulation.shots[simulation.charging_shot].charge_ticks) * charged_shot_range_per_tick) * simulation.config.player_shot_distance / source_player_shot_distance
			simulation.shots[simulation.charging_shot].target_size = charged_shot_base_size + f32(simulation.shots[simulation.charging_shot].charge_ticks) * charged_shot_size_per_tick
		}
		simulation.charging_shot = -1
	}
	if input.fire && !input.brake && simulation.fire_cooldown <= 0 {
		simulation.fire_cooldown = regular_shot_interval_ticks
		mut gun_offset := -gun_lateral_angle
		if simulation.fired_shots % 2 == 1 {
			gun_offset = gun_lateral_angle
		}
		index := simulation.next_shot_index(false)
		if index >= 0 {
			simulation.shots[index] = Shot{
				alive: true
				position: Vec2{
					x: wrap_angle(simulation.ship.angle + gun_offset)
					y: simulation.ship.relative_depth + shot_muzzle_depth_offset
				}
				range: simulation.config.player_shot_distance
				star_shell: simulation.fired_shots % star_shot_interval == 0
			}
			simulation.fired_shots++
		}
	}
	if input.fire && !input.brake && simulation.ship.speed > rules.default_speed * side_fire_speed_ratio
		&& simulation.side_fire_cooldown <= 0 {
		simulation.side_fire_cooldown = side_fire_idle_ticks
		speed_range := rules.max_speed - rules.default_speed
		side_angle := clamp_f32((simulation.ship.speed - rules.default_speed) / speed_range * side_fire_max_angle, side_fire_min_angle, side_fire_max_angle)
		mut direction := side_angle * f32(simulation.side_fired_shots % side_fire_angle_steps) * side_fire_angle_step_ratio
		if simulation.side_fired_shots % 2 == 1 {
			direction = -direction
		}
		index := simulation.next_shot_index(false)
		if index >= 0 {
			simulation.shots[index] = Shot{
				alive: true
				position: Vec2{
					x: wrap_angle(simulation.ship.angle + if simulation.fired_shots % 2 == 0 {
						-gun_lateral_angle
					} else {
						gun_lateral_angle
					})
					y: simulation.ship.relative_depth + shot_muzzle_depth_offset
				}
				direction: direction
				range: simulation.config.player_shot_distance
				star_shell: simulation.side_fired_shots % star_shot_interval == 0
			}
			simulation.side_fired_shots++
		}
	}
	mut side_interval := side_fire_idle_ticks
	if simulation.ship.speed > rules.default_speed * side_fire_speed_ratio {
		fire_density := (simulation.ship.speed - rules.default_speed * side_fire_speed_ratio) * side_fire_density_scale / (rules.max_speed - rules.default_speed) + 1.0
		side_interval = int(side_fire_interval_numerator / fire_density)
		if side_interval < 1 {
			side_interval = 1
		}
	}
	if simulation.side_fire_cooldown > side_interval {
		simulation.side_fire_cooldown = side_interval
	}
	if simulation.fire_cooldown > 0 {
		simulation.fire_cooldown--
	}
	if simulation.side_fire_cooldown > 0 {
		simulation.side_fire_cooldown--
	}
}

fn (mut simulation Simulation) next_shot_index(forced bool) int {
	if simulation.shots.len == 0 {
		return -1
	}
	limit := if forced { 1 } else { simulation.shots.len }
	for _ in 0 .. limit {
		simulation.shot_cursor--
		if simulation.shot_cursor < 0 {
			simulation.shot_cursor = simulation.shots.len - 1
		}
		if forced || !simulation.shots[simulation.shot_cursor].alive {
			return simulation.shot_cursor
		}
	}
	return -1
}

fn (mut simulation Simulation) update_shots() {
	mut impact_positions := []Vec2{}
	mut destruction_bursts := []DestructionBurst{}
	mut zones_completed := 0
	for mut shot in simulation.shots {
		if shot.alive && shot.charging {
			if shot.charge_ticks < charged_shot_max_ticks {
				shot.charge_ticks++
			}
			shot.target_size = (charged_shot_base_size + f32(shot.charge_ticks) * charged_shot_size_per_tick) * charging_shot_size_ratio
			shot.age++
		}
	}
	simulation.dispatch_shot_motion()
	for mut shot in simulation.shots {
		if !shot.alive {
			continue
		}
		if !shot.charging && shot.range > 0 && shot.range < 10 {
			shot.target_size *= 0.75
		}
		shot.size += (shot.target_size - shot.size) * 0.1
	}
	shot_enemy_candidates := if simulation.config.collisions {
		simulation.resolved_shot_enemy_candidates()
	} else {
		[]ShotCollisionCandidate{}
	}
	shot_bullet_candidates := if simulation.config.collisions {
		simulation.resolved_shot_bullet_candidates()
	} else {
		[]ShotCollisionCandidate{}
	}
	mut enemy_candidate_cursor := 0
	mut bullet_candidate_cursor := 0
	for shot_index, mut shot in simulation.shots {
		if !shot.alive {
			continue
		}
		if !shot.charging && simulation.config.collisions && shot.charged {
			for bullet_candidate_cursor < shot_bullet_candidates.len
				&& shot_bullet_candidates[bullet_candidate_cursor].shot_index < shot_index {
				bullet_candidate_cursor++
			}
			for bullet_candidate_cursor < shot_bullet_candidates.len
				&& shot_bullet_candidates[bullet_candidate_cursor].shot_index == shot_index {
				bullet_index := shot_bullet_candidates[bullet_candidate_cursor].target_index
				bullet_candidate_cursor++
				mut bullet := &simulation.bullets[bullet_index]
				if bullet.alive && bullet.disappear_ticks <= 0
					&& simulation.shot_touches_bullet(shot, *bullet) {
					position := bullet.position
					bullet.start_disappearing()
					simulation.bullets_cleared++
					simulation.score_shot_hit(mut shot, 10, position)
				}
			}
		}
		if !shot.charging && simulation.config.collisions {
			for enemy_candidate_cursor < shot_enemy_candidates.len
				&& shot_enemy_candidates[enemy_candidate_cursor].shot_index < shot_index {
				enemy_candidate_cursor++
			}
			for enemy_candidate_cursor < shot_enemy_candidates.len
				&& shot_enemy_candidates[enemy_candidate_cursor].shot_index == shot_index {
				enemy_index := shot_enemy_candidates[enemy_candidate_cursor].target_index
				enemy_candidate_cursor++
				mut enemy := &simulation.enemies[enemy_index]
				if !enemy.alive || !simulation.shot_touches_enemy(shot, *enemy) {
					continue
				}
				enemy.health -= shot.damage
				simulation.enemy_hits++
				if enemy.health <= 0 {
					enemy.alive = false
					if simulation.config.stage_progression && !enemy.rank_counted {
						enemy.rank_counted = true
						simulation.record_enemy_rank_up(enemy.kind == 2)
					}
					simulation.destroyed_enemies++
					if enemy.kind == 2 {
						simulation.destroyed_boss++
						simulation.ship.screen_shake_ticks = 56
						simulation.ship.screen_shake_intensity = 0.064
						if !simulation.config.stage_progression {
							zones_completed++
						}
					} else if enemy.kind == 1 {
						simulation.destroyed_middle++
					} else {
						simulation.destroyed_small++
					}
					destruction_bursts << DestructionBurst{
						position: enemy.position
						enemy_kind: enemy.kind
						collision_size: simulation.enemy_spec_for(enemy.kind, enemy.spec_index).collision_size
					}
				} else {
					enemy.damaged = true
					impact_positions << enemy.position
				}
				simulation.score_shot_hit(mut shot, enemy.score, enemy.position)
			}
		}
		if shot.star_shell || shot.charge_ticks >= charged_shot_min_ticks {
			particle_count := if shot.charged { 3 } else { 1 }
			for _ in 0 .. particle_count {
				simulation.spawn_shot_trail_particle(shot.position, shot.charge_ticks)
			}
		}
		// Actor removal does not abort the current move method:
		// the zero-range frame still collides and emits its trail first.
		if !shot.charging && shot.range <= 0 {
			shot.alive = false
		}
	}
	for position in impact_positions {
		simulation.spawn_enemy_hit_particles(position)
	}
	for burst in destruction_bursts {
		simulation.spawn_enemy_destruction_core(burst.position)
		simulation.spawn_enemy_fragments(burst.position, burst.enemy_kind, burst.collision_size)
	}
	for _ in 0 .. zones_completed {
		simulation.advance_zone()
	}
}

fn (mut simulation Simulation) score_shot_hit(mut shot Shot, points int, position Vec2) {
	if !simulation.game_over {
		simulation.score += points * shot.multiplier
	}
	if shot.multiplier > 1 {
		simulation.spawn_multiplier_popup(position, shot.multiplier, points)
	}
	if shot.charged {
		if shot.multiplier < 100 {
			shot.multiplier++
		}
	} else {
		shot.alive = false
	}
}

fn (mut simulation Simulation) spawn_shot_trail_particle(position Vec2, charge_ticks int) {
	index := simulation.next_particle_index(false)
	if index < 0 {
		return
	}
	direction := simulation.shot_random.next_signed_f32(f32(math.pi) / 2) + f32(math.pi)
	height_velocity := simulation.shot_random.next_signed_f32(0.5)
	base_life := charge_ticks * 32 / charged_shot_max_ticks + 4
	simulation.set_source_particle(index, position, direction, 1, height_velocity, 0.05, base_life, .spark, 1)
}

fn (mut simulation Simulation) spawn_enemy_jet_particles(position Vec2, spec EnemySpec) {
	for offset in ship_shape_rocket_offsets(spec.kind, spec.shape_seed) {
		index := simulation.next_particle_index(false)
		if index < 0 {
			break
		}
		jet_position := Vec2{
			x: wrap_angle(position.x + offset)
			y: position.y - 0.15
		}
		simulation.set_source_particle(index, jet_position, f32(math.pi), 1, 0, 0.2, 16, .jet, 1)
	}
}

fn (mut simulation Simulation) advance_zone() {
	completed_zone := simulation.zone
	simulation.zone++
	simulation.zone_advances++
	simulation.level += 0.5
	if simulation.config.run_time_ms > 0 {
		bonus := if completed_zone % 2 == 1 { 30 } else { 45 }
		simulation.change_time(bonus)
	}
}

pub fn extend_score_for_level(level f32) int {
	mut score := (int(level * 0.5) + 10) * 10000
	if score > 500000 {
		score = 500000
	}
	return score
}

fn int_max(a int, b int) int {
	return if a > b { a } else { b }
}

fn int_min(a int, b int) int {
	return if a < b { a } else { b }
}

fn clamp_f32(value f32, low f32, high f32) f32 {
	if value < low {
		return low
	}
	if value > high {
		return high
	}
	return value
}

fn f32_max(a f32, b f32) f32 {
	return if a > b { a } else { b }
}

fn (mut simulation Simulation) spawn_particles(position Vec2, count int, life int, kind ParticleKind) {
	simulation.spawn_particles_scaled(position, count, life, kind, 0)
}

fn (mut simulation Simulation) spawn_enemy_hit_particles(position Vec2) {
	for _ in 0 .. 4 {
		if !simulation.spawn_enemy_hit_particle(position, false) {
			continue
		}
		_ = simulation.spawn_enemy_hit_particle(position, true)
	}
}

fn (mut simulation Simulation) spawn_enemy_hit_particle(position Vec2, opposite bool) bool {
	in_course := simulation.particle_in_course(position)
	index := simulation.next_particle_index(false)
	if index < 0 {
		return false
	}
	direction := simulation.enemy_random.next_signed_f32(0.1) + if opposite {
		f32(math.pi)
	} else {
		f32(0)
	}
	height_velocity := simulation.enemy_random.next_signed_f32(1.6)
	_ = simulation.enemy_random.next_f32(0.4)
	speed_bias := simulation.particle_random.next_f32(0.8) + 0.4
	life := 16 + simulation.particle_random.next_int(8)
	luminosity := 0.8 + simulation.particle_random.next_f32(0.2)
	simulation.particles[index] = Particle{
		alive: true
		position: position
		velocity: Vec2{
			x: f32(math.sin(direction)) * 0.75 * speed_bias
			y: f32(math.cos(direction)) * 0.75 * speed_bias
		}
		life: life
		initial_life: life
		kind: .spark
		height: 1
		height_velocity: height_velocity
		in_course: in_course
		luminosity: luminosity
	}
	return true
}

fn (mut simulation Simulation) next_particle_index(forced bool) int {
	if simulation.particles.len == 0 {
		return -1
	}
	limit := if forced { 1 } else { simulation.particles.len }
	for _ in 0 .. limit {
		simulation.particle_cursor--
		if simulation.particle_cursor < 0 {
			simulation.particle_cursor = simulation.particles.len - 1
		}
		if forced || !simulation.particles[simulation.particle_cursor].alive {
			return simulation.particle_cursor
		}
	}
	return -1
}

fn (mut simulation Simulation) set_source_particle(index int, position Vec2, direction f32,
	height f32, height_velocity f32, speed f32, base_life int, kind ParticleKind,
	visual_tier int) {
	if index < 0 || index >= simulation.particles.len {
		return
	}
	speed_bias := simulation.particle_random.next_f32(0.8) + 0.4
	life := base_life + simulation.particle_random.next_int(base_life / 2)
	luminosity := 0.8 + simulation.particle_random.next_f32(0.2)
	mut spin_velocity := f32(0)
	mut secondary_spin_velocity := f32(0)
	if kind == .fragment {
		spin_velocity = simulation.particle_random.next_signed_f32(12) * f32(math.pi) / 180
		secondary_spin_velocity = simulation.particle_random.next_signed_f32(12) * f32(math.pi) / 180
	}
	simulation.particles[index] = Particle{
		alive: true
		position: position
		velocity: Vec2{
			x: f32(math.sin(direction)) * speed * speed_bias
			y: f32(math.cos(direction)) * speed * speed_bias
		}
		life: life
		initial_life: life
		kind: kind
		visual_tier: visual_tier
		height: height
		height_velocity: height_velocity
		in_course: simulation.particle_in_course(position)
		luminosity: luminosity
		spin_velocity: spin_velocity
		secondary_spin_velocity: secondary_spin_velocity
	}
}

fn (mut simulation Simulation) spawn_enemy_destruction_core(position Vec2) {
	for _ in 0 .. 30 {
		index := simulation.next_particle_index(false)
		if index < 0 {
			break
		}
		direction := simulation.enemy_random.next_f32(f32(math.pi * 2))
		height_velocity := simulation.enemy_random.next_signed_f32(1)
		speed := 0.01 + simulation.enemy_random.next_f32(0.1)
		_ = simulation.enemy_random.next_f32(0.8)
		simulation.set_source_particle(index, position, direction, 1, height_velocity, speed, 24, .spark, 0)
	}
}

fn (mut simulation Simulation) spawn_enemy_fragments(position Vec2, enemy_kind int,
	collision_size Vec2) {
	if collision_size.x < 0.5 {
		return
	}
	for _ in 0 .. int(collision_size.x * 40) {
		index := simulation.next_particle_index(false)
		if index < 0 {
			break
		}
		direction := simulation.shape_random.next_signed_f32(0.1)
		height_velocity := 1 + simulation.shape_random.next_signed_f32(1)
		speed := 0.2 + simulation.shape_random.next_f32(0.2)
		base_life := 32 + simulation.shape_random.next_int(16)
		fragment_width := collision_size.x + simulation.shape_random.next_f32(collision_size.x)
		fragment_height := collision_size.y + simulation.shape_random.next_f32(collision_size.y)
		simulation.set_source_particle(index, position, direction, 1, height_velocity, speed, base_life, .fragment, enemy_kind)
		simulation.particles[index].fragment_width = fragment_width
		simulation.particles[index].fragment_height = fragment_height
	}
}

fn (mut simulation Simulation) spawn_ship_destruction_particles(position Vec2) {
	for _ in 0 .. 256 {
		index := simulation.next_particle_index(true)
		if index < 0 {
			return
		}
		direction := simulation.ship_random.next_signed_f32(f32(math.pi) / 8)
		height_velocity := simulation.ship_random.next_signed_f32(2.5)
		speed := 0.5 + simulation.ship_random.next_f32(1)
		_ = simulation.ship_random.next_f32(0.8)
		simulation.set_source_particle(index, position, direction, 1, height_velocity, speed, 32, .spark, 0)
	}
}

fn (mut simulation Simulation) spawn_particles_scaled(position Vec2, count int, life int, kind ParticleKind, visual_tier int) {
	in_course := simulation.particle_in_course(position)
	for spawned in 0 .. count {
		index := simulation.next_particle_index(false)
		if index < 0 {
			break
		}
		// A golden-angle sequence produces an even deterministic burst without
		// consuming gameplay RNG or coupling effects to enemy spawning.
		angle := f32(spawned) * 2.3999631 + f32(simulation.tick) * 0.17
		speed := f32(0.018 + f32(spawned % 5) * 0.006)
		simulation.particles[index] = Particle{
			alive: true
			position: position
			velocity: Vec2{
				x: f32(math.sin(angle)) * speed
				y: f32(math.cos(angle)) * speed * 5
			}
			life: life
			initial_life: life
			kind: kind
			visual_tier: visual_tier
			height: 1
			in_course: in_course
		}
	}
}

fn (mut simulation Simulation) spawn_ship_particles() {
	if simulation.ship.lifecycle_counter >= -ship_spawn_invulnerability_ticks {
		simulation.spawn_jet_particle(0.02623)
		simulation.spawn_jet_particle(-0.02623)
	}
	simulation.next_star_distance -= simulation.ship.speed
	if simulation.next_star_distance <= 0 {
		simulation.spawn_background_stars()
		simulation.next_star_distance = 1
	}
}

fn (mut simulation Simulation) spawn_jet_particle(angle_offset f32) {
	position := Vec2{
		x: wrap_angle(simulation.ship.angle - simulation.ship.bank * 0.1 + angle_offset)
		y: simulation.ship.relative_depth - 0.15
	}
	in_course := simulation.particle_in_course(position)
	index := simulation.next_particle_index(false)
	if index >= 0 {
		speed_bias := simulation.particle_random.next_f32(0.8) + 0.4
		life := 16 + simulation.particle_random.next_int(8)
		luminosity := 0.8 + simulation.particle_random.next_f32(0.2)
		simulation.particles[index] = Particle{
			alive: true
			position: position
			velocity: Vec2{ y: -0.2 * speed_bias }
			life: life
			initial_life: life
			kind: .jet
			height: 1
			in_course: in_course
			luminosity: luminosity
		}
	}
}

fn (mut simulation Simulation) spawn_background_stars() {
	for _ in 0 .. 5 {
		index := simulation.next_particle_index(false)
		if index < 0 {
			break
		}
		// Distribute the distant field around the full tunnel. Restricting it to
		// the half opposite the ship left the entire lower screen empty.
		angle := simulation.ship.angle + simulation.ship_random.next_signed_f32(f32(math.pi))
		height := -8 - simulation.ship_random.next_f32(56)
		_ = simulation.particle_random.next_f32(0.8)
		life := 100 + simulation.particle_random.next_int(50)
		luminosity := 0.8 + simulation.particle_random.next_f32(0.2)
		simulation.particles[index] = Particle{
			alive: true
			position: Vec2{ x: wrap_angle(angle), y: 32 }
			life: life
			initial_life: life
			kind: .star
			height: height
			in_course: false
			luminosity: luminosity
		}
	}
}

fn (mut simulation Simulation) update_particles() {
	for mut particle in simulation.particles {
		if !particle.alive {
			continue
		}
		if particle.position.y < -2 {
			particle.alive = false
			continue
		}
		particle.position.y -= match particle.kind {
			.fragment { simulation.ship.speed * 0.5 }
			.spark { simulation.ship.speed * 0.33 }
			else { simulation.ship.speed }
		}
	}
	simulation.dispatch_particle_motion()
	for mut particle in simulation.particles {
		if !particle.alive {
			continue
		}
		particle.height += particle.height_velocity
		if particle.kind != .star {
			particle.height_velocity -= if particle.kind == .fragment {
				f32(0.01)
			} else {
				f32(0.02)
			}
			if particle.in_course && particle.height < 0 {
				particle.height_velocity *= if particle.kind == .fragment {
					f32(-0.6)
				} else {
					f32(-0.8)
				}
				particle.velocity.x *= 0.9
				particle.velocity.y *= 0.9
				particle.height_velocity *= 0.9
				particle.height += particle.height_velocity * 2
				particle.in_course = simulation.particle_in_course(particle.position)
			}
		}
		if particle.kind == .fragment {
			particle.spin += particle.spin_velocity
			particle.secondary_spin += particle.secondary_spin_velocity
			particle.spin_velocity *= 0.98
			particle.secondary_spin_velocity *= 0.98
			particle.scale *= 0.98
		}
		particle.luminosity *= 0.98
	}
}

fn (simulation &Simulation) particle_in_course(position Vec2) bool {
	if !simulation.config.procedural_course {
		return true
	}
	slice := simulation.course.slice_at(simulation.ship.course_position + position.y)
	return course_side(position.x, slice) == 0
}

fn (mut simulation Simulation) spawn_multiplier_popup(position Vec2, multiplier int, points int) {
	if multiplier <= 1 || simulation.multiplier_popups.len == 0 {
		return
	}
	simulation.multiplier_popup_cursor--
	if simulation.multiplier_popup_cursor < 0 {
		simulation.multiplier_popup_cursor = simulation.multiplier_popups.len - 1
	}
	simulation.multiplier_popups[simulation.multiplier_popup_cursor] = MultiplierPopup{
		alive: true
		position: position
		velocity: Vec2{
			x: simulation.multiplier_popup_random.next_signed_f32(0.001)
			y: 0.2 - simulation.multiplier_popup_random.next_f32(0.2)
		}
		life: int(30 + f32(multiplier) * 0.3)
		alpha: 0.8
		multiplier: multiplier
		large_label: points >= 100
	}
}

fn (mut simulation Simulation) update_multiplier_popups() {
	for mut popup in simulation.multiplier_popups {
		if !popup.alive {
			continue
		}
		popup.position.x += popup.velocity.x * popup.position.y
		popup.position.y += popup.velocity.y
		popup.life--
		if popup.life < 0 {
			popup.alive = false
		}
		if popup.alpha >= 0.03 {
			popup.alpha -= 0.03
		}
	}
}

pub fn (simulation &Simulation) living_multiplier_popups() int {
	mut count := 0
	for popup in simulation.multiplier_popups {
		if popup.alive {
			count++
		}
	}
	return count
}

pub fn (simulation &Simulation) living_particles() int {
	mut count := 0
	for particle in simulation.particles {
		if particle.alive {
			count++
		}
	}
	return count
}

pub fn (simulation &Simulation) living_shots() int {
	mut count := 0
	for shot in simulation.shots {
		if shot.alive {
			count++
		}
	}
	return count
}

pub fn (simulation &Simulation) living_enemies() int {
	mut count := 0
	for enemy in simulation.enemies {
		if enemy.alive {
			count++
		}
	}
	return count
}

pub fn (simulation &Simulation) living_passed_enemies() int {
	mut count := 0
	for enemy in simulation.passed_enemies {
		if enemy.alive {
			count++
		}
	}
	return count
}

fn (mut simulation Simulation) update_ship(input InputState) {
	simulation.ship.lifecycle_counter++
	simulation.ship.invulnerable_ticks = if simulation.ship.lifecycle_counter < 0 {
		-simulation.ship.lifecycle_counter
	} else {
		0
	}
	rules := rules_for_grade(simulation.config.grade)
	mut desired_speed := simulation.ship.target_speed
	if input.brake {
		desired_speed *= charge_brake_speed_ratio
	} else {
		regenerated_speed := simulation.ship.regenerative_charge * regenerative_release_ratio
		simulation.ship.speed += regenerated_speed
		desired_speed += regenerated_speed
		simulation.ship.regenerative_charge -= regenerated_speed
	}
	if simulation.ship.speed < desired_speed {
		simulation.ship.speed += (desired_speed - simulation.ship.speed) * ship_acceleration_response
	} else {
		if input.brake {
			simulation.ship.regenerative_charge -= (desired_speed - simulation.ship.speed) * regenerative_capture_ratio
		}
		simulation.ship.speed += (desired_speed - simulation.ship.speed) * ship_deceleration_response
	}
	previous_whole_distance := int(simulation.ship.distance)
	simulation.ship.distance += simulation.ship.speed
	if !simulation.game_over {
		simulation.score += int(simulation.ship.distance) - previous_whole_distance
	}
	simulation.ship.course_position += simulation.ship.speed
	course_length := simulation.active_course_length()
	for simulation.ship.course_position >= f32(course_length) {
		simulation.ship.course_position -= f32(course_length)
		simulation.ship.lap++
	}
	if input.right {
		simulation.ship.bank += (-rules.bank_max - simulation.ship.bank) * ship_bank_response
	}
	if input.left {
		simulation.ship.bank += (rules.bank_max - simulation.ship.bank) * ship_bank_response
	}
	mut over_accelerating := false
	if input.up {
		if simulation.ship.relative_depth < relative_depth_max {
			simulation.ship.relative_depth = f32_min(relative_depth_max, simulation.ship.relative_depth + relative_depth_step)
		} else {
			simulation.ship.target_speed += rules.accel_ratio
			over_accelerating = !input.brake && !simulation.stage.in_boss_mode
				&& !simulation.stage.zone_complete_pending && simulation.zone_transition_ticks < 0
		}
	}
	if input.down && simulation.ship.relative_depth > relative_depth_min {
		simulation.ship.relative_depth = f32_max(relative_depth_min, simulation.ship.relative_depth - relative_depth_step)
	}
	// Rearward travel changes framing and collision position without dropping
	// below the source default speed or shortening the source sight range.
	forward_depth := f32_max(simulation.ship.relative_depth, 0)
	acceleration_speed := forward_depth * (rules.max_speed - rules.default_speed) / relative_depth_max + rules.default_speed
	simulation.ship.sight_depth = ship_base_sight_depth * (1 + forward_depth / relative_depth_max)
	if simulation.ship.speed > rules.max_speed {
		simulation.ship.sight_depth += ship_base_sight_depth * (simulation.ship.speed - rules.max_speed) / rules.max_speed * 3
	}
	if over_accelerating {
		simulation.ship.target_speed += (acceleration_speed - simulation.ship.target_speed) * overdrive_target_response
	} else if simulation.ship.target_speed < acceleration_speed {
		simulation.ship.target_speed += (acceleration_speed - simulation.ship.target_speed) * speed_target_rise_response
	} else {
		simulation.ship.target_speed += (acceleration_speed - simulation.ship.target_speed) * speed_target_fall_response
	}
	simulation.ship.bank *= ship_bank_retention
	ship_slice := simulation.course.slice_at(simulation.ship.course_position + simulation.ship.relative_depth)
	radius_scale := if ship_slice.rad > 0 { 21 / ship_slice.rad } else { f32(1) }
	simulation.ship.angle = wrap_angle(simulation.ship.angle + simulation.ship.bank * ship_turn_rate * radius_scale)
	simulation.ship.eye_angle = wrap_angle(simulation.ship.eye_angle + angle_delta(simulation.ship.eye_angle, simulation.ship.angle) * camera_angle_response)
	if simulation.ship.screen_shake_ticks > 0 {
		simulation.ship.screen_shake_ticks--
	}
	if simulation.config.procedural_course {
		simulation.constrain_ship_to_course()
	}
}

fn (mut simulation Simulation) sample_screen_shake() {
	simulation.ship.camera_shake_angle = 0
	simulation.ship.camera_shake_x = 0
	simulation.ship.camera_shake_y = 0
	if simulation.ship.screen_shake_ticks <= 0 {
		return
	}
	scale := simulation.ship.screen_shake_intensity * f32(simulation.ship.screen_shake_ticks + 6)
	mx := simulation.ship_random.next_signed_f32(scale)
	my := simulation.ship_random.next_signed_f32(scale)
	mz := simulation.ship_random.next_signed_f32(scale)
	simulation.ship.camera_shake_angle = mx * 0.002
	// Camera shake offsets both eye and look-at positions in all three axes.
	// Retain angular roll for the torus coordinate and expose the other two
	// components as a shared screen offset for tunnel and entity rendering.
	simulation.ship.camera_shake_x = my * 0.002
	simulation.ship.camera_shake_y = mz * 0.002
}

pub fn (simulation &Simulation) camera_angle() f32 {
	return wrap_angle(simulation.ship.eye_angle + simulation.ship.camera_shake_angle)
}

fn (simulation &Simulation) active_course_length() int {
	if simulation.course.slices.len > 0 {
		return simulation.course.slices.len
	}
	return int_max(1, simulation.config.course_length)
}

pub fn (simulation &Simulation) presentation_course_position(frame_fraction f32) f32 {
	ratio := clamp_f32(frame_fraction, 0, 1)
	length := f32(simulation.active_course_length())
	mut position := simulation.ship.course_position + simulation.ship.presentation_course_step * ratio
	for position >= length {
		position -= length
	}
	for position < 0 {
		position += length
	}
	return position
}

fn wrapped_course_delta(previous f32, current f32, course_length int) f32 {
	length := f32(int_max(course_length, 1))
	mut delta := current - previous
	if delta < -length * 0.5 {
		delta += length
	} else if delta > length * 0.5 {
		delta -= length
	}
	return delta
}

pub fn (simulation &Simulation) presentation_relative_depth(frame_fraction f32) f32 {
	ratio := clamp_f32(frame_fraction, 0, 1)
	return clamp_f32(simulation.ship.relative_depth + simulation.ship.presentation_depth_step * ratio, relative_depth_min, relative_depth_max)
}

pub fn (simulation &Simulation) presentation_eye_angle(frame_fraction f32) f32 {
	ratio := clamp_f32(frame_fraction, 0, 1)
	return wrap_angle(simulation.ship.eye_angle + simulation.ship.presentation_eye_step * ratio)
}

pub fn (simulation &Simulation) presentation_ship_angle(frame_fraction f32) f32 {
	ratio := clamp_f32(frame_fraction, 0, 1)
	return wrap_angle(simulation.ship.angle + simulation.ship.presentation_angle_step * ratio)
}

pub fn (simulation &Simulation) presentation_ship_bank(frame_fraction f32) f32 {
	ratio := clamp_f32(frame_fraction, 0, 1)
	return simulation.ship.bank + simulation.ship.presentation_bank_step * ratio
}

fn (mut simulation Simulation) constrain_ship_to_course() {
	slice := simulation.course.slice_at(simulation.ship.course_position + simulation.ship.relative_depth)
	if slice.full {
		return
	}
	// Inset the boundary by the collision rectangle. Clamping only the ship's
	// center to an edge let its wing and hit area remain over the missing track,
	// especially when a slice narrowed underneath it. If an artificial slice is
	// narrower than the ship, the constraint safely centers it.
	// The visual racing hull is wider than the responsive gameplay core. Keep a
	// narrower side inset so the ship can skim an edge without feeling as if an
	// invisible wingtip has hit it early.
	margin := simulation.ship_collision.x * 5 / f32_max(slice.rad, 0.001)
	constrained, target_angle, side := ship_course_constraint(simulation.ship.angle, slice, margin)
	if !constrained {
		return
	}
	mut correction := (-f32(side) - simulation.ship.bank) * 0.05
	correction = clamp_f32(correction, -1, 1)
	simulation.ship.speed *= 1 - f32(math.abs(correction))
	simulation.ship.bank += correction
	// Clamp immediately only after the center has actually left the walkable
	// span. Contact with the inset collision margin eases inward over several
	// ticks, avoiding the former sideways snap.
	outside := course_side(simulation.ship.angle, slice) != 0
	ratio := if outside { f32(1) } else { f32(0.3) }
	simulation.ship.angle = wrap_angle(simulation.ship.angle + angle_delta(simulation.ship.angle, target_angle) * ratio)
}

fn ship_course_constraint(angle f32, slice CourseSlice, margin f32) (bool, f32, int) {
	if slice.full {
		return false, angle, 0
	}
	track_width := wrap_angle(slice.right - slice.left)
	if track_width < 0.000001 {
		return false, angle, 0
	}
	position := wrap_angle(angle - slice.left)
	usable_margin := f32_max(margin, 0)
	mut target := angle
	if track_width <= usable_margin * 2 {
		target = wrap_angle(slice.left + track_width * 0.5)
	} else if position < usable_margin {
		target = wrap_angle(slice.left + usable_margin)
	} else if position <= track_width && position > track_width - usable_margin {
		target = wrap_angle(slice.right - usable_margin)
	} else if position > track_width {
		target = if wrapped_distance(angle, slice.left) < wrapped_distance(angle, slice.right) {
			wrap_angle(slice.left + usable_margin)
		} else {
			wrap_angle(slice.right - usable_margin)
		}
	} else {
		return false, angle, 0
	}
	delta := angle_delta(angle, target)
	side := if delta >= 0 { -1 } else { 1 }
	return true, target, side
}

fn (mut simulation Simulation) destroy_ship() {
	if simulation.god_mode || simulation.ship.lifecycle_counter <= 0 {
		return
	}
	simulation.ship.hits++
	simulation.ship.lifecycle_counter = -ship_respawn_protection_ticks
	simulation.ship.invulnerable_ticks = ship_respawn_protection_ticks
	simulation.ship.target_speed = 0
	simulation.ship.regenerative_charge = 0
	simulation.ship.screen_shake_ticks = ship_hit_shake_ticks
	simulation.ship.screen_shake_intensity = ship_hit_shake_intensity
	simulation.spawn_ship_destruction_particles(Vec2{
		x: simulation.ship.angle
		y: simulation.ship.relative_depth
	})
	simulation.fire_cooldown = 0
	simulation.side_fire_cooldown = side_fire_idle_ticks
	if simulation.charging_shot >= 0 {
		simulation.shots[simulation.charging_shot].alive = false
		simulation.charging_shot = -1
	}
	if simulation.config.run_time_ms > 0 {
		simulation.change_time(-collision_penalty_seconds)
	}
}

fn wrap_angle(value f32) f32 {
	mut result := value
	for result < 0 {
		result += f32(math.pi * 2)
	}
	for result >= f32(math.pi * 2) {
		result -= f32(math.pi * 2)
	}
	return result
}

fn wrapped_distance(a f32, b f32) f32 {
	return f32(math.abs(angle_delta(a, b)))
}

pub fn (mut simulation Simulation) spawn(position Vec2, direction f32, speed f32, program_id int) bool {
	return simulation.spawn_index(position, direction, speed, program_id) >= 0
}

fn (mut simulation Simulation) spawn_index(position Vec2, direction f32, speed f32, program_id int) int {
	for index in 0 .. simulation.bullets.len {
		if simulation.bullets[index].alive {
			continue
		}
		simulation.bullets[index] = Bullet{
			alive: true
			position: position
			direction: direction
			speed: speed
			program_id: program_id
		}
		simulation.bullet_patterns[index] = BulletPatternState{}
		return index
	}
	return -1
}

fn (mut simulation Simulation) spawn_pattern_shot(position Vec2, program PatternProgram, rank f32, shot PatternShot) bool {
	return simulation.spawn_pipeline_shot(position, PatternPipeline{
		programs: [program]
		ranks: [rank]
	}, 0, program, rank, shot)
}

fn (mut simulation Simulation) spawn_pipeline_shot(position Vec2, pipeline PatternPipeline, pipeline_index int, current_program PatternProgram, current_rank f32, shot PatternShot) bool {
	mut runner := PatternRunner{}
	mut active := false
	mut next_pipeline_index := pipeline_index
	mut morph_seed := false
	if shot.action_entry >= 0 {
		runner = new_pattern_runner_at(current_program, PatternContext{
			rank: current_rank
			parameters: shot.parameters
			aim_direction: aim_direction_reversed(position, Vec2{
				x: simulation.ship.angle
				y: simulation.ship.relative_depth
			}, pipeline.x_reverse)
			base_direction: shot.direction
			base_speed: shot.speed
			default_speed: pipeline.default_speed
			speed_scale: pipeline.speed_scale
		}, shot.action_entry) or { return false }
		active = true
	} else if pipeline_index + 1 < pipeline.programs.len {
		next_pipeline_index++
		next_program := pipeline.programs[next_pipeline_index]
		runner = new_pattern_runner(next_program, PatternContext{
			rank: pipeline.ranks[next_pipeline_index]
			aim_direction: aim_direction_reversed(position, Vec2{
				x: simulation.ship.angle
				y: simulation.ship.relative_depth
			}, pipeline.x_reverse)
			base_direction: shot.direction
			base_speed: shot.speed
			default_speed: pipeline.default_speed
			speed_scale: pipeline.speed_scale
		})
		active = true
		morph_seed = true
	}
	index := simulation.spawn_index(position, shot.direction, shot.speed, -1)
	if index < 0 {
		return false
	}
	simulation.bullets[index].x_reverse = pipeline.x_reverse
	simulation.bullets[index].visual_shape = pipeline.visual_shape
	simulation.bullets[index].visual_scale = pipeline.visual_scale
	simulation.bullets[index].long_range = pipeline.long_range
	simulation.bullets[index].speed_rank = pipeline.speed_rank
	if active {
		simulation.bullet_patterns[index] = BulletPatternState{
			active: true
			runner: runner
			pipeline: pipeline
			pipeline_index: next_pipeline_index
			morph_seed: morph_seed
		}
	}
	return true
}

fn (simulation &Simulation) apply_steps(mut bullet Bullet) {
	if bullet.program_id < 0 || bullet.program_id >= simulation.config.programs.len {
		return
	}
	program := simulation.config.programs[bullet.program_id]
	for bullet.next_step < program.steps.len
		&& program.steps[bullet.next_step].at_age <= bullet.age {
		step := program.steps[bullet.next_step]
		match step.kind {
			.change_speed {
				if step.duration <= 0 {
					bullet.speed = step.target
				} else {
					bullet.speed_delta = (step.target - bullet.speed) / f32(step.duration)
					bullet.speed_ticks = step.duration
				}
			}
			.change_direction {
				if step.duration <= 0 {
					bullet.direction = step.target
				} else {
					bullet.direction_delta = angle_delta(bullet.direction, step.target) / f32(step.duration)
					bullet.direction_ticks = step.duration
				}
			}
			.vanish {
				bullet.alive = false
			}
		}
		bullet.next_step++
	}
}

fn angle_delta(from f32, to f32) f32 {
	mut delta := to - from
	for delta > f32(math.pi) {
		delta -= f32(math.pi * 2)
	}
	for delta < -f32(math.pi) {
		delta += f32(math.pi * 2)
	}
	return delta
}

pub fn (simulation &Simulation) living_bullets() int {
	mut count := 0
	for bullet in simulation.bullets {
		if bullet.alive && bullet.disappear_ticks <= 0 {
			count++
		}
	}
	return count
}

// checksum is intentionally based on exact f32 bits. It detects simulation drift
// across headless runs and future replay implementations.
pub fn (simulation &Simulation) checksum() u64 {
	mut value := u64(14695981039346656037)
	value = fnv1a(value, u64(simulation.tick))
	value = fnv1a(value, u64(f32_bits(simulation.ship.angle)))
	value = fnv1a(value, u64(f32_bits(simulation.ship.bank)))
	value = fnv1a(value, u64(f32_bits(simulation.ship.relative_depth)))
	value = fnv1a(value, u64(f32_bits(simulation.ship.target_speed)))
	value = fnv1a(value, u64(f32_bits(simulation.ship.speed)))
	value = fnv1a(value, u64(f32_bits(simulation.ship.distance)))
	value = fnv1a(value, u64(f32_bits(simulation.ship.regenerative_charge)))
	value = fnv1a(value, u64(simulation.ship.hits))
	value = fnv1a(value, u64(simulation.fired_shots))
	value = fnv1a(value, u64(simulation.side_fired_shots))
	value = fnv1a(value, u64(simulation.bullets_cleared))
	value = fnv1a(value, u64(simulation.destroyed_enemies))
	value = fnv1a(value, u64(simulation.spawned_enemies))
	value = fnv1a(value, u64(simulation.enemy_shots_fired))
	value = fnv1a(value, u64(simulation.score))
	value = fnv1a(value, u64(simulation.remaining_time_ms))
	value = fnv1a(value, u64(simulation.time_extensions))
	value = fnv1a(value, u64(simulation.warning_beeps))
	value = fnv1a(value, u64(f32_bits(simulation.level)))
	value = fnv1a(value, u64(simulation.zone))
	value = fnv1a(value, u64(simulation.zone_advances))
	for shot in simulation.shots {
		if !shot.alive {
			continue
		}
		value = fnv1a(value, u64(shot.age))
		value = fnv1a(value, u64(shot.charge_ticks))
		value = fnv1a(value, u64(shot.multiplier))
		value = fnv1a(value, u64(if shot.star_shell { 1 } else { 0 }))
		value = fnv1a(value, u64(f32_bits(shot.size)))
		value = fnv1a(value, u64(f32_bits(shot.target_size)))
		value = fnv1a(value, u64(f32_bits(shot.position.x)))
		value = fnv1a(value, u64(f32_bits(shot.position.y)))
	}
	for bullet in simulation.bullets {
		if !bullet.alive {
			continue
		}
		value = fnv1a(value, u64(bullet.age))
		value = fnv1a(value, u64(bullet.disappear_ticks))
		value = fnv1a(value, u64(f32_bits(bullet.position.x)))
		value = fnv1a(value, u64(f32_bits(bullet.position.y)))
		value = fnv1a(value, u64(f32_bits(bullet.direction)))
		value = fnv1a(value, u64(f32_bits(bullet.speed)))
		value = fnv1a(value, u64(f32_bits(bullet.x_reverse)))
		value = fnv1a(value, u64(bullet.visual_shape))
		value = fnv1a(value, u64(f32_bits(bullet.visual_scale)))
		value = fnv1a(value, u64(if bullet.long_range { 1 } else { 0 }))
		value = fnv1a(value, u64(f32_bits(bullet.speed_rank)))
	}
	for enemy in simulation.enemies {
		if !enemy.alive {
			continue
		}
		value = fnv1a(value, u64(enemy.age))
		value = fnv1a(value, u64(enemy.health))
		value = fnv1a(value, u64(enemy.kind))
		value = fnv1a(value, u64(enemy.score))
		value = fnv1a(value, u64(enemy.pattern))
		value = fnv1a(value, u64(enemy.spec_index))
		value = fnv1a(value, u64(if enemy.rank_counted { 1 } else { 0 }))
		value = fnv1a(value, u64(f32_bits(enemy.base_turn)))
		value = fnv1a(value, u64(f32_bits(enemy.turn_speed)))
		value = fnv1a(value, u64(f32_bits(enemy.speed)))
		value = fnv1a(value, u64(f32_bits(enemy.limit_depth)))
		value = fnv1a(value, u64(enemy.flip_ticks))
		value = fnv1a(value, u64(f32_bits(enemy.flip_velocity.x)))
		value = fnv1a(value, u64(f32_bits(enemy.flip_velocity.y)))
		value = fnv1a(value, u64(if enemy.damaged { 1 } else { 0 }))
		value = fnv1a(value, u64(f32_bits(enemy.position.x)))
		value = fnv1a(value, u64(f32_bits(enemy.position.y)))
	}
	for enemy in simulation.passed_enemies {
		if !enemy.alive {
			continue
		}
		value = fnv1a(value, u64(enemy.age))
		value = fnv1a(value, u64(enemy.kind))
		value = fnv1a(value, u64(enemy.spec_index))
		value = fnv1a(value, u64(f32_bits(enemy.base_turn)))
		value = fnv1a(value, u64(f32_bits(enemy.turn_speed)))
		value = fnv1a(value, u64(f32_bits(enemy.speed)))
		value = fnv1a(value, u64(f32_bits(enemy.position.x)))
		value = fnv1a(value, u64(f32_bits(enemy.position.y)))
	}
	for particle in simulation.particles {
		if !particle.alive {
			continue
		}
		value = fnv1a(value, u64(particle.life))
		value = fnv1a(value, u64(particle.kind))
		value = fnv1a(value, u64(f32_bits(particle.position.x)))
		value = fnv1a(value, u64(f32_bits(particle.position.y)))
		value = fnv1a(value, u64(f32_bits(particle.height)))
		value = fnv1a(value, u64(f32_bits(particle.height_velocity)))
		value = fnv1a(value, u64(if particle.in_course { 1 } else { 0 }))
		value = fnv1a(value, u64(f32_bits(particle.luminosity)))
		value = fnv1a(value, u64(f32_bits(particle.spin)))
		value = fnv1a(value, u64(f32_bits(particle.spin_velocity)))
		value = fnv1a(value, u64(f32_bits(particle.secondary_spin)))
		value = fnv1a(value, u64(f32_bits(particle.secondary_spin_velocity)))
		value = fnv1a(value, u64(f32_bits(particle.scale)))
		value = fnv1a(value, u64(f32_bits(particle.fragment_width)))
		value = fnv1a(value, u64(f32_bits(particle.fragment_height)))
	}
	return value
}

fn fnv1a(value u64, input u64) u64 {
	return (value ^ input) * u64(1099511628211)
}

fn f32_bits(value f32) u32 {
	return unsafe { *(&u32(&value)) }
}
