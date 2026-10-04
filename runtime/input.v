module runtime

import sim

// Additional platform actions follow the six replay bits in sim/replay.v.
// Keep these positions aligned with TTInputAction in vulkan_bridge.h.
const input_pause_bit = u32(64)
const input_restart_bit = u32(128)
const input_back_bit = u32(256)
const input_volume_down_bit = u32(512)
const input_volume_up_bit = u32(1024)

// Volume keys must not keep gameplay/menu input latched after a transition.
const input_gameplay_and_menu_bits = sim.input_left_bit | sim.input_right_bit |
	sim.input_up_bit | sim.input_down_bit | sim.input_fire_bit | sim.input_charge_bit |
	input_pause_bit | input_restart_bit | input_back_bit

fn title_menu_input_mask(input_mask u32, title_mode bool, menu_item TitleMenuItem) u32 {
	return if title_mode && menu_item in [.settings, .help, .replays] {
		input_mask & ~sim.input_charge_bit
	} else {
		input_mask
	}
}

fn input_state(input_mask u32, reverse_buttons bool, force_brake bool) sim.InputState {
	primary := input_mask & sim.input_fire_bit != 0
	secondary := input_mask & sim.input_charge_bit != 0
	return sim.InputState{
		left:  input_mask & sim.input_left_bit != 0
		right: input_mask & sim.input_right_bit != 0
		up:    input_mask & sim.input_up_bit != 0
		down:  input_mask & sim.input_down_bit != 0
		fire:  if reverse_buttons { secondary } else { primary }
		brake: (if reverse_buttons { primary } else { secondary }) || force_brake
	}
}
