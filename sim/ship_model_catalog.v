module sim

import math

// Optional tuning-scene overrides. Disabled entries keep the game's compiled
// procedural/readable hulls; enabled entries replace one preview's mesh.
pub struct ShipModelCatalog {
pub:
	version      int = 1
	player       ShipModel
	enemy_small  ShipModel
	enemy_middle ShipModel
	enemy_boss   ShipModel
}

pub struct ShipModel {
pub:
	enabled bool
	parts   []ShipModelPart
}

pub struct ShipModelSection {
pub:
	x           f32
	y           f32
	z           f32
	half_width  f32
	half_height f32
}

pub struct ShipModelPart {
pub:
	kind       string
	color      int = 7
	sections   []ShipModelSection
	root_width f32
	span       f32
	front_z    f32
	tip_z      f32
	rear_z     f32
	thickness  f32
	angle      f32
}

pub fn (catalog ShipModelCatalog) for_kind(kind int) ShipModel {
	return match kind {
		-1 { catalog.player }
		0 { catalog.enemy_small }
		1 { catalog.enemy_middle }
		else { catalog.enemy_boss }
	}
}

pub fn validate_ship_model_catalog(catalog ShipModelCatalog) ! {
	if catalog.version != 1 {
		return error('unsupported model-file version ${catalog.version}')
	}
	names := ['player', 'enemy_small', 'enemy_middle', 'enemy_boss']
	models := [catalog.player, catalog.enemy_small, catalog.enemy_middle, catalog.enemy_boss]
	for index, model in models {
		name := names[index]
		if model.enabled && model.parts.len == 0 {
			return error('${name}: enabled model has no parts')
		}
		if model.parts.len > 32 {
			return error('${name}: at most 32 parts are supported')
		}
		for part in model.parts {
			if part.color < 0 || part.color > 7 {
				return error('${name}: color must be 0..7')
			}
			match part.kind {
				'tapered_hull', 'round_hull' {
					if part.sections.len < 2 || part.sections.len > 16 {
						return error('${name}: hull needs 2..16 sections')
					}
					mut previous_z := f32(-1000)
					for section in part.sections {
						if !finite_model_value(section.x, 10) || !finite_model_value(section.y,
							10) || !finite_model_value(section.z, 10) || section.z <= previous_z
							|| !positive_model_value(section.half_width, 5)
							|| !positive_model_value(section.half_height, 5) {
							return error('${name}: invalid hull section (z must increase from rear to nose)')
						}
						previous_z = section.z
					}
				}
				'wing_pair' {
					if !positive_model_value(part.root_width, 5) || !positive_model_value(part.span,
						10) || part.span <= part.root_width || !positive_model_value(part.thickness,
						2) || !finite_model_value(part.front_z, 10) || !finite_model_value(part.tip_z,
						10) || !finite_model_value(part.rear_z, 10) {
						return error('${name}: invalid wing pair')
					}
				}
				'spike_pair' {
					if !finite_model_value(part.angle, f32(math.pi)) {
						return error('${name}: invalid spike angle')
					}
				}
				else {
					return error('${name}: unknown part kind ${part.kind}')
				}
			}
		}
	}
}

fn finite_model_value(value f32, limit f32) bool {
	return value == value && value >= -limit && value <= limit
}

fn positive_model_value(value f32, limit f32) bool {
	return finite_model_value(value, limit) && value > 0
}
