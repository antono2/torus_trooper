module sim

$if opencl_compute ? {
	import antono2.opencl as cl
}

$if opencl_compute ? {
	const opencl_motion_source = '
typedef struct {
    int active;
    float angle;
    float depth;
    float velocity_x;
    float velocity_y;
    int life;
} ParticleSlot;

typedef struct {
    float angle;
    float depth;
    float velocity_x;
    float velocity_y;
    int life;
} ParticleMotion;

typedef struct {
    float angle;
    float depth;
    float direction;
    float speed;
    float x_reverse;
    float speed_rank;
    float movement_scale;
    int age;
} BulletMotion;

typedef struct {
    int active;
    float angle;
    float depth;
    float direction;
    float speed;
    float x_reverse;
    float speed_rank;
    float movement_scale;
    int age;
} BulletSlot;

typedef struct {
    float angle;
    float depth;
    float direction;
    float range;
    int age;
} ShotMotion;

typedef struct {
    int active;
    float angle;
    float depth;
    float direction;
    float range;
    int age;
} ShotSlot;

typedef struct {
    float angle;
    float depth;
    float angle_step;
    float depth_step;
    int age;
} EnemyMotion;

typedef struct {
    int active;
    float angle;
    float depth;
    float angle_step;
    float depth_step;
    int age;
} EnemySlot;

typedef struct {
    int active;
    int source_index;
    float angle;
    float depth;
} CollisionPoint;

typedef struct {
    int shot_index;
    int target_index;
} ShotCollisionCandidate;

inline float tt_wrap_angle(float value) {
    const float tau = 6.28318530717958647692f;
    while (value < 0.0f) {
        value += tau;
    }
    while (value >= tau) {
        value -= tau;
    }
    return value;
}

inline float tt_angle_delta(float from, float to) {
    const float pi = 3.14159265358979323846f;
    const float tau = 6.28318530717958647692f;
    float delta = to - from;
    while (delta > pi) {
        delta -= tau;
    }
    while (delta < -pi) {
        delta += tau;
    }
    return delta;
}

kernel void mark_particle_slots(global const ParticleSlot *slots,
                                global int *active_flags) {
    const size_t index = get_global_id(0);
    active_flags[index] = slots[index].active ? 1 : 0;
}

kernel void scan_active_flags(global const int *input,
                              global int *output, int offset) {
    const size_t index = get_global_id(0);
    int value = input[index];
    if (index >= (size_t)offset) {
        value += input[index - (size_t)offset];
    }
    output[index] = value;
}

kernel void mark_collision_points(global const CollisionPoint *points,
                                  global int *active_flags) {
    const size_t index = get_global_id(0);
    active_flags[index] = points[index].active ? 1 : 0;
}

kernel void scatter_collision_points(global const CollisionPoint *points,
                                     global const int *inclusive_scan,
                                     global CollisionPoint *active_points) {
    const size_t source_index = get_global_id(0);
    CollisionPoint point = points[source_index];
    if (point.active) {
        const int write_index = inclusive_scan[source_index] - 1;
        active_points[write_index] = point;
    }
}

kernel void mark_collision_candidates(global const CollisionPoint *shots,
                                      global const CollisionPoint *targets,
                                      int target_count,
                                      float depth_limit,
                                      float angle_limit,
                                      global int *active_flags) {
    const size_t pair_index = get_global_id(0);
    const size_t shot_index = pair_index / (size_t)target_count;
    const size_t target_index = pair_index % (size_t)target_count;
    CollisionPoint shot = shots[shot_index];
    CollisionPoint target = targets[target_index];
    active_flags[pair_index] = fabs(target.depth - shot.depth) < depth_limit
        && fabs(tt_angle_delta(target.angle, shot.angle)) < angle_limit;
}

kernel void scatter_collision_candidates(global const CollisionPoint *shots,
                                         global const CollisionPoint *targets,
                                         int target_count,
                                         float depth_limit,
                                         float angle_limit,
                                         global const int *inclusive_scan,
                                         global ShotCollisionCandidate *candidates) {
    const size_t pair_index = get_global_id(0);
    const size_t shot_index = pair_index / (size_t)target_count;
    const size_t target_index = pair_index % (size_t)target_count;
    CollisionPoint shot = shots[shot_index];
    CollisionPoint target = targets[target_index];
    if (fabs(target.depth - shot.depth) < depth_limit
        && fabs(tt_angle_delta(target.angle, shot.angle)) < angle_limit) {
        const int write_index = inclusive_scan[pair_index] - 1;
        ShotCollisionCandidate candidate;
        candidate.shot_index = shot.source_index;
        candidate.target_index = target.source_index;
        candidates[write_index] = candidate;
    }
}

kernel void mark_bullet_slots(global const BulletSlot *slots,
                              global int *active_flags) {
    const size_t index = get_global_id(0);
    active_flags[index] = slots[index].active ? 1 : 0;
}

kernel void scatter_bullets(global const BulletSlot *slots,
                            global const int *inclusive_scan,
                            global BulletMotion *items,
                            global int *source_indices) {
    const size_t source_index = get_global_id(0);
    BulletSlot slot = slots[source_index];
    if (slot.active) {
        const int write_index = inclusive_scan[source_index] - 1;
        BulletMotion item;
        item.angle = slot.angle;
        item.depth = slot.depth;
        item.direction = slot.direction;
        item.speed = slot.speed;
        item.x_reverse = slot.x_reverse;
        item.speed_rank = slot.speed_rank;
        item.movement_scale = slot.movement_scale;
        item.age = slot.age;
        items[write_index] = item;
        source_indices[write_index] = (int)source_index;
    }
}

kernel void mark_shot_slots(global const ShotSlot *slots,
                            global int *active_flags) {
    const size_t index = get_global_id(0);
    active_flags[index] = slots[index].active ? 1 : 0;
}

kernel void scatter_shots(global const ShotSlot *slots,
                          global const int *inclusive_scan,
                          global ShotMotion *items,
                          global int *source_indices) {
    const size_t source_index = get_global_id(0);
    ShotSlot slot = slots[source_index];
    if (slot.active) {
        const int write_index = inclusive_scan[source_index] - 1;
        ShotMotion item;
        item.angle = slot.angle;
        item.depth = slot.depth;
        item.direction = slot.direction;
        item.range = slot.range;
        item.age = slot.age;
        items[write_index] = item;
        source_indices[write_index] = (int)source_index;
    }
}

kernel void mark_enemy_slots(global const EnemySlot *slots,
                             global int *active_flags) {
    const size_t index = get_global_id(0);
    active_flags[index] = slots[index].active ? 1 : 0;
}

kernel void scatter_enemies(global const EnemySlot *slots,
                            global const int *inclusive_scan,
                            global EnemyMotion *items,
                            global int *source_indices) {
    const size_t source_index = get_global_id(0);
    EnemySlot slot = slots[source_index];
    if (slot.active) {
        const int write_index = inclusive_scan[source_index] - 1;
        EnemyMotion item;
        item.angle = slot.angle;
        item.depth = slot.depth;
        item.angle_step = slot.angle_step;
        item.depth_step = slot.depth_step;
        item.age = slot.age;
        items[write_index] = item;
        source_indices[write_index] = (int)source_index;
    }
}

kernel void scatter_particles(global const ParticleSlot *slots,
                              global const int *inclusive_scan,
                              global ParticleMotion *items,
                              global int *source_indices) {
    const size_t source_index = get_global_id(0);
    ParticleSlot slot = slots[source_index];
    if (slot.active) {
        const int write_index = inclusive_scan[source_index] - 1;
        ParticleMotion item;
        item.angle = slot.angle;
        item.depth = slot.depth;
        item.velocity_x = slot.velocity_x;
        item.velocity_y = slot.velocity_y;
        item.life = slot.life;
        items[write_index] = item;
        source_indices[write_index] = (int)source_index;
    }
}

kernel void step_particles(global ParticleMotion *items) {
    const size_t index = get_global_id(0);
    ParticleMotion item = items[index];
    item.angle = tt_wrap_angle(item.angle + item.velocity_x);
    item.depth += item.velocity_y;
    item.life--;
    items[index] = item;
}

kernel void step_bullets(global BulletMotion *items) {
    const size_t index = get_global_id(0);
    BulletMotion item = items[index];
    const float movement_x = sin(item.direction) * item.speed * item.speed_rank * item.x_reverse;
    const float movement_y = cos(item.direction) * item.speed * item.speed_rank;
    const float direction = atan2(movement_x, movement_y);
    const float ratio = (1.0f - fabs(sin(direction)) * 0.999f) * item.movement_scale;
    item.angle = tt_wrap_angle(item.angle + movement_x * ratio);
    item.depth += movement_y * ratio;
    item.age++;
    items[index] = item;
}

kernel void step_shots(global ShotMotion *items) {
    const size_t index = get_global_id(0);
    ShotMotion item = items[index];
    item.angle = tt_wrap_angle(item.angle + sin(item.direction) * 0.75f);
    item.depth += cos(item.direction) * 0.75f;
    item.range -= 0.75f;
    item.age++;
    items[index] = item;
}

kernel void step_enemies(global EnemyMotion *items) {
    const size_t index = get_global_id(0);
    EnemyMotion item = items[index];
    item.angle = tt_wrap_angle(item.angle + item.angle_step);
    item.depth += item.depth_step;
    items[index] = item;
}
'

	struct OpenCLParticleSlot {
		active     i32
		angle      f32
		depth      f32
		velocity_x f32
		velocity_y f32
		life       i32
	}

	struct OpenCLParticleMotion {
	mut:
		angle      f32
		depth      f32
		velocity_x f32
		velocity_y f32
		life       i32
	}

	struct OpenCLBulletSlot {
		active         i32
		angle          f32
		depth          f32
		direction      f32
		speed          f32
		x_reverse      f32
		speed_rank     f32
		movement_scale f32
		age            i32
	}

	struct OpenCLBulletMotion {
	mut:
		angle          f32
		depth          f32
		direction      f32
		speed          f32
		x_reverse      f32
		speed_rank     f32
		movement_scale f32
		age            i32
	}

	struct OpenCLShotSlot {
		active    i32
		angle     f32
		depth     f32
		direction f32
		range     f32
		age       i32
	}

	struct OpenCLShotMotion {
	mut:
		angle     f32
		depth     f32
		direction f32
		range     f32
		age       i32
	}

	struct OpenCLEnemySlot {
		active     i32
		angle      f32
		depth      f32
		angle_step f32
		depth_step f32
		age        i32
	}

	struct OpenCLEnemyMotion {
	mut:
		angle      f32
		depth      f32
		angle_step f32
		depth_step f32
		age        i32
	}

	struct OpenCLCollisionPoint {
		active       i32
		source_index i32
		angle        f32
		depth        f32
	}

	struct OpenCLShotCollisionCandidate {
		shot_index   i32
		target_index i32
	}

	@[heap]
	struct OpenCLCompute {
	mut:
		context                        cl.OwnedContext
		queue                          cl.OwnedCommandQueue
		program                        cl.OwnedProgram
		particle_mark_kernel           cl.OwnedKernel
		particle_scatter_kernel        cl.OwnedKernel
		bullet_mark_kernel             cl.OwnedKernel
		bullet_scatter_kernel          cl.OwnedKernel
		shot_mark_kernel               cl.OwnedKernel
		shot_scatter_kernel            cl.OwnedKernel
		enemy_mark_kernel              cl.OwnedKernel
		enemy_scatter_kernel           cl.OwnedKernel
		collision_mark_kernel          cl.OwnedKernel
		collision_scatter_kernel       cl.OwnedKernel
		collision_point_mark_kernel    cl.OwnedKernel
		collision_point_scatter_kernel cl.OwnedKernel
		scan_kernel                    cl.OwnedKernel
		particle_kernel                cl.OwnedKernel
		bullet_kernel                  cl.OwnedKernel
		shot_kernel                    cl.OwnedKernel
		enemy_kernel                   cl.OwnedKernel
		particle_slots                 &cl.Buffer[OpenCLParticleSlot]
		active_flags_a                 &cl.Buffer[i32]
		active_flags_b                 &cl.Buffer[i32]
		particle_buffer                &cl.Buffer[OpenCLParticleMotion]
		particle_indices               &cl.Buffer[i32]
		bullet_slots                   &cl.Buffer[OpenCLBulletSlot]
		bullet_buffer                  &cl.Buffer[OpenCLBulletMotion]
		bullet_indices                 &cl.Buffer[i32]
		shot_slots                     &cl.Buffer[OpenCLShotSlot]
		shot_buffer                    &cl.Buffer[OpenCLShotMotion]
		shot_indices                   &cl.Buffer[i32]
		enemy_slots                    &cl.Buffer[OpenCLEnemySlot]
		enemy_buffer                   &cl.Buffer[OpenCLEnemyMotion]
		enemy_indices                  &cl.Buffer[i32]
		collision_shot_slots           &cl.Buffer[OpenCLCollisionPoint]
		collision_shots                &cl.Buffer[OpenCLCollisionPoint]
		collision_target_slots         &cl.Buffer[OpenCLCollisionPoint]
		collision_targets              &cl.Buffer[OpenCLCollisionPoint]
		collision_candidate_buffer     &cl.Buffer[OpenCLShotCollisionCandidate]
		device_name                    string
	}

	fn select_opencl_device() !(cl.DeviceId, string) {
		platforms := cl.platforms()!
		for device_kind in [cl.device_type_gpu, cl.device_type_all] {
			for platform in platforms {
				devices := cl.devices(platform, device_kind)!
				if devices.len > 0 {
					name := cl.device_info_string(devices[0], cl.device_name)!
					return devices[0], name
				}
			}
		}
		return error('no OpenCL devices are available')
	}

	fn new_opencl_compute() !&OpenCLCompute {
		device, device_name := select_opencl_device()!
		mut compute := &OpenCLCompute{
			device_name:                device_name
			particle_slots:             unsafe { nil }
			active_flags_a:             unsafe { nil }
			active_flags_b:             unsafe { nil }
			particle_buffer:            unsafe { nil }
			particle_indices:           unsafe { nil }
			bullet_slots:               unsafe { nil }
			bullet_buffer:              unsafe { nil }
			bullet_indices:             unsafe { nil }
			shot_slots:                 unsafe { nil }
			shot_buffer:                unsafe { nil }
			shot_indices:               unsafe { nil }
			enemy_slots:                unsafe { nil }
			enemy_buffer:               unsafe { nil }
			enemy_indices:              unsafe { nil }
			collision_shot_slots:       unsafe { nil }
			collision_shots:            unsafe { nil }
			collision_target_slots:     unsafe { nil }
			collision_targets:          unsafe { nil }
			collision_candidate_buffer: unsafe { nil }
		}
		compute.context = cl.new_context(device) or {
			compute.close()
			return err
		}
		compute.queue = compute.context.command_queue(device, 0) or {
			compute.close()
			return err
		}
		compute.program = cl.build_source_program(&compute.context, device, opencl_motion_source, '') or {
			compute.close()
			return err
		}
		compute.particle_mark_kernel = compute.program.kernel('mark_particle_slots') or {
			compute.close()
			return err
		}
		compute.particle_scatter_kernel = compute.program.kernel('scatter_particles') or {
			compute.close()
			return err
		}
		compute.bullet_mark_kernel = compute.program.kernel('mark_bullet_slots') or {
			compute.close()
			return err
		}
		compute.bullet_scatter_kernel = compute.program.kernel('scatter_bullets') or {
			compute.close()
			return err
		}
		compute.shot_mark_kernel = compute.program.kernel('mark_shot_slots') or {
			compute.close()
			return err
		}
		compute.shot_scatter_kernel = compute.program.kernel('scatter_shots') or {
			compute.close()
			return err
		}
		compute.enemy_mark_kernel = compute.program.kernel('mark_enemy_slots') or {
			compute.close()
			return err
		}
		compute.enemy_scatter_kernel = compute.program.kernel('scatter_enemies') or {
			compute.close()
			return err
		}
		compute.collision_mark_kernel = compute.program.kernel('mark_collision_candidates') or {
			compute.close()
			return err
		}
		compute.collision_scatter_kernel = compute.program.kernel('scatter_collision_candidates') or {
			compute.close()
			return err
		}
		compute.collision_point_mark_kernel = compute.program.kernel('mark_collision_points') or {
			compute.close()
			return err
		}
		compute.collision_point_scatter_kernel = compute.program.kernel('scatter_collision_points') or {
			compute.close()
			return err
		}
		compute.scan_kernel = compute.program.kernel('scan_active_flags') or {
			compute.close()
			return err
		}
		compute.particle_kernel = compute.program.kernel('step_particles') or {
			compute.close()
			return err
		}
		compute.bullet_kernel = compute.program.kernel('step_bullets') or {
			compute.close()
			return err
		}
		compute.shot_kernel = compute.program.kernel('step_shots') or {
			compute.close()
			return err
		}
		compute.enemy_kernel = compute.program.kernel('step_enemies') or {
			compute.close()
			return err
		}
		return compute
	}

	fn ensure_buffer_capacity[T](context &cl.OwnedContext, buffer &cl.Buffer[T], count int) !&cl.Buffer[T] {
		if !isnil(buffer) && buffer.count >= count {
			return unsafe { buffer }
		}
		if !isnil(buffer) {
			mut previous := unsafe { buffer }
			previous.close()!
		}
		return cl.new_buffer[T](context, cl.mem_read_write, count)!
	}

	fn close_buffer_if_allocated[T](mut buffer &cl.Buffer[T]) {
		if !isnil(buffer) {
			buffer.close() or {}
		}
	}

	fn run_motion_kernel[T](context &cl.OwnedContext, queue &cl.OwnedCommandQueue,
		kernel &cl.OwnedKernel, buffer &cl.Buffer[T], mut items []T) !&cl.Buffer[T] {
		if items.len == 0 {
			return unsafe { buffer }
		}
		active_buffer := ensure_buffer_capacity(context, buffer, items.len)!
		active_buffer.write(queue, 0, items)!
		kernel.set_buffer_arg(0, active_buffer.handle)!
		kernel.enqueue_1d(queue, usize(items.len), 0)!
		active_buffer.read(queue, 0, mut items)!
		return active_buffer
	}

	fn (mut compute OpenCLCompute) scan_flags(count int) !(cl.Mem, int) {
		compute.active_flags_a = ensure_buffer_capacity(&compute.context, compute.active_flags_a, count)!
		compute.active_flags_b = ensure_buffer_capacity(&compute.context, compute.active_flags_b, count)!
		mut scan_input := compute.active_flags_a.handle
		mut scan_output := compute.active_flags_b.handle
		mut offset := 1
		for offset < count {
			scan_offset := i32(offset)
			compute.scan_kernel.set_buffer_arg(0, scan_input)!
			compute.scan_kernel.set_buffer_arg(1, scan_output)!
			compute.scan_kernel.set_arg(2, &scan_offset)!
			compute.scan_kernel.enqueue_1d(&compute.queue, usize(count), 0)!
			scan_input, scan_output = scan_output, scan_input
			offset *= 2
		}
		mut active_count_value := [i32(0)]
		if scan_input == compute.active_flags_a.handle {
			compute.active_flags_a.read(&compute.queue, count - 1, mut active_count_value)!
		} else {
			compute.active_flags_b.read(&compute.queue, count - 1, mut active_count_value)!
		}
		active_count := int(active_count_value[0])
		if active_count < 0 || active_count > count {
			return error('OpenCL compaction returned invalid count ${active_count} for ${count} slots')
		}
		return scan_input, active_count
	}

	fn (mut compute OpenCLCompute) scan_active_slots(mark_kernel &cl.OwnedKernel,
		slots cl.Mem, count int) !(cl.Mem, int) {
		compute.active_flags_a = ensure_buffer_capacity(&compute.context, compute.active_flags_a, count)!
		mark_kernel.set_buffer_arg(0, slots)!
		mark_kernel.set_buffer_arg(1, compute.active_flags_a.handle)!
		mark_kernel.enqueue_1d(&compute.queue, usize(count), 0)!
		return compute.scan_flags(count)
	}

	fn (mut compute OpenCLCompute) compact_and_step_particles(particles []Particle) !ParticleMotionSoa {
		if particles.len == 0 {
			return ParticleMotionSoa{}
		}
		mut slots := []OpenCLParticleSlot{len: particles.len}
		for index, particle in particles {
			slots[index] = OpenCLParticleSlot{
				active:     i32(particle.alive)
				angle:      particle.position.x
				depth:      particle.position.y
				velocity_x: particle.velocity.x
				velocity_y: particle.velocity.y
				life:       i32(particle.life)
			}
		}
		compute.particle_slots = ensure_buffer_capacity(&compute.context, compute.particle_slots, slots.len)!
		compute.particle_buffer = ensure_buffer_capacity(&compute.context, compute.particle_buffer, slots.len)!
		compute.particle_indices = ensure_buffer_capacity(&compute.context, compute.particle_indices, slots.len)!
		compute.particle_slots.write(&compute.queue, 0, slots)!
		scan, active_count := compute.scan_active_slots(&compute.particle_mark_kernel, compute.particle_slots.handle, slots.len)!
		if active_count == 0 {
			return ParticleMotionSoa{}
		}
		compute.particle_scatter_kernel.set_buffer_arg(0, compute.particle_slots.handle)!
		compute.particle_scatter_kernel.set_buffer_arg(1, scan)!
		compute.particle_scatter_kernel.set_buffer_arg(2, compute.particle_buffer.handle)!
		compute.particle_scatter_kernel.set_buffer_arg(3, compute.particle_indices.handle)!
		compute.particle_scatter_kernel.enqueue_1d(&compute.queue, usize(slots.len), 0)!
		compute.particle_kernel.set_buffer_arg(0, compute.particle_buffer.handle)!
		compute.particle_kernel.enqueue_1d(&compute.queue, usize(active_count), 0)!
		mut packed := []OpenCLParticleMotion{len: active_count}
		mut source_indices := []i32{len: active_count}
		compute.particle_buffer.read(&compute.queue, 0, mut packed)!
		compute.particle_indices.read(&compute.queue, 0, mut source_indices)!
		mut result := ParticleMotionSoa{
			source_indices: []int{cap: active_count}
			angles:         []f32{cap: active_count}
			depths:         []f32{cap: active_count}
			velocity_x:     []f32{cap: active_count}
			velocity_y:     []f32{cap: active_count}
			lives:          []int{cap: active_count}
		}
		for index, item in packed {
			result.source_indices << int(source_indices[index])
			result.angles << item.angle
			result.depths << item.depth
			result.velocity_x << item.velocity_x
			result.velocity_y << item.velocity_y
			result.lives << int(item.life)
		}
		return result
	}

	fn (mut compute OpenCLCompute) step_particles(mut particles ParticleMotionSoa) ! {
		if particles.len() == 0 {
			return
		}
		mut packed := []OpenCLParticleMotion{cap: particles.len()}
		for index in 0 .. particles.len() {
			packed << OpenCLParticleMotion{
				angle:      particles.angles[index]
				depth:      particles.depths[index]
				velocity_x: particles.velocity_x[index]
				velocity_y: particles.velocity_y[index]
				life:       i32(particles.lives[index])
			}
		}
		compute.particle_buffer = run_motion_kernel(&compute.context, &compute.queue, &compute.particle_kernel, compute.particle_buffer, mut packed)!
		for index, item in packed {
			particles.angles[index] = item.angle
			particles.depths[index] = item.depth
			particles.velocity_x[index] = item.velocity_x
			particles.velocity_y[index] = item.velocity_y
			particles.lives[index] = int(item.life)
		}
	}

	fn (mut compute OpenCLCompute) compact_and_step_bullets(bullets []Bullet, movement_scale f32) !BulletMotionSoa {
		if bullets.len == 0 {
			return BulletMotionSoa{}
		}
		mut slots := []OpenCLBulletSlot{len: bullets.len}
		for index, bullet in bullets {
			slots[index] = OpenCLBulletSlot{
				active:         i32(bullet.alive)
				angle:          bullet.position.x
				depth:          bullet.position.y
				direction:      bullet.direction
				speed:          bullet.speed
				x_reverse:      bullet.x_reverse
				speed_rank:     bullet.speed_rank
				movement_scale: movement_scale
				age:            i32(bullet.age)
			}
		}
		compute.bullet_slots = ensure_buffer_capacity(&compute.context, compute.bullet_slots, slots.len)!
		compute.bullet_buffer = ensure_buffer_capacity(&compute.context, compute.bullet_buffer, slots.len)!
		compute.bullet_indices = ensure_buffer_capacity(&compute.context, compute.bullet_indices, slots.len)!
		compute.bullet_slots.write(&compute.queue, 0, slots)!
		scan, active_count := compute.scan_active_slots(&compute.bullet_mark_kernel, compute.bullet_slots.handle, slots.len)!
		if active_count == 0 {
			return BulletMotionSoa{}
		}
		compute.bullet_scatter_kernel.set_buffer_arg(0, compute.bullet_slots.handle)!
		compute.bullet_scatter_kernel.set_buffer_arg(1, scan)!
		compute.bullet_scatter_kernel.set_buffer_arg(2, compute.bullet_buffer.handle)!
		compute.bullet_scatter_kernel.set_buffer_arg(3, compute.bullet_indices.handle)!
		compute.bullet_scatter_kernel.enqueue_1d(&compute.queue, usize(slots.len), 0)!
		compute.bullet_kernel.set_buffer_arg(0, compute.bullet_buffer.handle)!
		compute.bullet_kernel.enqueue_1d(&compute.queue, usize(active_count), 0)!
		mut packed := []OpenCLBulletMotion{len: active_count}
		mut source_indices := []i32{len: active_count}
		compute.bullet_buffer.read(&compute.queue, 0, mut packed)!
		compute.bullet_indices.read(&compute.queue, 0, mut source_indices)!
		mut result := BulletMotionSoa{
			source_indices:  []int{cap: active_count}
			angles:          []f32{cap: active_count}
			depths:          []f32{cap: active_count}
			directions:      []f32{cap: active_count}
			speeds:          []f32{cap: active_count}
			x_reverse:       []f32{cap: active_count}
			speed_ranks:     []f32{cap: active_count}
			movement_scales: []f32{cap: active_count}
			ages:            []int{cap: active_count}
		}
		for index, item in packed {
			result.source_indices << int(source_indices[index])
			result.angles << item.angle
			result.depths << item.depth
			result.directions << item.direction
			result.speeds << item.speed
			result.x_reverse << item.x_reverse
			result.speed_ranks << item.speed_rank
			result.movement_scales << item.movement_scale
			result.ages << int(item.age)
		}
		return result
	}

	fn (mut compute OpenCLCompute) step_bullets(mut bullets BulletMotionSoa) ! {
		if bullets.len() == 0 {
			return
		}
		mut packed := []OpenCLBulletMotion{cap: bullets.len()}
		for index in 0 .. bullets.len() {
			packed << OpenCLBulletMotion{
				angle:          bullets.angles[index]
				depth:          bullets.depths[index]
				direction:      bullets.directions[index]
				speed:          bullets.speeds[index]
				x_reverse:      bullets.x_reverse[index]
				speed_rank:     bullets.speed_ranks[index]
				movement_scale: bullets.movement_scales[index]
				age:            i32(bullets.ages[index])
			}
		}
		compute.bullet_buffer = run_motion_kernel(&compute.context, &compute.queue, &compute.bullet_kernel, compute.bullet_buffer, mut packed)!
		for index, item in packed {
			bullets.angles[index] = item.angle
			bullets.depths[index] = item.depth
			bullets.ages[index] = int(item.age)
		}
	}

	fn (mut compute OpenCLCompute) compact_and_step_shots(shots []Shot) !ShotMotionSoa {
		if shots.len == 0 {
			return ShotMotionSoa{}
		}
		mut slots := []OpenCLShotSlot{len: shots.len}
		for index, shot in shots {
			slots[index] = OpenCLShotSlot{
				active:    i32(shot.alive && !shot.charging)
				angle:     shot.position.x
				depth:     shot.position.y
				direction: shot.direction
				range:     shot.range
				age:       i32(shot.age)
			}
		}
		compute.shot_slots = ensure_buffer_capacity(&compute.context, compute.shot_slots, slots.len)!
		compute.shot_buffer = ensure_buffer_capacity(&compute.context, compute.shot_buffer, slots.len)!
		compute.shot_indices = ensure_buffer_capacity(&compute.context, compute.shot_indices, slots.len)!
		compute.shot_slots.write(&compute.queue, 0, slots)!
		scan, active_count := compute.scan_active_slots(&compute.shot_mark_kernel, compute.shot_slots.handle, slots.len)!
		if active_count == 0 {
			return ShotMotionSoa{}
		}
		compute.shot_scatter_kernel.set_buffer_arg(0, compute.shot_slots.handle)!
		compute.shot_scatter_kernel.set_buffer_arg(1, scan)!
		compute.shot_scatter_kernel.set_buffer_arg(2, compute.shot_buffer.handle)!
		compute.shot_scatter_kernel.set_buffer_arg(3, compute.shot_indices.handle)!
		compute.shot_scatter_kernel.enqueue_1d(&compute.queue, usize(slots.len), 0)!
		compute.shot_kernel.set_buffer_arg(0, compute.shot_buffer.handle)!
		compute.shot_kernel.enqueue_1d(&compute.queue, usize(active_count), 0)!
		mut packed := []OpenCLShotMotion{len: active_count}
		mut source_indices := []i32{len: active_count}
		compute.shot_buffer.read(&compute.queue, 0, mut packed)!
		compute.shot_indices.read(&compute.queue, 0, mut source_indices)!
		mut result := ShotMotionSoa{
			source_indices: []int{cap: active_count}
			angles:         []f32{cap: active_count}
			depths:         []f32{cap: active_count}
			directions:     []f32{cap: active_count}
			ranges:         []f32{cap: active_count}
			ages:           []int{cap: active_count}
		}
		for index, item in packed {
			result.source_indices << int(source_indices[index])
			result.angles << item.angle
			result.depths << item.depth
			result.directions << item.direction
			result.ranges << item.range
			result.ages << int(item.age)
		}
		return result
	}

	fn (mut compute OpenCLCompute) step_shots(mut shots ShotMotionSoa) ! {
		if shots.len() == 0 {
			return
		}
		mut packed := []OpenCLShotMotion{cap: shots.len()}
		for index in 0 .. shots.len() {
			packed << OpenCLShotMotion{
				angle:     shots.angles[index]
				depth:     shots.depths[index]
				direction: shots.directions[index]
				range:     shots.ranges[index]
				age:       i32(shots.ages[index])
			}
		}
		compute.shot_buffer = run_motion_kernel(&compute.context, &compute.queue, &compute.shot_kernel, compute.shot_buffer, mut packed)!
		for index, item in packed {
			shots.angles[index] = item.angle
			shots.depths[index] = item.depth
			shots.ranges[index] = item.range
			shots.ages[index] = int(item.age)
		}
	}

	fn (mut compute OpenCLCompute) compact_and_step_enemies(enemies EnemyMotionSlots) !EnemyMotionSoa {
		if enemies.items.len == 0 {
			return EnemyMotionSoa{}
		}
		mut slots := []OpenCLEnemySlot{len: enemies.items.len}
		for index, enemy in enemies.items {
			slots[index] = OpenCLEnemySlot{
				active:     i32(enemy.active)
				angle:      enemy.angle
				depth:      enemy.depth
				angle_step: enemy.angle_step
				depth_step: enemy.depth_step
				age:        i32(enemy.age)
			}
		}
		compute.enemy_slots = ensure_buffer_capacity(&compute.context, compute.enemy_slots, slots.len)!
		compute.enemy_buffer = ensure_buffer_capacity(&compute.context, compute.enemy_buffer, slots.len)!
		compute.enemy_indices = ensure_buffer_capacity(&compute.context, compute.enemy_indices, slots.len)!
		compute.enemy_slots.write(&compute.queue, 0, slots)!
		scan, active_count := compute.scan_active_slots(&compute.enemy_mark_kernel, compute.enemy_slots.handle, slots.len)!
		if active_count == 0 {
			return EnemyMotionSoa{}
		}
		compute.enemy_scatter_kernel.set_buffer_arg(0, compute.enemy_slots.handle)!
		compute.enemy_scatter_kernel.set_buffer_arg(1, scan)!
		compute.enemy_scatter_kernel.set_buffer_arg(2, compute.enemy_buffer.handle)!
		compute.enemy_scatter_kernel.set_buffer_arg(3, compute.enemy_indices.handle)!
		compute.enemy_scatter_kernel.enqueue_1d(&compute.queue, usize(slots.len), 0)!
		compute.enemy_kernel.set_buffer_arg(0, compute.enemy_buffer.handle)!
		compute.enemy_kernel.enqueue_1d(&compute.queue, usize(active_count), 0)!
		mut packed := []OpenCLEnemyMotion{len: active_count}
		mut source_indices := []i32{len: active_count}
		compute.enemy_buffer.read(&compute.queue, 0, mut packed)!
		compute.enemy_indices.read(&compute.queue, 0, mut source_indices)!
		mut result := EnemyMotionSoa{
			source_indices: []int{cap: active_count}
			angles:         []f32{cap: active_count}
			depths:         []f32{cap: active_count}
			angle_steps:    []f32{cap: active_count}
			depth_steps:    []f32{cap: active_count}
			ages:           []int{cap: active_count}
		}
		for index, item in packed {
			result.source_indices << int(source_indices[index])
			result.angles << item.angle
			result.depths << item.depth
			result.angle_steps << item.angle_step
			result.depth_steps << item.depth_step
			result.ages << int(item.age)
		}
		return result
	}

	fn (mut compute OpenCLCompute) step_enemies(mut enemies EnemyMotionSoa) ! {
		if enemies.len() == 0 {
			return
		}
		mut packed := []OpenCLEnemyMotion{cap: enemies.len()}
		for index in 0 .. enemies.len() {
			packed << OpenCLEnemyMotion{
				angle:      enemies.angles[index]
				depth:      enemies.depths[index]
				angle_step: enemies.angle_steps[index]
				depth_step: enemies.depth_steps[index]
				age:        i32(enemies.ages[index])
			}
		}
		compute.enemy_buffer = run_motion_kernel(&compute.context, &compute.queue, &compute.enemy_kernel, compute.enemy_buffer, mut packed)!
		for index, item in packed {
			enemies.angles[index] = item.angle
			enemies.depths[index] = item.depth
			enemies.ages[index] = int(item.age)
		}
	}

	fn (mut compute OpenCLCompute) compact_collision_points(points []OpenCLCollisionPoint,
		slots &cl.Buffer[OpenCLCollisionPoint],
		active_points &cl.Buffer[OpenCLCollisionPoint]) !(int, &cl.Buffer[OpenCLCollisionPoint]) {
		if points.len == 0 {
			return 0, unsafe { active_points }
		}
		compute.active_flags_a = ensure_buffer_capacity(&compute.context, compute.active_flags_a, points.len)!
		slots.write(&compute.queue, 0, points)!
		compute.collision_point_mark_kernel.set_buffer_arg(0, slots.handle)!
		compute.collision_point_mark_kernel.set_buffer_arg(1, compute.active_flags_a.handle)!
		compute.collision_point_mark_kernel.enqueue_1d(&compute.queue, usize(points.len), 0)!
		scan, active_count := compute.scan_flags(points.len)!
		if active_count == 0 {
			return 0, unsafe { active_points }
		}
		allocated_points := ensure_buffer_capacity(&compute.context, active_points, active_count)!
		compute.collision_point_scatter_kernel.set_buffer_arg(0, slots.handle)!
		compute.collision_point_scatter_kernel.set_buffer_arg(1, scan)!
		compute.collision_point_scatter_kernel.set_buffer_arg(2, allocated_points.handle)!
		compute.collision_point_scatter_kernel.enqueue_1d(&compute.queue, usize(points.len), 0)!
		return active_count, allocated_points
	}

	fn (mut compute OpenCLCompute) collision_candidates(shots []OpenCLCollisionPoint,
		targets []OpenCLCollisionPoint, depth_limit f32,
		angle_limit f32) !CollisionCandidateBatch {
		if shots.len == 0 {
			return CollisionCandidateBatch{}
		}
		compute.collision_shot_slots = ensure_buffer_capacity(&compute.context, compute.collision_shot_slots, shots.len)!
		active_shot_count, active_shots_buffer := compute.compact_collision_points(shots, compute.collision_shot_slots, compute.collision_shots)!
		compute.collision_shots = active_shots_buffer
		if active_shot_count == 0 {
			return CollisionCandidateBatch{}
		}
		if targets.len == 0 {
			return CollisionCandidateBatch{
				active_shots: active_shot_count
			}
		}
		compute.collision_target_slots = ensure_buffer_capacity(&compute.context, compute.collision_target_slots, targets.len)!
		active_target_count, active_targets_buffer := compute.compact_collision_points(targets, compute.collision_target_slots, compute.collision_targets)!
		compute.collision_targets = active_targets_buffer
		if active_target_count == 0 {
			return CollisionCandidateBatch{
				active_shots: active_shot_count
			}
		}
		pair_count := active_shot_count * active_target_count
		compute.collision_candidate_buffer = ensure_buffer_capacity(&compute.context, compute.collision_candidate_buffer, pair_count)!
		compute.active_flags_a = ensure_buffer_capacity(&compute.context, compute.active_flags_a, pair_count)!
		target_count := i32(active_target_count)
		compute.collision_mark_kernel.set_buffer_arg(0, compute.collision_shots.handle)!
		compute.collision_mark_kernel.set_buffer_arg(1, compute.collision_targets.handle)!
		compute.collision_mark_kernel.set_arg(2, &target_count)!
		compute.collision_mark_kernel.set_arg(3, &depth_limit)!
		compute.collision_mark_kernel.set_arg(4, &angle_limit)!
		compute.collision_mark_kernel.set_buffer_arg(5, compute.active_flags_a.handle)!
		compute.collision_mark_kernel.enqueue_1d(&compute.queue, usize(pair_count), 0)!
		scan, candidate_count := compute.scan_flags(pair_count)!
		if candidate_count == 0 {
			return CollisionCandidateBatch{
				active_shots:   active_shot_count
				active_targets: active_target_count
				tested_pairs:   pair_count
			}
		}
		compute.collision_scatter_kernel.set_buffer_arg(0, compute.collision_shots.handle)!
		compute.collision_scatter_kernel.set_buffer_arg(1, compute.collision_targets.handle)!
		compute.collision_scatter_kernel.set_arg(2, &target_count)!
		compute.collision_scatter_kernel.set_arg(3, &depth_limit)!
		compute.collision_scatter_kernel.set_arg(4, &angle_limit)!
		compute.collision_scatter_kernel.set_buffer_arg(5, scan)!
		compute.collision_scatter_kernel.set_buffer_arg(6, compute.collision_candidate_buffer.handle)!
		compute.collision_scatter_kernel.enqueue_1d(&compute.queue, usize(pair_count), 0)!
		mut packed_candidates := []OpenCLShotCollisionCandidate{len: candidate_count}
		compute.collision_candidate_buffer.read(&compute.queue, 0, mut packed_candidates)!
		mut candidates := []ShotCollisionCandidate{cap: candidate_count}
		for candidate in packed_candidates {
			candidates << ShotCollisionCandidate{
				shot_index:   int(candidate.shot_index)
				target_index: int(candidate.target_index)
			}
		}
		return CollisionCandidateBatch{
			candidates:     candidates
			active_shots:   active_shot_count
			active_targets: active_target_count
			tested_pairs:   pair_count
		}
	}

	fn (mut compute OpenCLCompute) shot_enemy_candidates(shots []Shot,
		enemies []Enemy) !CollisionCandidateBatch {
		mut packed_shots := []OpenCLCollisionPoint{len: shots.len}
		for index, shot in shots {
			packed_shots[index] = OpenCLCollisionPoint{
				active:       i32(shot.alive && !shot.charging)
				source_index: i32(index)
				angle:        shot.position.x
				depth:        shot.position.y
			}
		}
		mut packed_enemies := []OpenCLCollisionPoint{len: enemies.len}
		for index, enemy in enemies {
			packed_enemies[index] = OpenCLCollisionPoint{
				active:       i32(enemy.alive)
				source_index: i32(index)
				angle:        enemy.position.x
				depth:        enemy.position.y
			}
		}
		return compute.collision_candidates(packed_shots, packed_enemies, shot_enemy_candidate_depth_limit, shot_enemy_candidate_angle_limit)
	}

	fn (mut compute OpenCLCompute) shot_bullet_candidates(shots []Shot,
		bullets []Bullet) !CollisionCandidateBatch {
		mut packed_shots := []OpenCLCollisionPoint{len: shots.len}
		for index, shot in shots {
			packed_shots[index] = OpenCLCollisionPoint{
				active:       i32(shot.alive && !shot.charging && shot.charged)
				source_index: i32(index)
				angle:        shot.position.x
				depth:        shot.position.y
			}
		}
		mut packed_bullets := []OpenCLCollisionPoint{len: bullets.len}
		for index, bullet in bullets {
			packed_bullets[index] = OpenCLCollisionPoint{
				active:       i32(bullet.alive && bullet.disappear_ticks <= 0)
				source_index: i32(index)
				angle:        bullet.position.x
				depth:        bullet.position.y
			}
		}
		return compute.collision_candidates(packed_shots, packed_bullets, shot_bullet_candidate_depth_limit, shot_bullet_candidate_angle_limit)
	}

	fn (mut compute OpenCLCompute) close() {
		close_buffer_if_allocated(mut compute.particle_slots)
		close_buffer_if_allocated(mut compute.active_flags_a)
		close_buffer_if_allocated(mut compute.active_flags_b)
		close_buffer_if_allocated(mut compute.particle_buffer)
		close_buffer_if_allocated(mut compute.particle_indices)
		close_buffer_if_allocated(mut compute.bullet_slots)
		close_buffer_if_allocated(mut compute.bullet_buffer)
		close_buffer_if_allocated(mut compute.bullet_indices)
		close_buffer_if_allocated(mut compute.shot_slots)
		close_buffer_if_allocated(mut compute.shot_buffer)
		close_buffer_if_allocated(mut compute.shot_indices)
		close_buffer_if_allocated(mut compute.enemy_slots)
		close_buffer_if_allocated(mut compute.enemy_buffer)
		close_buffer_if_allocated(mut compute.enemy_indices)
		close_buffer_if_allocated(mut compute.collision_shot_slots)
		close_buffer_if_allocated(mut compute.collision_shots)
		close_buffer_if_allocated(mut compute.collision_target_slots)
		close_buffer_if_allocated(mut compute.collision_targets)
		close_buffer_if_allocated(mut compute.collision_candidate_buffer)
		compute.particle_mark_kernel.close() or {}
		compute.particle_scatter_kernel.close() or {}
		compute.bullet_mark_kernel.close() or {}
		compute.bullet_scatter_kernel.close() or {}
		compute.shot_mark_kernel.close() or {}
		compute.shot_scatter_kernel.close() or {}
		compute.enemy_mark_kernel.close() or {}
		compute.enemy_scatter_kernel.close() or {}
		compute.collision_mark_kernel.close() or {}
		compute.collision_scatter_kernel.close() or {}
		compute.collision_point_mark_kernel.close() or {}
		compute.collision_point_scatter_kernel.close() or {}
		compute.scan_kernel.close() or {}
		compute.particle_kernel.close() or {}
		compute.bullet_kernel.close() or {}
		compute.shot_kernel.close() or {}
		compute.enemy_kernel.close() or {}
		compute.program.close() or {}
		compute.queue.close() or {}
		compute.context.close() or {}
	}
}
