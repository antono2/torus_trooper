module sim

pub struct Replay {
pub:
	grade                Grade
	starting_level       int = 1
	random_seed          u64
	inputs               []u8
	player_shot_distance f32 = 35
	god_mode             bool
}

pub fn encode_input(input InputState) u8 {
	mut value := u8(0)
	if input.left {
		value |= 1
	}
	if input.right {
		value |= 2
	}
	if input.up {
		value |= 4
	}
	if input.down {
		value |= 8
	}
	if input.fire {
		value |= 16
	}
	if input.brake {
		value |= 32
	}
	return value
}

pub fn decode_input(value u8) InputState {
	return InputState{
		left:  value & 1 != 0
		right: value & 2 != 0
		up:    value & 4 != 0
		down:  value & 8 != 0
		fire:  value & 16 != 0
		brake: value & 32 != 0
	}
}
