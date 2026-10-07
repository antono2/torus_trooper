// MT19937 random stream and bounded helpers used for reproducible simulation and replay behavior.
module sim

const mt_state_size = 624
const mt_period_offset = 397

// Mt19937 provides a stable random sequence for gameplay. Pattern,
// stage, particle, and replay randomness must all derive from explicit seeded
// instances so a run never depends on wall-clock or platform RNG state.
pub struct Mt19937 {
mut:
	state []u32
	index int
}

pub fn new_mt19937(seed u32) Mt19937 {
	mut rng := Mt19937{
		state: []u32{len: mt_state_size}
		index: mt_state_size
	}
	rng.state[0] = seed
	for index in 1 .. mt_state_size {
		previous := rng.state[index - 1]
		rng.state[index] = u32(u64(1812433253) * u64(previous ^ (previous >> 30)) + u64(index))
	}
	return rng
}

pub fn (mut rng Mt19937) next_u32() u32 {
	if rng.index >= mt_state_size {
		rng.twist()
	}
	mut value := rng.state[rng.index]
	rng.index++
	value ^= value >> 11
	value ^= (value << 7) & u32(0x9d2c5680)
	value ^= (value << 15) & u32(0xefc60000)
	value ^= value >> 18
	return value
}

pub fn (mut rng Mt19937) next_int(limit int) int {
	if limit <= 0 {
		return 0
	}
	return int(rng.next_u32() % u32(limit))
}

pub fn (mut rng Mt19937) next_f32(scale f32) f32 {
	return f32(f64(rng.next_u32()) * (1.0 / 4294967295.0)) * scale
}

pub fn (mut rng Mt19937) next_signed_f32(scale f32) f32 {
	return rng.next_f32(scale * 2) - scale
}

fn (mut rng Mt19937) twist() {
	for index in 0 .. mt_state_size {
		combined := (rng.state[index] & u32(0x80000000)) | (rng.state[(index + 1) % mt_state_size] & u32(0x7fffffff))
		mut value := rng.state[(index + mt_period_offset) % mt_state_size] ^ (combined >> 1)
		if combined & 1 != 0 {
			value ^= u32(0x9908b0df)
		}
		rng.state[index] = value
	}
	rng.index = 0
}
