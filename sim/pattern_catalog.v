module sim

fn rank_value(scale f32, offset f32) ValueExpression {
	return ValueExpression{
		tokens: [
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: scale },
			ValueToken{ op: .multiply },
			ValueToken{ op: .literal, value: offset },
			ValueToken{ op: .add },
		]
	}
}

fn random_value(scale f32, offset f32) ValueExpression {
	return ValueExpression{
		tokens: [
			ValueToken{ op: .random },
			ValueToken{ op: .literal, value: scale },
			ValueToken{ op: .multiply },
			ValueToken{ op: .literal, value: offset },
			ValueToken{ op: .add },
		]
	}
}

fn parameter_value(index int) ValueExpression {
	return ValueExpression{
		tokens: [ValueToken{ op: .parameter, parameter: index }]
	}
}

pub fn native_pattern_catalog() []PatternProgram {
	return [straight_pattern(), nway_pattern(), alternating_nway_pattern(), fast_aim_pattern(),
		random_fire_pattern(), accel_pattern(), bar_pattern(), divide_pattern(),
		fire_slowshot_pattern(), slide_pattern(), wide_pattern(), zero_to_one_pattern(),
		fast_pattern(), slowdown_pattern(), speed_random_pattern(), twin_pattern(),
		wedge_half_pattern(), forward_one_way_pattern(), backward_spread_pattern(),
		clow_rocket_pattern(), accelshot_pattern(), alternating_sideshot_pattern(), grow_pattern(),
		grow_three_way_pattern(), spread_two_bullet_pattern(), squirt_pattern(),
		thirty_five_way_pattern(), diamond_nway_pattern()]
}

pub fn native_pattern_named(name string) ?PatternProgram {
	for program in native_pattern_catalog() {
		if program.name == name {
			return program
		}
	}
	return none
}

pub fn straight_pattern() PatternProgram {
	return PatternProgram{
		name: 'basic/straight'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
}

pub fn nway_pattern() PatternProgram {
	count := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 1 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 5.2 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .add },
		]
	}
	mut opposite_tokens := count.tokens.clone()
	opposite_tokens << ValueToken{ op: .literal, value: 1 }
	opposite_tokens << ValueToken{ op: .subtract }
	return PatternProgram{
		name: 'middle/nway'
		instructions: [
			PatternInstruction{ op: .fire, value: literal_expression(0) },
			PatternInstruction{ op: .repeat_begin, value: count, jump: 4 },
			PatternInstruction{
				op: .fire
				value: literal_expression(2.5)
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .fire, value: literal_expression(-2.5) },
			PatternInstruction{
				op: .repeat_begin
				value: ValueExpression{ tokens: opposite_tokens }
				jump: 8
			},
			PatternInstruction{
				op: .fire
				value: literal_expression(-2.5)
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: literal_expression(50) },
			PatternInstruction{ op: .end },
		]
	}
}

pub fn alternating_nway_pattern() PatternProgram {
	count := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 1 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 2.9 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .add },
		]
	}
	positive_step := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 7.7 },
			ValueToken{ op: .literal, value: 1 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 2.2 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .add },
			ValueToken{ op: .divide },
		]
	}
	negative_step := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 7.7 },
			ValueToken{ op: .literal, value: -1 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 2.2 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .subtract },
			ValueToken{ op: .divide },
		]
	}
	parameter_one := ValueExpression{
		tokens: [ValueToken{ op: .parameter, parameter: 1 }]
	}
	parameter_two := ValueExpression{
		tokens: [ValueToken{ op: .parameter, parameter: 2 }]
	}
	return PatternProgram{
		name: 'middle/alt_nway'
		instructions: [
			PatternInstruction{
				op: .call_action
				jump: 5
				parameters: [count, positive_step]
			},
			PatternInstruction{ op: .wait, value: literal_expression(45) },
			PatternInstruction{
				op: .call_action
				jump: 5
				parameters: [count, negative_step]
			},
			PatternInstruction{ op: .wait, value: literal_expression(45) },
			PatternInstruction{ op: .end },
			PatternInstruction{ op: .fire, value: parameter_two },
			PatternInstruction{ op: .repeat_begin, value: parameter_one, jump: 9 },
			PatternInstruction{
				op: .fire
				value: parameter_two
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .return_action },
		]
	}
}

pub fn fast_aim_pattern() PatternProgram {
	return PatternProgram{
		name: 'middle/fast_aim'
		instructions: [
			PatternInstruction{ op: .fire, value: literal_expression(0) },
			PatternInstruction{ op: .wait, value: rank_value(-10, 18) },
			PatternInstruction{ op: .end },
		]
	}
}

pub fn random_fire_pattern() PatternProgram {
	wait_value := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 200 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 16 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .literal, value: 10 },
			ValueToken{ op: .add },
			ValueToken{ op: .divide },
		]
	}
	return PatternProgram{
		name: 'middle/random_fire'
		instructions: [
			PatternInstruction{
				op: .fire
				value: random_value(9, -4.5)
				speed: random_value(0.8, 0.4)
			},
			PatternInstruction{ op: .wait, value: wait_value },
			PatternInstruction{ op: .end },
		]
	}
}

pub fn accel_pattern() PatternProgram {
	return PatternProgram{
		name: 'morph/accel'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0)
				speed_mode: .relative
			},
			PatternInstruction{ op: .repeat_begin, value: rank_value(1.8, 1), jump: 5 },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0.11)
				speed_mode: .sequence
			},
			PatternInstruction{ op: .wait, value: literal_expression(4) },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn bar_pattern() PatternProgram {
	return PatternProgram{
		name: 'morph/bar'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0)
				speed_mode: .relative
			},
			PatternInstruction{ op: .repeat_begin, value: rank_value(1.7, 0), jump: 4 },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: rank_value(0.05, 0.08)
				speed_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn divide_pattern() PatternProgram {
	return PatternProgram{
		name: 'morph/divide'
		instructions: [
			PatternInstruction{
				op: .fire
				value: rank_value(0.2, 0.2)
				direction_mode: .relative
				speed: literal_expression(-0.1)
				speed_mode: .relative
			},
			PatternInstruction{
				op: .fire
				value: rank_value(-0.2, -0.2)
				direction_mode: .relative
				speed: literal_expression(-0.1)
				speed_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
}

pub fn fire_slowshot_pattern() PatternProgram {
	direction := ValueExpression{
		tokens: [
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 0.5 },
			ValueToken{ op: .add },
			ValueToken{ op: .random },
			ValueToken{ op: .multiply },
		]
	}
	return PatternProgram{
		name: 'morph/fire_slowshot'
		instructions: [
			PatternInstruction{ op: .wait, value: literal_expression(4) },
			PatternInstruction{
				op: .fire
				value: direction
				direction_mode: .relative
				speed: literal_expression(-0.3)
				speed_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
}

pub fn slide_pattern() PatternProgram {
	return PatternProgram{
		name: 'morph/slide'
		instructions: [
			PatternInstruction{
				op: .fire
				value: rank_value(0.1, 0.1)
				direction_mode: .relative
				speed: literal_expression(-0.1)
				speed_mode: .relative
			},
			PatternInstruction{
				op: .fire
				value: rank_value(-0.1, -0.1)
				direction_mode: .relative
				speed: literal_expression(0.1)
				speed_mode: .relative
			},
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn wide_pattern() PatternProgram {
	return PatternProgram{
		name: 'morph/wide'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0)
				speed_mode: .relative
			},
			PatternInstruction{
				op: .fire
				value: rank_value(0.1, 0.1)
				direction_mode: .relative
				speed: literal_expression(0)
				speed_mode: .relative
			},
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn zero_to_one_pattern() PatternProgram {
	duration := rank_value(-50, 60)
	return PatternProgram{
		name: 'morph/0to1'
		instructions: [
			PatternInstruction{
				op: .change_speed
				value: literal_expression(0)
				term: literal_expression(1)
			},
			PatternInstruction{ op: .wait, value: literal_expression(1) },
			PatternInstruction{
				op: .change_speed
				value: literal_expression(1)
				term: duration
			},
			PatternInstruction{ op: .wait, value: duration },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
}

pub fn fast_pattern() PatternProgram {
	return PatternProgram{
		name: 'morph/fast'
		instructions: [
			PatternInstruction{
				op: .change_speed
				value: rank_value(1.5, 0)
				speed_mode: .relative
				term: literal_expression(60)
			},
			PatternInstruction{ op: .wait, value: literal_expression(60) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0)
				speed_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
}

pub fn slowdown_pattern() PatternProgram {
	duration := rank_value(5, 7)
	return PatternProgram{
		name: 'morph/slowdown'
		instructions: [
			PatternInstruction{
				op: .change_speed
				value: literal_expression(-0.7)
				speed_mode: .relative
				term: duration
			},
			PatternInstruction{ op: .wait, value: duration },
			PatternInstruction{
				op: .change_speed
				value: rank_value(0.3, 0.7)
				speed_mode: .relative
				term: literal_expression(8)
			},
			PatternInstruction{ op: .wait, value: literal_expression(8) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0)
				speed_mode: .relative
			},
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn speed_random_pattern() PatternProgram {
	target := ValueExpression{
		tokens: [
			ValueToken{ op: .random },
			ValueToken{ op: .rank },
			ValueToken{ op: .multiply },
			ValueToken{ op: .literal, value: 0.75 },
			ValueToken{ op: .add },
		]
	}
	return PatternProgram{
		name: 'morph/speed_rnd'
		instructions: [
			PatternInstruction{
				op: .change_speed
				value: target
				term: literal_expression(20)
			},
			PatternInstruction{ op: .wait, value: literal_expression(20) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0)
				speed_mode: .relative
			},
			PatternInstruction{ op: .end },
		]
	}
}

pub fn twin_pattern() PatternProgram {
	parameter := ValueExpression{
		tokens: [ValueToken{ op: .parameter, parameter: 1 }]
	}
	negative_parameter := ValueExpression{
		tokens: [
			ValueToken{ op: .parameter, parameter: 1 },
			ValueToken{ op: .negate },
		]
	}
	negative_rank := ValueExpression{
		tokens: [ValueToken{ op: .rank }, ValueToken{ op: .negate }]
	}
	return PatternProgram{
		name: 'morph/twin'
		instructions: [
			PatternInstruction{ op: .wait, value: literal_expression(1) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: ValueExpression{ tokens: [ValueToken{ op: .rank }] }
				speed_mode: .relative
				bullet_entry: 4
				bullet_parameters: [literal_expression(90)]
			},
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: ValueExpression{ tokens: [ValueToken{ op: .rank }] }
				speed_mode: .relative
				bullet_entry: 4
				bullet_parameters: [literal_expression(-90)]
			},
			PatternInstruction{ op: .vanish },
			PatternInstruction{
				op: .change_direction
				value: parameter
				direction_mode: .relative
				term: literal_expression(1)
			},
			PatternInstruction{ op: .wait, value: literal_expression(1) },
			PatternInstruction{
				op: .change_direction
				value: negative_parameter
				direction_mode: .relative
				term: literal_expression(1)
			},
			PatternInstruction{ op: .wait, value: literal_expression(1) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: negative_rank
				speed_mode: .relative
			},
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn wedge_half_pattern() PatternProgram {
	parameter_one := ValueExpression{
		tokens: [ValueToken{ op: .parameter, parameter: 1 }]
	}
	negative_parameter_one := ValueExpression{
		tokens: [
			ValueToken{ op: .parameter, parameter: 1 },
			ValueToken{ op: .negate },
		]
	}
	initial_speed := rank_value(0.4, 0.2)
	output_speed := ValueExpression{
		tokens: [
			ValueToken{ op: .parameter, parameter: 2 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 0.4 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .subtract },
			ValueToken{ op: .literal, value: 0.2 },
			ValueToken{ op: .subtract },
		]
	}
	return PatternProgram{
		name: 'morph/wedge_half'
		instructions: [
			PatternInstruction{ op: .wait, value: literal_expression(1) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: initial_speed
				speed_mode: .relative
				bullet_entry: 4
				bullet_parameters: [literal_expression(0), literal_expression(-0.08)]
			},
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: initial_speed
				speed_mode: .relative
				bullet_entry: 4
				bullet_parameters: [literal_expression(-120), literal_expression(0.08)]
			},
			PatternInstruction{ op: .vanish },
			PatternInstruction{
				op: .change_direction
				value: parameter_one
				direction_mode: .relative
				term: literal_expression(1)
			},
			PatternInstruction{ op: .wait, value: literal_expression(1) },
			PatternInstruction{
				op: .change_direction
				value: negative_parameter_one
				direction_mode: .relative
				term: literal_expression(1)
			},
			PatternInstruction{ op: .wait, value: literal_expression(1) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: output_speed
				speed_mode: .relative
			},
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn forward_one_way_pattern() PatternProgram {
	return PatternProgram{
		name: 'middle/forward_1way'
		instructions: [
			PatternInstruction{
				op: .fire
				value: random_value(-14, 7)
				speed: literal_expression(0.3)
				bullet_entry: 3
			},
			PatternInstruction{ op: .wait, value: literal_expression(72) },
			PatternInstruction{ op: .end },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
			},
			PatternInstruction{ op: .repeat_begin, value: rank_value(5.2, 2), jump: 8 },
			PatternInstruction{ op: .wait, value: rank_value(-2, 5) },
			PatternInstruction{
				op: .fire
				value: literal_expression(2)
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn backward_spread_pattern() PatternProgram {
	return PatternProgram{
		name: 'middle/backword_spread'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(180)
				speed: literal_expression(0.5)
				bullet_entry: 3
			},
			PatternInstruction{ op: .wait, value: literal_expression(48) },
			PatternInstruction{ op: .end },
			PatternInstruction{ op: .fire, value: literal_expression(-5) },
			PatternInstruction{ op: .repeat_begin, value: rank_value(4.7, 2), jump: 8 },
			PatternInstruction{ op: .wait, value: rank_value(-2, 4) },
			PatternInstruction{
				op: .fire
				value: rank_value(-0.3, 2.5)
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn clow_rocket_pattern() PatternProgram {
	negative_parameter := ValueExpression{
		tokens: [
			ValueToken{ op: .parameter, parameter: 1 },
			ValueToken{ op: .negate },
		]
	}
	return PatternProgram{
		name: 'middle/clow_rocket'
		instructions: [
			PatternInstruction{
				op: .call_action
				jump: 3
				parameters: [random_value(1, 2), random_value(-8, 4)]
			},
			PatternInstruction{ op: .wait, value: literal_expression(60) },
			PatternInstruction{ op: .end },
			PatternInstruction{
				op: .fire
				value: parameter_value(2)
				speed: literal_expression(1)
				bullet_entry: 6
				bullet_parameters: [parameter_value(1)]
			},
			PatternInstruction{
				op: .fire
				value: parameter_value(2)
				speed: literal_expression(1)
				bullet_entry: 6
				bullet_parameters: [negative_parameter]
			},
			PatternInstruction{ op: .return_action },
			PatternInstruction{
				op: .fire
				value: parameter_value(1)
				direction_mode: .relative
			},
			PatternInstruction{ op: .repeat_begin, value: rank_value(4.7, 1), jump: 11 },
			PatternInstruction{ op: .wait, value: literal_expression(3) },
			PatternInstruction{
				op: .fire
				value: parameter_value(1)
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn accelshot_pattern() PatternProgram {
	return PatternProgram{
		name: 'morph/accelshot'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(-0.9)
				speed_mode: .relative
				bullet_entry: 6
			},
			PatternInstruction{ op: .repeat_begin, value: rank_value(1.7, 0), jump: 5 },
			PatternInstruction{ op: .wait, value: literal_expression(2) },
			PatternInstruction{
				op: .fire
				value: literal_expression(0)
				direction_mode: .relative
				speed: literal_expression(0.3)
				speed_mode: .sequence
				bullet_entry: 6
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .vanish },
			PatternInstruction{ op: .wait, value: literal_expression(8) },
			PatternInstruction{
				op: .change_speed
				value: literal_expression(1)
				term: literal_expression(60)
			},
			PatternInstruction{ op: .end },
		]
	}
}

pub fn alternating_sideshot_pattern() PatternProgram {
	direction := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 3.6 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 1.2 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .subtract },
			ValueToken{ op: .parameter, parameter: 1 },
			ValueToken{ op: .multiply },
		]
	}
	initial_direction := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: -1 },
			ValueToken{ op: .parameter, parameter: 1 },
			ValueToken{ op: .multiply },
		]
	}
	return PatternProgram{
		name: 'middle/alt_sideshot'
		instructions: [
			PatternInstruction{
				op: .call_action
				jump: 5
				parameters: [
					literal_expression(1),
				]
			},
			PatternInstruction{ op: .wait, value: literal_expression(45) },
			PatternInstruction{
				op: .call_action
				jump: 5
				parameters: [
					literal_expression(-1),
				]
			},
			PatternInstruction{ op: .wait, value: literal_expression(45) },
			PatternInstruction{ op: .end },
			PatternInstruction{
				op: .fire
				value: initial_direction
				speed: literal_expression(1)
			},
			PatternInstruction{ op: .repeat_begin, value: rank_value(5.2, 2), jump: 10 },
			PatternInstruction{
				op: .fire
				value: direction
				direction_mode: .sequence
				speed: literal_expression(-0.06)
				speed_mode: .sequence
			},
			PatternInstruction{ op: .wait, value: literal_expression(2) },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .return_action },
		]
	}
}

pub fn grow_pattern() PatternProgram {
	return PatternProgram{
		name: 'middle/grow'
		instructions: [
			PatternInstruction{
				op: .fire
				value: random_value(-6, 3)
				speed: literal_expression(0.4)
			},
			PatternInstruction{
				op: .call_action
				jump: 4
				parameters: [random_value(-1, 0.5)]
			},
			PatternInstruction{ op: .wait, value: literal_expression(60) },
			PatternInstruction{ op: .end },
			PatternInstruction{ op: .repeat_begin, value: rank_value(12.6, 3), jump: 8 },
			PatternInstruction{
				op: .fire
				value: parameter_value(1)
				direction_mode: .sequence
				speed: literal_expression(0.05)
				speed_mode: .sequence
			},
			PatternInstruction{ op: .wait, value: literal_expression(5) },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .return_action },
		]
	}
}

pub fn grow_three_way_pattern() PatternProgram {
	return PatternProgram{
		name: 'middle/grow3way'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(-3)
				speed: literal_expression(0.5)
			},
			PatternInstruction{ op: .repeat_begin, value: literal_expression(2), jump: 4 },
			PatternInstruction{
				op: .fire
				value: literal_expression(3)
				direction_mode: .sequence
				speed: literal_expression(0)
				speed_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: literal_expression(4) },
			PatternInstruction{ op: .repeat_begin, value: rank_value(6.9, 1), jump: 12 },
			PatternInstruction{
				op: .fire
				value: literal_expression(-3)
				speed: literal_expression(0.2)
				speed_mode: .sequence
			},
			PatternInstruction{ op: .repeat_begin, value: literal_expression(2), jump: 10 },
			PatternInstruction{
				op: .fire
				value: literal_expression(3)
				direction_mode: .sequence
				speed: literal_expression(0)
				speed_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: literal_expression(4) },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: literal_expression(90) },
			PatternInstruction{ op: .end },
		]
	}
}

pub fn spread_two_bullet_pattern() PatternProgram {
	return PatternProgram{
		name: 'middle/spread2blt'
		instructions: [
			PatternInstruction{
				op: .fire
				value: literal_expression(120)
				direction_mode: .absolute
				speed: literal_expression(1)
				bullet_entry: 5
			},
			PatternInstruction{ op: .wait, value: literal_expression(50) },
			PatternInstruction{
				op: .fire
				value: literal_expression(240)
				direction_mode: .absolute
				speed: literal_expression(1)
				bullet_entry: 5
			},
			PatternInstruction{ op: .wait, value: literal_expression(50) },
			PatternInstruction{ op: .end },
			PatternInstruction{
				op: .change_speed
				value: literal_expression(0.2)
				term: literal_expression(40)
			},
			PatternInstruction{ op: .wait, value: literal_expression(20) },
			PatternInstruction{ op: .repeat_begin, value: rank_value(7.2, 2), jump: 10 },
			PatternInstruction{
				op: .fire
				value: random_value(20, 170)
				direction_mode: .absolute
				speed: random_value(0.5, 0.7)
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .vanish },
		]
	}
}

pub fn squirt_pattern() PatternProgram {
	count := rank_value(7.5, 4)
	wait_value := rank_value(-9.5, 20)
	positive_step := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 12 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 7.5 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .literal, value: 4 },
			ValueToken{ op: .add },
			ValueToken{ op: .divide },
		]
	}
	negative_step := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 12 },
			ValueToken{ op: .literal, value: -4 },
			ValueToken{ op: .rank },
			ValueToken{ op: .literal, value: 7.5 },
			ValueToken{ op: .multiply },
			ValueToken{ op: .subtract },
			ValueToken{ op: .divide },
		]
	}
	return PatternProgram{
		name: 'middle/squirt'
		instructions: [
			PatternInstruction{
				op: .call_action
				jump: 2
				parameters: [count, positive_step, negative_step]
			},
			PatternInstruction{ op: .end },
			PatternInstruction{
				op: .fire
				value: literal_expression(174)
				direction_mode: .absolute
			},
			PatternInstruction{ op: .repeat_begin, value: literal_expression(99), jump: 13 },
			PatternInstruction{ op: .repeat_begin, value: parameter_value(1), jump: 8 },
			PatternInstruction{ op: .wait, value: wait_value },
			PatternInstruction{
				op: .fire
				value: parameter_value(2)
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .repeat_begin, value: parameter_value(1), jump: 12 },
			PatternInstruction{ op: .wait, value: wait_value },
			PatternInstruction{
				op: .fire
				value: parameter_value(3)
				direction_mode: .sequence
			},
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .return_action },
		]
	}
}

pub fn thirty_five_way_pattern() PatternProgram {
	return PatternProgram{
		name: 'middle/35way'
		entry_points: [0, 6]
		instructions: [
			PatternInstruction{ op: .fire, value: literal_expression(-5), speed: literal_expression(0.7) },
			PatternInstruction{ op: .repeat_begin, value: literal_expression(2), jump: 4 },
			PatternInstruction{ op: .fire, value: literal_expression(5), direction_mode: .sequence, speed: literal_expression(0.7) },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: rank_value(-32, 72) },
			PatternInstruction{ op: .end },
			PatternInstruction{ op: .wait, value: rank_value(-8, 26) },
			PatternInstruction{ op: .fire, value: literal_expression(-8), speed: literal_expression(1) },
			PatternInstruction{ op: .repeat_begin, value: literal_expression(4), jump: 11 },
			PatternInstruction{ op: .fire, value: literal_expression(4), direction_mode: .sequence, speed: literal_expression(1) },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: rank_value(-24, 46) },
			PatternInstruction{ op: .end },
		]
	}
}

pub fn diamond_nway_pattern() PatternProgram {
	negative_step := rank_value(1, -3.5)
	positive_step := ValueExpression{
		tokens: [
			ValueToken{ op: .literal, value: 3.5 },
			ValueToken{ op: .rank },
			ValueToken{ op: .subtract },
		]
	}
	return PatternProgram{
		name: 'middle/diamondnway'
		entry_points: [0, 7]
		instructions: [
			PatternInstruction{ op: .fire, value: literal_expression(0) },
			PatternInstruction{ op: .repeat_begin, value: rank_value(4.2, 1), jump: 5 },
			PatternInstruction{ op: .wait, value: literal_expression(4) },
			PatternInstruction{ op: .fire, value: negative_step, direction_mode: .sequence },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: literal_expression(60) },
			PatternInstruction{ op: .end },
			PatternInstruction{ op: .fire, value: literal_expression(0) },
			PatternInstruction{ op: .repeat_begin, value: rank_value(4.2, 1), jump: 12 },
			PatternInstruction{ op: .wait, value: literal_expression(4) },
			PatternInstruction{ op: .fire, value: positive_step, direction_mode: .sequence },
			PatternInstruction{ op: .repeat_end },
			PatternInstruction{ op: .wait, value: literal_expression(60) },
			PatternInstruction{ op: .end },
		]
	}
}
