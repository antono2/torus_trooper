// Loads, validates and saves configurable object scales and shot-distance settings.
module runtime

import json2
import os
import sim

const object_sizes_version = 2
const object_size_min = f32(0.1)
const object_size_max = f32(5)
const player_shot_distance_min = f32(2)
const player_shot_distance_max = f32(200)

pub enum ObjectSizeKind {
	player
	player_shot
	star_shot
	charged_shot
	enemy_small
	enemy_middle
	enemy_boss
	boss_bit
	bullet_triangle
	bullet_square
	bullet_bar
	particle_spark
	particle_jet
	particle_star
	particle_fragment
	tunnel
}

const object_size_kinds = [
	ObjectSizeKind.player,
	.player_shot,
	.star_shot,
	.charged_shot,
	.enemy_small,
	.enemy_middle,
	.enemy_boss,
	.boss_bit,
	.bullet_triangle,
	.bullet_square,
	.bullet_bar,
	.particle_spark,
	.particle_jet,
	.particle_star,
	.particle_fragment,
	.tunnel,
]

// ObjectSizes is intentionally flat: calibration labels use the visual field
// names in uppercase, so a label seen in the scene is easy to find in JSON.
// The gameplay distance remains beside those scales so one tuning file owns
// the complete high-resolution presentation calibration.
pub struct ObjectSizes {
pub mut:
	version              int = object_sizes_version
	player_shot_distance f32 = 75
	player               f32 = 1.5
	player_shot          f32 = 2
	star_shot            f32 = 3
	charged_shot         f32 = 3
	enemy_small          f32 = 3
	enemy_middle         f32 = 3
	enemy_boss           f32 = 4
	boss_bit             f32 = 3
	bullet_triangle      f32 = 3.5
	bullet_square        f32 = 3.5
	bullet_bar           f32 = 3.5
	particle_spark       f32 = 4
	particle_jet         f32 = 4
	particle_star        f32 = 4
	particle_fragment    f32 = 4
	tunnel               f32 = 4
}

pub fn default_object_sizes() ObjectSizes {
	return ObjectSizes{}
}

pub fn load_object_sizes(path string) ObjectSizes {
	return load_object_sizes_checked(path) or { default_object_sizes() }
}

// Interactive reload must report an unreadable or malformed file instead of
// silently replacing in-memory edits with defaults.
pub fn load_object_sizes_checked(path string) !ObjectSizes {
	content := os.read_file(path)!
	mut sizes := json2.decode[ObjectSizes](content)!
	sizes.normalize()
	return sizes
}

pub fn save_object_sizes(path string, sizes ObjectSizes) ! {
	mut normalized := sizes
	normalized.normalize()
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(normalized, prettify: true, escape_unicode: true))!
}

pub fn (mut sizes ObjectSizes) normalize() {
	sizes.version = object_sizes_version
	sizes.player_shot_distance = clamp_player_shot_distance(sizes.player_shot_distance)
	for kind in object_size_kinds {
		sizes.set(kind, sizes.get(kind))
	}
}

pub fn (sizes &ObjectSizes) get(kind ObjectSizeKind) f32 {
	return match kind {
		.player { sizes.player }
		.player_shot { sizes.player_shot }
		.star_shot { sizes.star_shot }
		.charged_shot { sizes.charged_shot }
		.enemy_small { sizes.enemy_small }
		.enemy_middle { sizes.enemy_middle }
		.enemy_boss { sizes.enemy_boss }
		.boss_bit { sizes.boss_bit }
		.bullet_triangle { sizes.bullet_triangle }
		.bullet_square { sizes.bullet_square }
		.bullet_bar { sizes.bullet_bar }
		.particle_spark { sizes.particle_spark }
		.particle_jet { sizes.particle_jet }
		.particle_star { sizes.particle_star }
		.particle_fragment { sizes.particle_fragment }
		.tunnel { sizes.tunnel }
	}
}

pub fn (mut sizes ObjectSizes) set(kind ObjectSizeKind, value f32) {
	normalized := clamp_object_size(value)
	match kind {
		.player {
			sizes.player = normalized
		}
		.player_shot {
			sizes.player_shot = normalized
		}
		.star_shot {
			sizes.star_shot = normalized
		}
		.charged_shot {
			sizes.charged_shot = normalized
		}
		.enemy_small {
			sizes.enemy_small = normalized
		}
		.enemy_middle {
			sizes.enemy_middle = normalized
		}
		.enemy_boss {
			sizes.enemy_boss = normalized
		}
		.boss_bit {
			sizes.boss_bit = normalized
		}
		.bullet_triangle {
			sizes.bullet_triangle = normalized
		}
		.bullet_square {
			sizes.bullet_square = normalized
		}
		.bullet_bar {
			sizes.bullet_bar = normalized
		}
		.particle_spark {
			sizes.particle_spark = normalized
		}
		.particle_jet {
			sizes.particle_jet = normalized
		}
		.particle_star {
			sizes.particle_star = normalized
		}
		.particle_fragment {
			sizes.particle_fragment = normalized
		}
		.tunnel {
			sizes.tunnel = normalized
		}
	}
}

pub fn object_size_kind(index int) ObjectSizeKind {
	return object_size_kinds[index]
}

pub fn object_size_kind_count() int {
	return object_size_kinds.len
}

pub fn object_size_label(kind ObjectSizeKind) string {
	return match kind {
		.player { 'PLAYER' }
		.player_shot { 'PLAYER_SHOT' }
		.star_shot { 'STAR_SHOT' }
		.charged_shot { 'CHARGED_SHOT' }
		.enemy_small { 'ENEMY_SMALL' }
		.enemy_middle { 'ENEMY_MIDDLE' }
		.enemy_boss { 'ENEMY_BOSS' }
		.boss_bit { 'BOSS_BIT' }
		.bullet_triangle { 'BULLET_TRIANGLE' }
		.bullet_square { 'BULLET_SQUARE' }
		.bullet_bar { 'BULLET_BAR' }
		.particle_spark { 'PARTICLE_SPARK' }
		.particle_jet { 'PARTICLE_JET' }
		.particle_star { 'PARTICLE_STAR' }
		.particle_fragment { 'PARTICLE_FRAGMENT' }
		.tunnel { 'TUNNEL' }
	}
}

pub fn (sizes &ObjectSizes) render_scales() sim.RenderScales {
	return sim.RenderScales{
		player: sizes.player
		player_shot: sizes.player_shot
		star_shot: sizes.star_shot
		charged_shot: sizes.charged_shot
		enemy_small: sizes.enemy_small
		enemy_middle: sizes.enemy_middle
		enemy_boss: sizes.enemy_boss
		boss_bit: sizes.boss_bit
		bullet_triangle: sizes.bullet_triangle
		bullet_square: sizes.bullet_square
		bullet_bar: sizes.bullet_bar
		particle_spark: sizes.particle_spark
		particle_jet: sizes.particle_jet
		particle_star: sizes.particle_star
		particle_fragment: sizes.particle_fragment
	}
}

fn clamp_object_size(value f32) f32 {
	if value != value {
		return 1
	}
	return f32_min(f32_max(value, object_size_min), object_size_max)
}

fn clamp_player_shot_distance(value f32) f32 {
	if value != value {
		return 35
	}
	return f32_min(f32_max(value, player_shot_distance_min), player_shot_distance_max)
}
