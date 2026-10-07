// Interprets native bullet-pattern programs and ranked or seeded value expressions.
module sim

import math

pub enum ValueOp {
	literal
	rank
	random
	parameter
	add
	subtract
	multiply
	divide
	negate
}

pub struct ValueToken {
pub:
	op        ValueOp
	value     f32
	parameter int
}

// ValueExpression is a compact postfix expression. It supports every value
// source and arithmetic operator needed by native barrage programs while
// remaining deterministic and straightforward to flatten for OpenCL later.
pub struct ValueExpression {
pub:
	tokens []ValueToken
}

pub fn literal_expression(value f32) ValueExpression {
	return ValueExpression{ tokens: [ValueToken{ op: .literal, value: value }] }
}

pub fn (expression ValueExpression) evaluate(rank f32, parameters []f32, mut rng Mt19937) !f32 {
	if expression.tokens.len == 0 {
		return error('empty pattern expression')
	}
	mut stack := []f32{cap: expression.tokens.len}
	for token in expression.tokens {
		match token.op {
			.literal { stack << token.value }
			.rank { stack << rank }
			.random { stack << rng.next_f32(1) }
			.parameter {
				index := token.parameter - 1
				if index < 0 || index >= parameters.len {
					return error('pattern parameter ${token.parameter} is unavailable')
				}
				stack << parameters[index]
			}
			.negate {
				if stack.len < 1 {
					return error('pattern expression stack underflow')
				}
				stack[stack.len - 1] = -stack[stack.len - 1]
			}
			.add, .subtract, .multiply, .divide {
				if stack.len < 2 {
					return error('pattern expression stack underflow')
				}
				right := stack.pop()
				left := stack.pop()
				value := match token.op {
					.add { left + right }
					.subtract { left - right }
					.multiply { left * right }
					.divide {
						if right == 0 {
							return error('division by zero in pattern expression')
						}
						left / right
					}
					else { f32(0) }
				}
				stack << value
			}
		}
	}
	if stack.len != 1 {
		return error('pattern expression left ${stack.len} values')
	}
	return stack[0]
}

pub enum PatternOp {
	fire
	wait
	repeat_begin
	repeat_end
	call_action
	return_action
	change_speed
	change_direction
	vanish
	end
}

pub enum DirectionMode {
	aim
	absolute
	relative
	sequence
}

pub enum SpeedMode {
	absolute
	relative
	sequence
}

pub struct PatternInstruction {
pub:
	op                PatternOp
	value             ValueExpression
	direction_mode    DirectionMode
	speed             ValueExpression
	speed_mode        SpeedMode
	term              ValueExpression
	parameters        []ValueExpression
	bullet_entry      int = -1
	bullet_parameters []ValueExpression
	// repeat_begin jumps here when its count is zero; repeat_end jumps to the
	// first instruction in the body while iterations remain.
	jump int = -1
}

pub struct PatternProgram {
pub:
	name         string
	instructions []PatternInstruction
	// Most barrages have one top action at instruction zero. A small number of
	// patterns expose several top actions which execute concurrently.
	entry_points []int
}

pub struct PatternContext {
pub:
	rank           f32
	parameters     []f32
	aim_direction  f32
	base_direction f32
	base_speed     f32
	default_speed  f32
	speed_scale    f32 = 1
}

pub struct PatternShot {
pub:
	direction    f32
	speed        f32
	action_entry int = -1
	parameters   []f32
}

pub struct PatternPipeline {
pub:
	programs      []PatternProgram
	ranks         []f32
	x_reverse     f32 = 1
	visual_shape  int
	visual_scale  f32 = 1
	long_range    bool
	speed_rank    f32 = 1
	default_speed f32
	speed_scale   f32 = 1
}

struct PatternRepeat {
mut:
	remaining int
	body      int
}

struct PatternCall {
	return_instruction int
	parameters         []f32
}

pub struct PatternRunner {
	program PatternProgram
	context PatternContext
pub mut:
	instruction   int
	wait_ticks    int
	alive         bool = true
	vanished      bool
	direction     f32
	speed         f32
	aim_direction f32
mut:
	repeats               []PatternRepeat
	calls                 []PatternCall
	parameters            []f32
	last_fire_direction   f32
	last_fire_speed       f32
	last_direction_target f32
	last_speed_target     f32
	direction_target      f32
	direction_delta       f32
	direction_ticks       int
	speed_target          f32
	speed_delta           f32
	speed_ticks           int
}

fn pattern_default_speed(context PatternContext) f32 {
	return if context.default_speed > 0 { context.default_speed } else { context.base_speed }
}

pub fn new_pattern_runner(program PatternProgram, context PatternContext) PatternRunner {
	return PatternRunner{
		program: program
		context: context
		parameters: context.parameters.clone()
		direction: context.base_direction
		speed: context.base_speed
		aim_direction: context.aim_direction
		last_fire_direction: context.base_direction
		last_fire_speed: pattern_default_speed(context)
		last_direction_target: context.base_direction
		last_speed_target: context.base_speed
	}
}

pub fn new_pattern_runner_at(program PatternProgram, context PatternContext, instruction int) !PatternRunner {
	if instruction < 0 || instruction >= program.instructions.len {
		return error('pattern ${program.name} child action target is out of range')
	}
	mut runner := new_pattern_runner(program, context)
	runner.instruction = instruction
	return runner
}

pub fn (mut runner PatternRunner) rewind() {
	runner.rewind_at(0)
}

pub fn (mut runner PatternRunner) rewind_at(instruction int) {
	runner.instruction = instruction
	runner.wait_ticks = 0
	runner.alive = true
	runner.vanished = false
	runner.repeats.clear()
	runner.calls.clear()
	runner.parameters = runner.context.parameters.clone()
	runner.direction = runner.context.base_direction
	runner.speed = runner.context.base_speed
	runner.aim_direction = runner.context.aim_direction
	runner.last_fire_direction = runner.context.base_direction
	runner.last_fire_speed = pattern_default_speed(runner.context)
	runner.last_direction_target = runner.context.base_direction
	runner.last_speed_target = runner.context.base_speed
	runner.direction_ticks = 0
	runner.speed_ticks = 0
}

pub fn (mut runner PatternRunner) sync_owner(direction f32, speed f32, aim_direction f32) {
	runner.direction = direction
	runner.speed = speed
	runner.aim_direction = aim_direction
}

pub fn (runner &PatternRunner) has_pending_transitions() bool {
	return runner.speed_ticks > 0 || runner.direction_ticks > 0
}

pub struct LoopingPatternRunner {
pub mut:
	runner     PatternRunner
	wait_ticks int
pub:
	post_wait         int
	entry_instruction int
}

pub fn new_looping_pattern_runner(program PatternProgram, context PatternContext, pre_wait int, post_wait int) LoopingPatternRunner {
	return LoopingPatternRunner{
		runner: new_pattern_runner(program, context)
		wait_ticks: int_max(0, pre_wait)
		post_wait: int_max(0, post_wait)
		entry_instruction: 0
	}
}

pub fn new_looping_pattern_runner_at(program PatternProgram, context PatternContext, instruction int, pre_wait int, post_wait int) !LoopingPatternRunner {
	runner := new_pattern_runner_at(program, context, instruction)!
	return LoopingPatternRunner{
		runner: runner
		wait_ticks: int_max(0, pre_wait)
		post_wait: int_max(0, post_wait)
		entry_instruction: instruction
	}
}

pub fn (mut looping LoopingPatternRunner) tick(mut rng Mt19937) ![]PatternShot {
	if looping.wait_ticks > 0 {
		looping.wait_ticks--
		return []PatternShot{}
	}
	shots := looping.runner.tick(mut rng)!
	if !looping.runner.alive {
		looping.runner.rewind_at(looping.entry_instruction)
		looping.wait_ticks = looping.post_wait
	}
	return shots
}

pub struct ParallelPatternRunner {
pub mut:
	runners []LoopingPatternRunner
}

pub fn new_parallel_pattern_runner(program PatternProgram, context PatternContext, pre_wait int, post_wait int) !ParallelPatternRunner {
	entries := if program.entry_points.len > 0 { program.entry_points } else { [0] }
	mut runners := []LoopingPatternRunner{cap: entries.len}
	for entry in entries {
		runners << new_looping_pattern_runner_at(program, context, entry, pre_wait, post_wait)!
	}
	return ParallelPatternRunner{ runners: runners }
}

pub fn (mut parallel ParallelPatternRunner) tick(mut rng Mt19937) ![]PatternShot {
	mut shots := []PatternShot{}
	for mut runner in parallel.runners {
		shots << runner.tick(mut rng)!
	}
	return shots
}

pub fn (mut runner PatternRunner) tick(mut rng Mt19937) ![]PatternShot {
	mut shots := []PatternShot{}
	runner.apply_transitions()
	if !runner.alive {
		return shots
	}
	if runner.wait_ticks > 0 {
		runner.wait_ticks--
		return shots
	}
	for operations := 0; operations < 1024; operations++ {
		if runner.instruction < 0 || runner.instruction >= runner.program.instructions.len {
			return error('pattern ${runner.program.name} instruction pointer is out of range')
		}
		instruction := runner.program.instructions[runner.instruction]
		match instruction.op {
			.fire {
				direction_value := instruction.value.evaluate(runner.context.rank, runner.parameters, mut rng)!
				direction_offset := direction_value * f32(math.pi / 180.0)
				direction := match instruction.direction_mode {
					.aim { runner.aim_direction + direction_offset }
					.absolute { direction_offset }
					.relative { runner.direction + direction_offset }
					.sequence { runner.last_fire_direction + direction_offset }
				}
				mut speed := pattern_default_speed(runner.context)
				if instruction.speed.tokens.len > 0 {
					speed_value := instruction.speed.evaluate(runner.context.rank, runner.parameters, mut rng)! * runner.context.speed_scale
					speed = match instruction.speed_mode {
						.absolute { speed_value }
						.relative { runner.speed + speed_value }
						.sequence { runner.last_fire_speed + speed_value }
					}
				}
				runner.last_fire_direction = direction
				runner.last_fire_speed = speed
				mut child_parameters := []f32{cap: instruction.bullet_parameters.len}
				for expression in instruction.bullet_parameters {
					child_parameters << expression.evaluate(runner.context.rank, runner.parameters, mut rng)!
				}
				shots << PatternShot{
					direction: direction
					speed: speed
					action_entry: instruction.bullet_entry
					parameters: child_parameters
				}
				runner.instruction++
			}
			.wait {
				value := instruction.value.evaluate(runner.context.rank, runner.parameters, mut rng)!
				runner.wait_ticks = int(value)
				if runner.wait_ticks < 0 {
					runner.wait_ticks = 0
				}
				runner.instruction++
				return shots
			}
			.repeat_begin {
				value := instruction.value.evaluate(runner.context.rank, runner.parameters, mut rng)!
				count := int(value)
				if count <= 0 {
					runner.instruction = instruction.jump
				} else {
					runner.repeats << PatternRepeat{
						remaining: count
						body: runner.instruction + 1
					}
					runner.instruction++
				}
			}
			.repeat_end {
				if runner.repeats.len == 0 {
					return error('pattern ${runner.program.name} repeat stack underflow')
				}
				last := runner.repeats.len - 1
				runner.repeats[last].remaining--
				if runner.repeats[last].remaining > 0 {
					runner.instruction = runner.repeats[last].body
				} else {
					runner.repeats.pop()
					runner.instruction++
				}
			}
			.call_action {
				if instruction.jump < 0 || instruction.jump >= runner.program.instructions.len {
					return error('pattern ${runner.program.name} action target is out of range')
				}
				mut call_arguments := []f32{cap: instruction.parameters.len}
				for expression in instruction.parameters {
					call_arguments << expression.evaluate(runner.context.rank, runner.parameters, mut rng)!
				}
				runner.calls << PatternCall{
					return_instruction: runner.instruction + 1
					parameters: runner.parameters.clone()
				}
				runner.parameters = call_arguments
				runner.instruction = instruction.jump
			}
			.return_action {
				if runner.calls.len == 0 {
					return error('pattern ${runner.program.name} action stack underflow')
				}
				frame := runner.calls.pop()
				runner.parameters = frame.parameters
				runner.instruction = frame.return_instruction
			}
			.change_speed {
				value := instruction.value.evaluate(runner.context.rank, runner.parameters, mut rng)! * runner.context.speed_scale
				target := match instruction.speed_mode {
					.absolute { value }
					.relative { runner.speed + value }
					.sequence { runner.last_speed_target + value }
				}
				duration := int(instruction.term.evaluate(runner.context.rank, runner.parameters, mut rng)!)
				runner.start_speed_transition(target, duration)
				runner.instruction++
			}
			.change_direction {
				value := instruction.value.evaluate(runner.context.rank, runner.parameters, mut rng)!
				offset := value * f32(math.pi / 180.0)
				target := match instruction.direction_mode {
					.aim { runner.aim_direction + offset }
					.absolute { offset }
					.relative { runner.direction + offset }
					.sequence { runner.last_direction_target + offset }
				}
				duration := int(instruction.term.evaluate(runner.context.rank, runner.parameters, mut rng)!)
				runner.start_direction_transition(target, duration)
				runner.instruction++
			}
			.vanish {
				runner.vanished = true
				runner.alive = false
				return shots
			}
			.end {
				runner.alive = false
				return shots
			}
		}
	}
	return error('pattern ${runner.program.name} exceeded the per-tick operation limit')
}

fn (mut runner PatternRunner) start_speed_transition(target f32, duration int) {
	runner.last_speed_target = target
	if duration <= 0 {
		runner.speed = target
		runner.speed_ticks = 0
		return
	}
	runner.speed_target = target
	runner.speed_delta = (target - runner.speed) / f32(duration)
	runner.speed_ticks = duration
}

fn (mut runner PatternRunner) start_direction_transition(target f32, duration int) {
	runner.last_direction_target = target
	if duration <= 0 {
		runner.direction = target
		runner.direction_ticks = 0
		return
	}
	runner.direction_target = target
	runner.direction_delta = (target - runner.direction) / f32(duration)
	runner.direction_ticks = duration
}

fn (mut runner PatternRunner) apply_transitions() {
	if runner.speed_ticks > 0 {
		runner.speed += runner.speed_delta
		runner.speed_ticks--
		if runner.speed_ticks == 0 {
			runner.speed = runner.speed_target
		}
	}
	if runner.direction_ticks > 0 {
		runner.direction += runner.direction_delta
		runner.direction_ticks--
		if runner.direction_ticks == 0 {
			runner.direction = runner.direction_target
		}
	}
}
