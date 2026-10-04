module sim

// Replay bytes and the platform input mask share these six logical actions.
// Their bit positions are part of the saved replay format; do not reorder them.
pub const input_left_bit = u32(1)
pub const input_right_bit = u32(2)
pub const input_up_bit = u32(4)
pub const input_down_bit = u32(8)
pub const input_fire_bit = u32(16)
pub const input_charge_bit = u32(32)

pub struct Replay {
pub:
	grade                Grade
	starting_level       int = 1
	random_seed          u64
	inputs               []u8
	player_shot_distance f32 = source_player_shot_distance
	god_mode             bool
}

pub fn encode_input(input InputState) u8 {
	mut value := u8(0)
	if input.left {
		value |= u8(input_left_bit)
	}
	if input.right {
		value |= u8(input_right_bit)
	}
	if input.up {
		value |= u8(input_up_bit)
	}
	if input.down {
		value |= u8(input_down_bit)
	}
	if input.fire {
		value |= u8(input_fire_bit)
	}
	if input.brake {
		value |= u8(input_charge_bit)
	}
	return value
}

pub fn decode_input(value u8) InputState {
	return InputState{
		left:  value & u8(input_left_bit) != 0
		right: value & u8(input_right_bit) != 0
		up:    value & u8(input_up_bit) != 0
		down:  value & u8(input_down_bit) != 0
		fire:  value & u8(input_fire_bit) != 0
		brake: value & u8(input_charge_bit) != 0
	}
}
