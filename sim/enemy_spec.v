// Generates enemy specifications, barrage choices and boss-bit formations from seeded state.
module sim

import math

pub enum BossBitFormation {
	none
	round
	line
}

pub struct GeneratedBarrageSpec {
pub:
	base_pattern string
	rank         f32
	speed_rank   f32
	morph_rank   f32
	morphs       []string
	interval     int
	bullet_shape int
	visual_scale f32 = 1
	long_range   bool
	no_x_reverse bool
}

pub struct EnemySpec {
pub:
	kind                int
	shield              int
	score               int
	base_speed          f32
	ship_speed_ratio    f32
	visual_range        f32
	bank_max            f32
	base_bank           f32
	shape_seed          int
	collision_size      Vec2
	barrage             GeneratedBarrageSpec
	bit_count           int
	bit_formation       BossBitFormation
	bit_distance        f32
	bit_angular_step    f32
	bit_barrage         GeneratedBarrageSpec
	middle_boss         bool
	aim_ship            bool
	has_limit_depth     bool
	no_fire_depth_limit bool
}

pub struct ZoneEnemySpecs {
pub:
	small  []EnemySpec
	middle []EnemySpec
	boss   []EnemySpec
}

pub struct ZoneEnemySetup {
pub:
	specs                ZoneEnemySpecs
	next_small_distance  f32
	next_middle_distance f32
}

pub struct BossBitPose {
pub:
	position  Vec2
	direction f32
	rotation  f32
}

pub fn shape_random_after_zone(specs ZoneEnemySpecs, fallback_seed u32) Mt19937 {
	seed := if specs.boss.len > 0 { u32(specs.boss.last().shape_seed) } else { fallback_seed }
	mut rng := new_mt19937(seed)
	// Large ShipShape creation consumes fifteen values. The damaged copy resets
	// to the same seed, so this is the shared fragment stream state
	// after the final boss specification has been built.
	for _ in 0 .. 15 {
		_ = rng.next_u32()
	}
	return rng
}

pub fn boss_bit_pose(spec EnemySpec, boss_position Vec2, index int, age int) BossBitPose {
	if spec.bit_formation == .round {
		step := f32(math.pi * 2) / f32(spec.bit_count)
		angle := step * f32(index) + f32(age) * spec.bit_angular_step
		return BossBitPose{
			position: Vec2{
				x: wrap_angle(boss_position.x + spec.bit_distance * 2 * f32(math.sin(angle)))
				y: boss_position.y + spec.bit_distance * 2 * f32(math.cos(angle)) * 5
			}
			direction: f32(math.pi) - f32(math.sin(angle)) * 0.05
			rotation: f32(age) * f32(math.pi) * 7 / 180
		}
	}
	if spec.bit_formation == .line {
		side := f32((index % 2) * 2 - 1)
		distance_index := f32(index / 2 + 1)
		return BossBitPose{
			position: Vec2{
				x: wrap_angle(boss_position.x + spec.bit_distance * 1.5 * distance_index * side)
				y: boss_position.y
			}
			direction: f32(math.pi)
			rotation: f32(age) * f32(math.pi) * 7 / 180
		}
	}
	return BossBitPose{
		position: boss_position
		direction: f32(math.pi)
		rotation: f32(age) * f32(math.pi) * 7 / 180
	}
}

const middle_pattern_names = ['middle/35way', 'middle/alt_nway', 'middle/alt_sideshot',
	'middle/backword_spread', 'middle/clow_rocket', 'middle/diamondnway', 'middle/fast_aim',
	'middle/forward_1way', 'middle/grow', 'middle/grow3way', 'middle/nway', 'middle/random_fire',
	'middle/spread2blt', 'middle/squirt']

const morph_pattern_names = ['morph/0to1', 'morph/accel', 'morph/accelshot', 'morph/bar',
	'morph/divide', 'morph/fast', 'morph/fire_slowshot', 'morph/slide', 'morph/slowdown',
	'morph/speed_rnd', 'morph/twin', 'morph/wedge_half', 'morph/wide']

pub fn generate_zone_enemy_specs(level f32, grade Grade, middle_boss bool, boss_count int, mut rng Mt19937) ZoneEnemySpecs {
	return generate_zone_enemy_setup(level, grade, middle_boss, boss_count, mut rng).specs
}

pub fn generate_zone_enemy_setup(level f32, grade Grade, middle_boss bool, boss_count int,
	mut rng Mt19937) ZoneEnemySetup {
	mut small := []EnemySpec{}
	mut small_index := 0
	// Preserve the dynamic for-loop condition: its random upper bound is
	// evaluated before every iteration, including the final failed check.
	for small_index < 2 + rng.next_int(2) {
		small << generate_small_enemy_spec(level * 1.8, grade, mut rng)
		small_index++
	}
	mut middle := []EnemySpec{}
	mut middle_index := 0
	for middle_index < 2 + rng.next_int(2) {
		middle << generate_middle_enemy_spec(level * 1.9, mut rng)
		middle_index++
	}
	// StageManager initializes both distance counters before creating boss specs.
	// These draws therefore contribute to every subsequent boss and zone value.
	next_small_distance := f32(rng.next_int(16) + 6)
	next_middle_distance := f32(rng.next_int(200) + 33)
	mut boss := []EnemySpec{}
	mut count := int_max(1, boss_count)
	if boss_count <= 0 && middle_boss && level > 5 && rng.next_int(3) != 0 {
		count = int_min(4, 1 + rng.next_int(int(math.sqrt(level / 5)) + 1))
	}
	for _ in 0 .. count {
		mut boss_level := level * 2 / f32(count)
		if middle_boss {
			boss_level *= 1.33
		}
		speed_ratio := 0.8 + f32(int(grade)) * 0.04 + rng.next_f32(0.03)
		boss << generate_boss_enemy_spec(boss_level, speed_ratio, middle_boss, mut rng)
	}
	return ZoneEnemySetup{
		specs: ZoneEnemySpecs{ small: small, middle: middle, boss: boss }
		next_small_distance: next_small_distance
		next_middle_distance: next_middle_distance
	}
}

fn generate_small_enemy_spec(level f32, grade Grade, mut rng Mt19937) EnemySpec {
	base_speed := 0.05 + rng.next_f32(0.1)
	ship_speed_ratio := 0.25 + rng.next_f32(0.25)
	visual_range := 10 + rng.next_f32(32)
	bank_max := 0.3 + rng.next_f32(0.7)
	base_bank := if rng.next_int(3) == 0 { 0.1 + rng.next_f32(0.2) } else { f32(0) }
	shape_seed := rng.next_int(99_999)
	grade_offset := (2 - int(grade)) * 8
	mut minimum := int(160 / level)
	minimum = int_max(40, int_min(80, minimum)) + grade_offset
	maximum := 80 + grade_offset
	interval := minimum + rng.next_int(maximum - minimum)
	barrage_level := level / (150.0 / f32(interval))
	return EnemySpec{
		kind: 0
		shield: 1
		score: 100
		base_speed: base_speed
		ship_speed_ratio: ship_speed_ratio
		visual_range: visual_range
		bank_max: bank_max
		base_bank: base_bank
		shape_seed: shape_seed
		collision_size: ship_shape_collision(0, shape_seed)
		barrage: generate_barrage_spec(barrage_level, interval, '', 0, 1, false, false, mut rng)
	}
}

fn generate_middle_enemy_spec(level f32, mut rng Mt19937) EnemySpec {
	base_speed := 0.1 + rng.next_f32(0.1)
	ship_speed_ratio := 0.4 + rng.next_f32(0.4)
	visual_range := 10 + rng.next_f32(32)
	bank_max := 0.2 + rng.next_f32(0.5)
	base_bank := if rng.next_int(4) == 0 { 0.05 + rng.next_f32(0.1) } else { f32(0) }
	shape_seed := rng.next_int(99_999)
	return EnemySpec{
		kind: 1
		shield: 10
		score: 500
		base_speed: base_speed
		ship_speed_ratio: ship_speed_ratio
		visual_range: visual_range
		bank_max: bank_max
		base_bank: base_bank
		shape_seed: shape_seed
		collision_size: ship_shape_collision(1, shape_seed)
		barrage: generate_barrage_spec(level, 0, 'middle', 2, 1, false, false, mut rng)
	}
}

fn generate_boss_enemy_spec(level f32, speed_ratio f32, middle_boss bool, mut rng Mt19937) EnemySpec {
	base_speed := 0.1 + rng.next_f32(0.1)
	visual_range := 16 + rng.next_f32(24)
	bank_max := 0.8 + rng.next_f32(0.4)
	shape_seed := rng.next_int(99_999)
	barrage := generate_barrage_spec(level, 0, 'middle', 2, 1.2, true, false, mut rng)
	if middle_boss {
		return EnemySpec{
			kind: 2
			shield: 30
			score: 2000
			base_speed: base_speed
			ship_speed_ratio: speed_ratio
			visual_range: visual_range
			bank_max: bank_max
			shape_seed: shape_seed
			collision_size: ship_shape_collision(2, shape_seed)
			barrage: barrage
			middle_boss: true
			aim_ship: true
			has_limit_depth: true
			no_fire_depth_limit: true
		}
	}
	bit_count := 2 + rng.next_int(3) * 2
	formation := if rng.next_int(2) == 0 { BossBitFormation.round } else { BossBitFormation.line }
	bit_distance := 0.33 + rng.next_f32(0.3)
	bit_step := 0.02 + rng.next_f32(0.02)
	mut bit_level := level / f32(bit_count / 2)
	mut minimum := int(120 / bit_level)
	minimum = int_max(20, int_min(60, minimum))
	interval := minimum + rng.next_int(60 - minimum)
	bit_level /= 60.0 / f32(interval)
	return EnemySpec{
		kind: 2
		shield: 30
		score: 2000
		base_speed: base_speed
		ship_speed_ratio: speed_ratio
		visual_range: visual_range
		bank_max: bank_max
		shape_seed: shape_seed
		collision_size: ship_shape_collision(2, shape_seed)
		barrage: barrage
		bit_count: bit_count
		bit_formation: formation
		bit_distance: bit_distance
		bit_angular_step: bit_step
		bit_barrage: generate_barrage_spec(bit_level, interval, '', 4, 1, true, true, mut rng)
		aim_ship: true
		has_limit_depth: true
		no_fire_depth_limit: true
	}
}

fn generate_barrage_spec(level f32, interval int, base_directory string, bullet_shape int, visual_scale f32, long_range bool, no_x_reverse bool, mut rng Mt19937) GeneratedBarrageSpec {
	mut rank := f32(math.sqrt(level)) / f32(8 - rng.next_int(3))
	if rank > 0.8 {
		rank = 0.8 + rng.next_f32(0.2)
	}
	remaining_level := level / (rank + 2)
	mut speed_rank := f32(math.sqrt(rank)) * (0.8 + rng.next_f32(0.2))
	if speed_rank < 1 {
		speed_rank = 1
	} else if speed_rank > 2 {
		speed_rank = f32(math.sqrt(speed_rank * 2))
	}
	mut morph_rank := remaining_level / speed_rank
	mut morph_count := 0
	for morph_rank > 1 {
		morph_count++
		morph_rank /= 3
	}
	base_pattern := if base_directory == 'middle' {
		middle_pattern_names[rng.next_int(middle_pattern_names.len)]
	} else {
		'basic/straight'
	}
	morphs := select_morph_patterns(morph_count, mut rng)
	return GeneratedBarrageSpec{
		base_pattern: base_pattern
		rank: rank
		speed_rank: speed_rank
		morph_rank: morph_rank
		morphs: morphs
		interval: interval
		bullet_shape: bullet_shape
		visual_scale: visual_scale
		long_range: long_range
		no_x_reverse: no_x_reverse
	}
}

fn select_morph_patterns(morph_count int, mut rng Mt19937) []string {
	mut available := morph_pattern_names.clone()
	mut morphs := []string{}
	for _ in 0 .. int_min(morph_count, morph_pattern_names.len) {
		index := rng.next_int(available.len)
		mut selected := index
		for available[selected].len == 0 {
			selected--
			if selected < 0 {
				selected = available.len - 1
			}
		}
		morphs << available[selected]
		// D's `delete ps[pi]` clears the selected class reference without
		// shrinking the dynamic array, so every random draw retains modulus 13.
		available[selected] = ''
	}
	return morphs
}
