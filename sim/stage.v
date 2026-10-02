module sim

// StageProgression owns the rank gate for stage advancement.
// Enemy generation is kept separate so this small state machine can also be
// shared by a future compute backend without renderer or entity-pool state.
pub struct StageProgression {
pub mut:
	rank                  int
	zone                  int = 1
	zone_end_rank         int
	boss_appearance_rank  int
	bosses_remaining      int
	in_boss_mode          bool
	zone_complete_pending bool
pub:
	grade Grade
}

pub fn new_stage_progression(grade Grade, boss_count int) StageProgression {
	count := int_max(1, boss_count)
	interval := rules_for_grade(grade).boss_app_rank
	return StageProgression{
		grade: grade
		zone_end_rank: interval
		boss_appearance_rank: interval - count
		bosses_remaining: count
	}
}

// rank_up returns true only when the last boss completes the current zone.
pub fn (mut stage StageProgression) rank_up(is_boss bool) bool {
	if stage.in_boss_mode && !is_boss {
		return false
	}
	if stage.in_boss_mode {
		stage.bosses_remaining--
		if stage.bosses_remaining <= 0 {
			stage.rank++
			stage.in_boss_mode = false
			stage.zone_complete_pending = true
			stage.boss_appearance_rank = 9_999_999
			return true
		}
	}
	stage.rank++
	if stage.rank >= stage.boss_appearance_rank {
		stage.in_boss_mode = true
	}
	return false
}

pub fn (mut stage StageProgression) rank_down() {
	if !stage.in_boss_mode {
		stage.rank--
	}
}

pub fn (mut stage StageProgression) force_zone_complete() {
	stage.bosses_remaining = 0
	stage.in_boss_mode = false
	stage.zone_complete_pending = true
	stage.boss_appearance_rank = 9_999_999
}

pub fn (mut stage StageProgression) start_next_zone(boss_count int) {
	count := int_max(1, boss_count)
	interval := rules_for_grade(stage.grade).boss_app_rank
	stage.zone++
	stage.boss_appearance_rank = stage.zone_end_rank + interval - count
	stage.zone_end_rank += interval
	stage.bosses_remaining = count
	stage.in_boss_mode = false
	stage.zone_complete_pending = false
}
