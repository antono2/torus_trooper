module sim

pub enum Grade {
	normal
	hard
	extreme
}

// GradeRules contains the ship and stage constants. Keeping them
// as data makes difficulty selection deterministic and keeps future CPU/OpenCL
// backends on the same ruleset.
pub struct GradeRules {
pub:
	name          string
	letter        string
	default_speed f32
	max_speed     f32
	accel_ratio   f32
	bank_max      f32
	boss_app_rank int
}

pub fn rules_for_grade(grade Grade) GradeRules {
	return match grade {
		.normal {
			GradeRules{
				name: 'NORMAL'
				letter: 'N'
				default_speed: 0.4
				max_speed: 0.8
				accel_ratio: 0.002
				bank_max: 0.8
				boss_app_rank: 100
			}
		}
		.hard {
			GradeRules{
				name: 'HARD'
				letter: 'H'
				default_speed: 0.6
				max_speed: 1.2
				accel_ratio: 0.003
				bank_max: 1.0
				boss_app_rank: 160
			}
		}
		.extreme {
			GradeRules{
				name: 'EXTREME'
				letter: 'E'
				default_speed: 0.8
				max_speed: 1.6
				accel_ratio: 0.004
				bank_max: 1.2
				boss_app_rank: 250
			}
		}
	}
}
