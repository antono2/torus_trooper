// Selects CPU or optional compute acceleration for entity updates and collision candidates.
module sim

import math

// Broad-phase limits cover the maximum source large-ship collision rectangle
// plus a fully charged size-13.6 shot at the minimum generated tunnel radius.
// Ordered simulation checks then apply the exact seeded shape and live shot size.
const shot_enemy_candidate_depth_limit = f32(10.81)
const shot_enemy_candidate_angle_limit = f32(2.04)
const shot_bullet_candidate_depth_limit = f32(4.09)
const shot_bullet_candidate_angle_limit = f32(0.98)

pub enum ComputeBackend {
	cpu
	opencl
}

pub struct ComputeStats {
pub mut:
	particle_items                         u64
	bullet_items                           u64
	shot_items                             u64
	enemy_items                            u64
	collision_candidate_items              u64
	collision_candidate_batches            u64
	collision_candidate_mismatched_batches u64
	collision_candidate_mismatches         u64
	collision_active_shots                 u64
	collision_active_targets               u64
	collision_tested_pairs                 u64
	rejected_batches                       u64
	fallback_batches                       u64
	verified_batches                       u64
	mismatched_batches                     u64
	differential_mismatches                u64
	max_differential_error                 f32
	particle_mismatched_batches            u64
	bullet_mismatched_batches              u64
	shot_mismatched_batches                u64
	enemy_mismatched_batches               u64
	particle_checksum                      u64
	bullet_checksum                        u64
	shot_checksum                          u64
	enemy_checksum                         u64
}

pub struct ShotCollisionCandidate {
pub:
	shot_index   int
	target_index int
}

struct CollisionCandidateBatch {
	candidates     []ShotCollisionCandidate
	active_shots   int
	active_targets int
	tested_pairs   int
}

// shot_enemy_collision_candidates is the ordered CPU reference for the broad
// phase. Gameplay still rechecks each pair because earlier candidates can kill
// either participant before a later pair is consumed.
pub fn shot_enemy_collision_candidates(shots []Shot, enemies []Enemy) []ShotCollisionCandidate {
	mut candidates := []ShotCollisionCandidate{}
	for shot_index, shot in shots {
		if !shot.alive || shot.charging {
			continue
		}
		for enemy_index, enemy in enemies {
			if enemy.alive
				&& f32(math.abs(enemy.position.y - shot.position.y)) < shot_enemy_candidate_depth_limit
				&& wrapped_distance(enemy.position.x, shot.position.x) < shot_enemy_candidate_angle_limit {
				candidates << ShotCollisionCandidate{
					shot_index: shot_index
					target_index: enemy_index
				}
			}
		}
	}
	return candidates
}

// shot_bullet_collision_candidates mirrors the charged-shot clearing broad phase.
// Regular released shots cannot clear hostile bullets and are excluded here.
pub fn shot_bullet_collision_candidates(shots []Shot, bullets []Bullet) []ShotCollisionCandidate {
	mut candidates := []ShotCollisionCandidate{}
	for shot_index, shot in shots {
		if !shot.alive || shot.charging || !shot.charged {
			continue
		}
		for bullet_index, bullet in bullets {
			if bullet.alive && bullet.disappear_ticks <= 0
				&& f32(math.abs(bullet.position.y - shot.position.y)) < shot_bullet_candidate_depth_limit
				&& wrapped_distance(bullet.position.x, shot.position.x) < shot_bullet_candidate_angle_limit {
				candidates << ShotCollisionCandidate{
					shot_index: shot_index
					target_index: bullet_index
				}
			}
		}
	}
	return candidates
}

pub fn (backend ComputeBackend) name() string {
	return match backend {
		.cpu { 'cpu' }
		.opencl { 'opencl' }
	}
}

@[heap]
pub struct ComputeSession {
pub:
	requested ComputeBackend
mut:
	active          ComputeBackend
	handle          voidptr
	device_name     string
	fallback_reason string
}

// new_compute_session creates the process-facing compute resources once. An
// unavailable optional backend is represented by an active CPU session and a
// diagnostic reason, rather than making game startup fail.
pub fn new_compute_session(requested ComputeBackend) &ComputeSession {
	mut session := &ComputeSession{
		requested: requested
		active: .cpu
	}
	if requested != .opencl {
		return session
	}
	$if opencl_compute ? {
		compute := new_opencl_compute() or {
			session.fallback_reason = err.msg()
			return session
		}
		session.handle = compute
		session.device_name = compute.device_name
		session.active = .opencl
	} $else {
		session.fallback_reason = 'this binary was built without -d opencl_compute'
	}
	return session
}

pub fn (session &ComputeSession) active_backend() ComputeBackend {
	return session.active
}

pub fn (session &ComputeSession) device() string {
	return session.device_name
}

pub fn (session &ComputeSession) fallback() string {
	return session.fallback_reason
}

fn (mut session ComputeSession) disable_opencl(reason string) {
	$if opencl_compute ? {
		if !isnil(session.handle) {
			mut compute := unsafe { &OpenCLCompute(session.handle) }
			compute.close()
		}
	}
	session.handle = unsafe { nil }
	session.active = .cpu
	session.fallback_reason = reason
}

pub fn (mut session ComputeSession) close() {
	if session.active == .opencl || !isnil(session.handle) {
		session.disable_opencl('compute session closed')
	}
}

fn (mut session ComputeSession) step_particles(mut particles ParticleMotionSoa) bool {
	$if !opencl_compute ? {
		_ = particles
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		compute.step_particles(mut particles) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) compact_and_step_particles(particles []Particle,
	mut output ParticleMotionSoa) bool {
	$if !opencl_compute ? {
		_ = particles
		_ = output
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		output = compute.compact_and_step_particles(particles) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) step_bullets(mut bullets BulletMotionSoa) bool {
	$if !opencl_compute ? {
		_ = bullets
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		compute.step_bullets(mut bullets) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) compact_and_step_bullets(bullets []Bullet, movement_scale f32,
	mut output BulletMotionSoa) bool {
	$if !opencl_compute ? {
		_ = bullets
		_ = movement_scale
		_ = output
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		output = compute.compact_and_step_bullets(bullets, movement_scale) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) step_shots(mut shots ShotMotionSoa) bool {
	$if !opencl_compute ? {
		_ = shots
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		compute.step_shots(mut shots) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) compact_and_step_shots(shots []Shot,
	mut output ShotMotionSoa) bool {
	$if !opencl_compute ? {
		_ = shots
		_ = output
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		output = compute.compact_and_step_shots(shots) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) step_enemies(mut enemies EnemyMotionSoa) bool {
	$if !opencl_compute ? {
		_ = enemies
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		compute.step_enemies(mut enemies) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) compact_and_step_enemies(enemies EnemyMotionSlots,
	mut output EnemyMotionSoa) bool {
	$if !opencl_compute ? {
		_ = enemies
		_ = output
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		output = compute.compact_and_step_enemies(enemies) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) shot_enemy_candidates(shots []Shot, enemies []Enemy,
	mut output CollisionCandidateBatch) bool {
	$if !opencl_compute ? {
		_ = shots
		_ = enemies
		_ = output
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		output = compute.shot_enemy_candidates(shots, enemies) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn (mut session ComputeSession) shot_bullet_candidates(shots []Shot, bullets []Bullet,
	mut output CollisionCandidateBatch) bool {
	$if !opencl_compute ? {
		_ = shots
		_ = bullets
		_ = output
	}
	if session.active != .opencl || isnil(session.handle) {
		return false
	}
	$if opencl_compute ? {
		mut compute := unsafe { &OpenCLCompute(session.handle) }
		output = compute.shot_bullet_candidates(shots, bullets) or {
			session.disable_opencl(err.msg())
			return false
		}
		return true
	}
	return false
}

fn collision_candidate_mismatches(reference []ShotCollisionCandidate,
	candidate []ShotCollisionCandidate) int {
	if reference.len != candidate.len {
		return 1
	}
	mut mismatches := 0
	for index, expected in reference {
		actual := candidate[index]
		if actual.shot_index != expected.shot_index || actual.target_index != expected.target_index {
			mismatches++
		}
	}
	return mismatches
}

fn (mut simulation Simulation) record_collision_candidates(batch CollisionCandidateBatch,
	mismatches int) {
	simulation.compute_stats.collision_candidate_batches++
	simulation.compute_stats.collision_candidate_items += u64(batch.candidates.len)
	simulation.compute_stats.collision_active_shots += u64(batch.active_shots)
	simulation.compute_stats.collision_active_targets += u64(batch.active_targets)
	simulation.compute_stats.collision_tested_pairs += u64(batch.tested_pairs)
	if mismatches > 0 {
		simulation.compute_stats.collision_candidate_mismatched_batches++
		simulation.compute_stats.collision_candidate_mismatches += u64(mismatches)
	}
}

fn (mut simulation Simulation) resolved_shot_enemy_candidates() []ShotCollisionCandidate {
	reference := shot_enemy_collision_candidates(simulation.shots, simulation.enemies)
	if simulation.config.compute_backend != .opencl || isnil(simulation.compute_session) {
		return reference
	}
	mut batch := CollisionCandidateBatch{}
	mut session := simulation.compute_session
	if !session.shot_enemy_candidates(simulation.shots, simulation.enemies, mut batch) {
		simulation.compute_stats.fallback_batches++
		return reference
	}
	mismatches := collision_candidate_mismatches(reference, batch.candidates)
	simulation.record_collision_candidates(batch, mismatches)
	return if mismatches == 0 { batch.candidates } else { reference }
}

fn (mut simulation Simulation) resolved_shot_bullet_candidates() []ShotCollisionCandidate {
	reference := shot_bullet_collision_candidates(simulation.shots, simulation.bullets)
	if simulation.config.compute_backend != .opencl || isnil(simulation.compute_session) {
		return reference
	}
	mut batch := CollisionCandidateBatch{}
	mut session := simulation.compute_session
	if !session.shot_bullet_candidates(simulation.shots, simulation.bullets, mut batch) {
		simulation.compute_stats.fallback_batches++
		return reference
	}
	mismatches := collision_candidate_mismatches(reference, batch.candidates)
	simulation.record_collision_candidates(batch, mismatches)
	return if mismatches == 0 { batch.candidates } else { reference }
}

pub fn (mut simulation Simulation) attach_compute_session(session &ComputeSession) {
	simulation.compute_session = session
}

pub fn (simulation &Simulation) active_compute_backend() ComputeBackend {
	if simulation.config.compute_backend == .opencl && !isnil(simulation.compute_session)
		&& simulation.compute_session.active_backend() == .opencl {
		return .opencl
	}
	return .cpu
}

fn (mut simulation Simulation) run_particle_backend(mut particles ParticleMotionSoa) bool {
	if simulation.config.compute_backend == .opencl {
		if !isnil(simulation.compute_session) {
			mut candidate := ParticleMotionSoa{}
			mut session := simulation.compute_session
			if session.compact_and_step_particles(simulation.particles, mut candidate) {
				mut reference := particles.deep_clone()
				if !cpu_step_particle_motion(mut reference) {
					return false
				}
				comparison := compare_particle_motion(reference, candidate, 0)
				simulation.record_differential(comparison)
				if comparison.matches() {
					particles = candidate
					return true
				}
				simulation.compute_stats.particle_mismatched_batches++
				simulation.compute_stats.fallback_batches++
				particles = reference
				return true
			}
		}
		simulation.compute_stats.fallback_batches++
	}
	return cpu_step_particle_motion(mut particles)
}

fn (mut simulation Simulation) run_bullet_backend(mut bullets BulletMotionSoa) bool {
	if simulation.config.compute_backend == .opencl {
		if !isnil(simulation.compute_session) {
			mut candidate := BulletMotionSoa{}
			mut session := simulation.compute_session
			movement_scale := if bullets.movement_scales.len > 0 {
				bullets.movement_scales[0]
			} else {
				f32(0)
			}
			if session.compact_and_step_bullets(simulation.bullets, movement_scale, mut candidate) {
				mut reference := bullets.deep_clone()
				if !cpu_step_bullet_motion(mut reference) {
					return false
				}
				comparison := compare_bullet_motion(reference, candidate, 0)
				simulation.record_differential(comparison)
				if comparison.matches() {
					bullets = candidate
					return true
				}
				simulation.compute_stats.bullet_mismatched_batches++
				simulation.compute_stats.fallback_batches++
				bullets = reference
				return true
			}
		}
		simulation.compute_stats.fallback_batches++
	}
	return cpu_step_bullet_motion(mut bullets)
}

fn (mut simulation Simulation) run_shot_backend(mut shots ShotMotionSoa) bool {
	if simulation.config.compute_backend == .opencl {
		if !isnil(simulation.compute_session) {
			mut candidate := ShotMotionSoa{}
			mut session := simulation.compute_session
			if session.compact_and_step_shots(simulation.shots, mut candidate) {
				mut reference := shots.deep_clone()
				if !cpu_step_shot_motion(mut reference) {
					return false
				}
				comparison := compare_shot_motion(reference, candidate, 0)
				simulation.record_differential(comparison)
				if comparison.matches() {
					shots = candidate
					return true
				}
				simulation.compute_stats.shot_mismatched_batches++
				simulation.compute_stats.fallback_batches++
				shots = reference
				return true
			}
		}
		simulation.compute_stats.fallback_batches++
	}
	return cpu_step_shot_motion(mut shots)
}

fn (mut simulation Simulation) run_enemy_backend(slots EnemyMotionSlots,
	mut enemies EnemyMotionSoa) bool {
	if simulation.config.compute_backend == .opencl {
		if !isnil(simulation.compute_session) {
			mut candidate := EnemyMotionSoa{}
			mut session := simulation.compute_session
			if session.compact_and_step_enemies(slots, mut candidate) {
				mut reference := enemies.deep_clone()
				if !cpu_step_enemy_motion(mut reference) {
					return false
				}
				comparison := compare_enemy_motion(reference, candidate, 0)
				simulation.record_differential(comparison)
				if comparison.matches() {
					enemies = candidate
					return true
				}
				simulation.compute_stats.enemy_mismatched_batches++
				simulation.compute_stats.fallback_batches++
				enemies = reference
				return true
			}
		}
		simulation.compute_stats.fallback_batches++
	}
	return cpu_step_enemy_motion(mut enemies)
}

fn (mut simulation Simulation) record_differential(comparison ComputeComparison) {
	simulation.compute_stats.verified_batches++
	if comparison.max_error > simulation.compute_stats.max_differential_error {
		simulation.compute_stats.max_differential_error = comparison.max_error
	}
	if !comparison.matches() {
		simulation.compute_stats.mismatched_batches++
		simulation.compute_stats.differential_mismatches += u64(comparison.mismatches)
	}
}

fn (mut simulation Simulation) dispatch_particle_motion() {
	mut particles := simulation.particle_motion_snapshot()
	if !simulation.run_particle_backend(mut particles) || !simulation.apply_particle_motion(particles) {
		simulation.compute_stats.rejected_batches++
		return
	}
	simulation.compute_stats.particle_items += u64(particles.len())
	simulation.compute_stats.particle_checksum = particle_motion_checksum(simulation.compute_stats.particle_checksum, particles)
}

fn (mut simulation Simulation) dispatch_bullet_motion() {
	mut bullets := simulation.bullet_motion_snapshot()
	if !simulation.run_bullet_backend(mut bullets) || !simulation.apply_bullet_motion(bullets) {
		simulation.compute_stats.rejected_batches++
		return
	}
	simulation.compute_stats.bullet_items += u64(bullets.len())
	simulation.compute_stats.bullet_checksum = bullet_motion_checksum(simulation.compute_stats.bullet_checksum, bullets)
}

fn (mut simulation Simulation) dispatch_shot_motion() {
	mut shots := simulation.shot_motion_snapshot()
	if !simulation.run_shot_backend(mut shots) || !simulation.apply_shot_motion(shots) {
		simulation.compute_stats.rejected_batches++
		return
	}
	simulation.compute_stats.shot_items += u64(shots.len())
	simulation.compute_stats.shot_checksum = shot_motion_checksum(simulation.compute_stats.shot_checksum, shots)
}

fn (mut simulation Simulation) dispatch_enemy_motion(slots EnemyMotionSlots) {
	mut enemies := slots.compact()
	if !simulation.run_enemy_backend(slots, mut enemies) || !simulation.apply_enemy_motion(enemies) {
		simulation.compute_stats.rejected_batches++
		return
	}
	simulation.compute_stats.enemy_items += u64(enemies.len())
	simulation.compute_stats.enemy_checksum = enemy_motion_checksum(simulation.compute_stats.enemy_checksum, enemies)
}

fn compute_checksum_start(previous u64, tag u64, length int) u64 {
	mut value := if previous == 0 { u64(14695981039346656037) } else { previous }
	value = fnv1a(value, tag)
	return fnv1a(value, u64(length))
}

pub fn particle_motion_checksum(previous u64, particles ParticleMotionSoa) u64 {
	mut value := compute_checksum_start(previous, 1, particles.len())
	for index in 0 .. particles.len() {
		value = fnv1a(value, u64(particles.source_indices[index]))
		value = fnv1a(value, u64(f32_bits(particles.angles[index])))
		value = fnv1a(value, u64(f32_bits(particles.depths[index])))
		value = fnv1a(value, u64(f32_bits(particles.velocity_x[index])))
		value = fnv1a(value, u64(f32_bits(particles.velocity_y[index])))
		value = fnv1a(value, u64(particles.lives[index]))
	}
	return value
}

pub fn bullet_motion_checksum(previous u64, bullets BulletMotionSoa) u64 {
	mut value := compute_checksum_start(previous, 2, bullets.len())
	for index in 0 .. bullets.len() {
		value = fnv1a(value, u64(bullets.source_indices[index]))
		value = fnv1a(value, u64(f32_bits(bullets.angles[index])))
		value = fnv1a(value, u64(f32_bits(bullets.depths[index])))
		value = fnv1a(value, u64(f32_bits(bullets.directions[index])))
		value = fnv1a(value, u64(f32_bits(bullets.speeds[index])))
		value = fnv1a(value, u64(f32_bits(bullets.x_reverse[index])))
		value = fnv1a(value, u64(f32_bits(bullets.speed_ranks[index])))
		value = fnv1a(value, u64(f32_bits(bullets.movement_scales[index])))
		value = fnv1a(value, u64(bullets.ages[index]))
	}
	return value
}

pub fn shot_motion_checksum(previous u64, shots ShotMotionSoa) u64 {
	mut value := compute_checksum_start(previous, 3, shots.len())
	for index in 0 .. shots.len() {
		value = fnv1a(value, u64(shots.source_indices[index]))
		value = fnv1a(value, u64(f32_bits(shots.angles[index])))
		value = fnv1a(value, u64(f32_bits(shots.depths[index])))
		value = fnv1a(value, u64(f32_bits(shots.directions[index])))
		value = fnv1a(value, u64(f32_bits(shots.ranges[index])))
		value = fnv1a(value, u64(shots.ages[index]))
	}
	return value
}

pub fn enemy_motion_checksum(previous u64, enemies EnemyMotionSoa) u64 {
	mut value := compute_checksum_start(previous, 4, enemies.len())
	for index in 0 .. enemies.len() {
		value = fnv1a(value, u64(enemies.source_indices[index]))
		value = fnv1a(value, u64(f32_bits(enemies.angles[index])))
		value = fnv1a(value, u64(f32_bits(enemies.depths[index])))
		value = fnv1a(value, u64(f32_bits(enemies.angle_steps[index])))
		value = fnv1a(value, u64(f32_bits(enemies.depth_steps[index])))
		value = fnv1a(value, u64(enemies.ages[index]))
	}
	return value
}

pub fn (stats &ComputeStats) checksum() u64 {
	mut value := u64(14695981039346656037)
	value = fnv1a(value, stats.particle_checksum)
	value = fnv1a(value, stats.bullet_checksum)
	value = fnv1a(value, stats.shot_checksum)
	return fnv1a(value, stats.enemy_checksum)
}

pub struct ComputeComparison {
pub mut:
	compatible bool = true
	mismatches int
	max_error  f32
}

pub fn (comparison &ComputeComparison) matches() bool {
	return comparison.compatible && comparison.mismatches == 0
}

fn compare_f32_field(reference []f32, candidate []f32, tolerance f32, mut result ComputeComparison) {
	if reference.len != candidate.len {
		result.compatible = false
		result.mismatches++
		return
	}
	for index, expected in reference {
		delta := f32(math.abs(expected - candidate[index]))
		if delta > result.max_error {
			result.max_error = delta
		}
		if delta > tolerance {
			result.mismatches++
		}
	}
}

fn compare_int_field(reference []int, candidate []int, mut result ComputeComparison) {
	if reference.len != candidate.len {
		result.compatible = false
		result.mismatches++
		return
	}
	for index, expected in reference {
		if expected != candidate[index] {
			result.mismatches++
		}
	}
}

fn comparison_start(reference_valid bool, candidate_valid bool, reference_indices []int,
	candidate_indices []int) ComputeComparison {
	mut result := ComputeComparison{ compatible: reference_valid && candidate_valid }
	if !result.compatible {
		result.mismatches++
	}
	compare_int_field(reference_indices, candidate_indices, mut result)
	return result
}

pub fn compare_particle_motion(reference ParticleMotionSoa, candidate ParticleMotionSoa,
	tolerance f32) ComputeComparison {
	mut result := comparison_start(reference.valid(), candidate.valid(), reference.source_indices, candidate.source_indices)
	limit := f32_max(tolerance, 0)
	compare_f32_field(reference.angles, candidate.angles, limit, mut result)
	compare_f32_field(reference.depths, candidate.depths, limit, mut result)
	compare_f32_field(reference.velocity_x, candidate.velocity_x, limit, mut result)
	compare_f32_field(reference.velocity_y, candidate.velocity_y, limit, mut result)
	compare_int_field(reference.lives, candidate.lives, mut result)
	return result
}

pub fn compare_bullet_motion(reference BulletMotionSoa, candidate BulletMotionSoa,
	tolerance f32) ComputeComparison {
	mut result := comparison_start(reference.valid(), candidate.valid(), reference.source_indices, candidate.source_indices)
	limit := f32_max(tolerance, 0)
	compare_f32_field(reference.angles, candidate.angles, limit, mut result)
	compare_f32_field(reference.depths, candidate.depths, limit, mut result)
	compare_f32_field(reference.directions, candidate.directions, limit, mut result)
	compare_f32_field(reference.speeds, candidate.speeds, limit, mut result)
	compare_f32_field(reference.x_reverse, candidate.x_reverse, limit, mut result)
	compare_f32_field(reference.speed_ranks, candidate.speed_ranks, limit, mut result)
	compare_f32_field(reference.movement_scales, candidate.movement_scales, limit, mut result)
	compare_int_field(reference.ages, candidate.ages, mut result)
	return result
}

pub fn compare_shot_motion(reference ShotMotionSoa, candidate ShotMotionSoa,
	tolerance f32) ComputeComparison {
	mut result := comparison_start(reference.valid(), candidate.valid(), reference.source_indices, candidate.source_indices)
	limit := f32_max(tolerance, 0)
	compare_f32_field(reference.angles, candidate.angles, limit, mut result)
	compare_f32_field(reference.depths, candidate.depths, limit, mut result)
	compare_f32_field(reference.directions, candidate.directions, limit, mut result)
	compare_f32_field(reference.ranges, candidate.ranges, limit, mut result)
	compare_int_field(reference.ages, candidate.ages, mut result)
	return result
}

pub fn compare_enemy_motion(reference EnemyMotionSoa, candidate EnemyMotionSoa,
	tolerance f32) ComputeComparison {
	mut result := comparison_start(reference.valid(), candidate.valid(), reference.source_indices, candidate.source_indices)
	limit := f32_max(tolerance, 0)
	compare_f32_field(reference.angles, candidate.angles, limit, mut result)
	compare_f32_field(reference.depths, candidate.depths, limit, mut result)
	compare_f32_field(reference.angle_steps, candidate.angle_steps, limit, mut result)
	compare_f32_field(reference.depth_steps, candidate.depth_steps, limit, mut result)
	compare_int_field(reference.ages, candidate.ages, mut result)
	return result
}

// ParticleMotionSoa is the first simulation-side compute buffer. source_indices
// preserve stable pool slots while active particles are compacted for the
// kernel-sized movement pass.
pub struct ParticleMotionSoa {
pub mut:
	source_indices []int
	angles         []f32
	depths         []f32
	velocity_x     []f32
	velocity_y     []f32
	lives          []int
}

pub fn (particles &ParticleMotionSoa) len() int {
	return particles.source_indices.len
}

pub fn (particles &ParticleMotionSoa) valid() bool {
	return particles.angles.len == particles.len() && particles.depths.len == particles.len()
		&& particles.velocity_x.len == particles.len()
		&& particles.velocity_y.len == particles.len() && particles.lives.len == particles.len()
}

fn (particles &ParticleMotionSoa) deep_clone() ParticleMotionSoa {
	return ParticleMotionSoa{
		source_indices: particles.source_indices.clone()
		angles: particles.angles.clone()
		depths: particles.depths.clone()
		velocity_x: particles.velocity_x.clone()
		velocity_y: particles.velocity_y.clone()
		lives: particles.lives.clone()
	}
}

pub fn (simulation &Simulation) particle_motion_snapshot() ParticleMotionSoa {
	mut result := ParticleMotionSoa{}
	for index, particle in simulation.particles {
		if !particle.alive {
			continue
		}
		result.source_indices << index
		result.angles << particle.position.x
		result.depths << particle.position.y
		result.velocity_x << particle.velocity.x
		result.velocity_y << particle.velocity.y
		result.lives << particle.life
	}
	return result
}

// cpu_step_particle_motion is the reference implementation for a future
// element-wise OpenCL movement kernel.
pub fn cpu_step_particle_motion(mut particles ParticleMotionSoa) bool {
	if !particles.valid() {
		return false
	}
	for index in 0 .. particles.len() {
		particles.angles[index] = wrap_angle(particles.angles[index] + particles.velocity_x[index])
		particles.depths[index] += particles.velocity_y[index]
		particles.lives[index]--
	}
	return true
}

fn (mut simulation Simulation) apply_particle_motion(particles ParticleMotionSoa) bool {
	if !particles.valid() {
		return false
	}
	for index, source_index in particles.source_indices {
		if source_index < 0 || source_index >= simulation.particles.len {
			return false
		}
		mut particle := simulation.particles[source_index]
		particle.position.x = particles.angles[index]
		particle.position.y = particles.depths[index]
		particle.velocity.x = particles.velocity_x[index]
		particle.velocity.y = particles.velocity_y[index]
		particle.life = particles.lives[index]
		particle.alive = particle.life >= 0
		simulation.particles[source_index] = particle
	}
	return true
}

// BulletMotionSoa contains only the fields required by the parallel hostile
// bullet translation pass. Pattern runners prepare direction and speed first;
// collision and lifecycle decisions remain an ordered gameplay pass afterward.
pub struct BulletMotionSoa {
pub mut:
	source_indices  []int
	angles          []f32
	depths          []f32
	directions      []f32
	speeds          []f32
	x_reverse       []f32
	speed_ranks     []f32
	movement_scales []f32
	ages            []int
}

pub fn (bullets &BulletMotionSoa) len() int {
	return bullets.source_indices.len
}

pub fn (bullets &BulletMotionSoa) valid() bool {
	return bullets.angles.len == bullets.len() && bullets.depths.len == bullets.len()
		&& bullets.directions.len == bullets.len() && bullets.speeds.len == bullets.len()
		&& bullets.x_reverse.len == bullets.len() && bullets.speed_ranks.len == bullets.len()
		&& bullets.movement_scales.len == bullets.len() && bullets.ages.len == bullets.len()
}

fn (bullets &BulletMotionSoa) deep_clone() BulletMotionSoa {
	return BulletMotionSoa{
		source_indices: bullets.source_indices.clone()
		angles: bullets.angles.clone()
		depths: bullets.depths.clone()
		directions: bullets.directions.clone()
		speeds: bullets.speeds.clone()
		x_reverse: bullets.x_reverse.clone()
		speed_ranks: bullets.speed_ranks.clone()
		movement_scales: bullets.movement_scales.clone()
		ages: bullets.ages.clone()
	}
}

pub fn (simulation &Simulation) bullet_motion_snapshot() BulletMotionSoa {
	mut result := BulletMotionSoa{}
	for index, bullet in simulation.bullets {
		if !bullet.alive {
			continue
		}
		result.source_indices << index
		result.angles << bullet.position.x
		result.depths << bullet.position.y
		result.directions << bullet.direction
		result.speeds << bullet.speed
		result.x_reverse << bullet.x_reverse
		result.speed_ranks << bullet.speed_rank
		result.movement_scales << simulation.ship.speed * 5
		result.ages << bullet.age
	}
	return result
}

pub fn cpu_step_bullet_motion(mut bullets BulletMotionSoa) bool {
	if !bullets.valid() {
		return false
	}
	for index in 0 .. bullets.len() {
		movement_x := f32(math.sin(bullets.directions[index])) * bullets.speeds[index] * bullets.speed_ranks[index] * bullets.x_reverse[index]
		movement_y := f32(math.cos(bullets.directions[index])) * bullets.speeds[index] * bullets.speed_ranks[index]
		direction := f32(math.atan2(movement_x, movement_y))
		ratio := (1 - f32(math.abs(math.sin(direction))) * 0.999) * bullets.movement_scales[index]
		bullets.angles[index] = wrap_angle(bullets.angles[index] + movement_x * ratio)
		bullets.depths[index] += movement_y * ratio
		bullets.ages[index]++
	}
	return true
}

fn (mut simulation Simulation) apply_bullet_motion(bullets BulletMotionSoa) bool {
	if !bullets.valid() {
		return false
	}
	for index, source_index in bullets.source_indices {
		if source_index < 0 || source_index >= simulation.bullets.len {
			return false
		}
		mut bullet := simulation.bullets[source_index]
		bullet.position.x = bullets.angles[index]
		bullet.position.y = bullets.depths[index]
		bullet.age = bullets.ages[index]
		simulation.bullets[source_index] = bullet
	}
	return true
}

pub struct ShotMotionSoa {
pub mut:
	source_indices []int
	angles         []f32
	depths         []f32
	directions     []f32
	ranges         []f32
	ages           []int
}

pub fn (shots &ShotMotionSoa) len() int {
	return shots.source_indices.len
}

pub fn (shots &ShotMotionSoa) valid() bool {
	return shots.angles.len == shots.len() && shots.depths.len == shots.len()
		&& shots.directions.len == shots.len() && shots.ranges.len == shots.len()
		&& shots.ages.len == shots.len()
}

fn (shots &ShotMotionSoa) deep_clone() ShotMotionSoa {
	return ShotMotionSoa{
		source_indices: shots.source_indices.clone()
		angles: shots.angles.clone()
		depths: shots.depths.clone()
		directions: shots.directions.clone()
		ranges: shots.ranges.clone()
		ages: shots.ages.clone()
	}
}

pub fn (simulation &Simulation) shot_motion_snapshot() ShotMotionSoa {
	mut result := ShotMotionSoa{}
	for index, shot in simulation.shots {
		if !shot.alive || shot.charging {
			continue
		}
		result.source_indices << index
		result.angles << shot.position.x
		result.depths << shot.position.y
		result.directions << shot.direction
		result.ranges << shot.range
		result.ages << shot.age
	}
	return result
}

pub fn cpu_step_shot_motion(mut shots ShotMotionSoa) bool {
	if !shots.valid() {
		return false
	}
	for index in 0 .. shots.len() {
		shots.angles[index] = wrap_angle(shots.angles[index] + f32(math.sin(shots.directions[index])) * 0.75)
		shots.depths[index] += f32(math.cos(shots.directions[index])) * 0.75
		shots.ranges[index] -= 0.75
		shots.ages[index]++
	}
	return true
}

fn (mut simulation Simulation) apply_shot_motion(shots ShotMotionSoa) bool {
	if !shots.valid() {
		return false
	}
	for index, source_index in shots.source_indices {
		if source_index < 0 || source_index >= simulation.shots.len {
			return false
		}
		mut shot := simulation.shots[source_index]
		shot.position.x = shots.angles[index]
		shot.position.y = shots.depths[index]
		shot.range = shots.ranges[index]
		shot.age = shots.ages[index]
		simulation.shots[source_index] = shot
	}
	return true
}

pub struct EnemyMotionSoa {
pub mut:
	source_indices []int
	angles         []f32
	depths         []f32
	angle_steps    []f32
	depth_steps    []f32
	ages           []int
}

pub struct EnemyMotionSlot {
pub:
	active     bool
	angle      f32
	depth      f32
	angle_step f32
	depth_step f32
	age        int
}

pub struct EnemyMotionSlots {
pub mut:
	items []EnemyMotionSlot
}

pub fn new_enemy_motion_slots(count int) EnemyMotionSlots {
	return EnemyMotionSlots{
		items: []EnemyMotionSlot{len: count}
	}
}

fn (mut slots EnemyMotionSlots) set(source_index int, enemy Enemy, depth_step f32) {
	if source_index < 0 || source_index >= slots.items.len {
		return
	}
	slots.items[source_index] = EnemyMotionSlot{
		active: enemy.alive
		angle: enemy.position.x
		depth: enemy.position.y
		angle_step: enemy.turn_speed
		depth_step: depth_step
		age: enemy.age + 1
	}
}

fn (slots &EnemyMotionSlots) compact() EnemyMotionSoa {
	mut enemies := EnemyMotionSoa{}
	for source_index, slot in slots.items {
		if !slot.active {
			continue
		}
		enemies.source_indices << source_index
		enemies.angles << slot.angle
		enemies.depths << slot.depth
		enemies.angle_steps << slot.angle_step
		enemies.depth_steps << slot.depth_step
		enemies.ages << slot.age
	}
	return enemies
}

pub fn (enemies &EnemyMotionSoa) len() int {
	return enemies.source_indices.len
}

pub fn (enemies &EnemyMotionSoa) valid() bool {
	return enemies.angles.len == enemies.len() && enemies.depths.len == enemies.len()
		&& enemies.angle_steps.len == enemies.len() && enemies.depth_steps.len == enemies.len()
		&& enemies.ages.len == enemies.len()
}

fn (enemies &EnemyMotionSoa) deep_clone() EnemyMotionSoa {
	return EnemyMotionSoa{
		source_indices: enemies.source_indices.clone()
		angles: enemies.angles.clone()
		depths: enemies.depths.clone()
		angle_steps: enemies.angle_steps.clone()
		depth_steps: enemies.depth_steps.clone()
		ages: enemies.ages.clone()
	}
}

fn (mut enemies EnemyMotionSoa) append(source_index int, enemy Enemy, depth_step f32) {
	enemies.source_indices << source_index
	enemies.angles << enemy.position.x
	enemies.depths << enemy.position.y
	enemies.angle_steps << enemy.turn_speed
	enemies.depth_steps << depth_step
	enemies.ages << enemy.age + 1
}

pub fn cpu_step_enemy_motion(mut enemies EnemyMotionSoa) bool {
	if !enemies.valid() {
		return false
	}
	for index in 0 .. enemies.len() {
		enemies.angles[index] = wrap_angle(enemies.angles[index] + enemies.angle_steps[index])
		enemies.depths[index] += enemies.depth_steps[index]
	}
	return true
}

fn (mut simulation Simulation) apply_enemy_motion(enemies EnemyMotionSoa) bool {
	if !enemies.valid() {
		return false
	}
	for index, source_index in enemies.source_indices {
		if source_index < 0 || source_index >= simulation.enemies.len {
			return false
		}
		mut enemy := simulation.enemies[source_index]
		enemy.position.x = enemies.angles[index]
		enemy.position.y = enemies.depths[index]
		enemy.age = enemies.ages[index]
		simulation.enemies[source_index] = enemy
	}
	return true
}
