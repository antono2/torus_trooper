// Compares batched compute paths with scalar references and checks entity compaction.
module sim

import math

fn test_cpu_particle_compute_matches_scalar_reference_and_compacts_slots() {
	mut simulation := new_simulation(SimulationConfig{ particle_capacity: 4 })
	simulation.particles[1] = Particle{
		alive: true
		position: Vec2{ x: 6.27, y: 2 }
		velocity: Vec2{ x: 0.04, y: -0.5 }
		life: 2
		initial_life: 2
	}
	simulation.particles[3] = Particle{
		alive: true
		position: Vec2{ x: 1, y: -1 }
		velocity: Vec2{ x: -0.2, y: 0.25 }
		life: 1
		initial_life: 1
	}
	mut particles := simulation.particle_motion_snapshot()
	expected_velocity_x := simulation.particles[1].velocity.x
	expected_velocity_y := simulation.particles[1].velocity.y
	assert particles.valid()
	assert particles.source_indices == [1, 3]
	assert cpu_step_particle_motion(mut particles)
	assert simulation.apply_particle_motion(particles)
	assert simulation.particles[1].position.x == wrap_angle(f32(6.27 + 0.04))
	assert simulation.particles[1].position.y == 1.5
	assert simulation.particles[1].velocity.x == expected_velocity_x
	assert simulation.particles[1].velocity.y == expected_velocity_y
	assert simulation.particles[1].life == 1
	assert simulation.particles[1].alive
	assert simulation.particles[3].alive
	assert simulation.particles[3].life == 0
}

fn test_cpu_particle_compute_rejects_mismatched_soa_fields() {
	mut particles := ParticleMotionSoa{ source_indices: [0], angles: [f32(1)] }
	assert !particles.valid()
	assert !cpu_step_particle_motion(mut particles)
}

fn test_cpu_bullet_compute_matches_scalar_kinematics_and_compacts_slots() {
	mut simulation := new_simulation(SimulationConfig{ bullet_capacity: 4 })
	simulation.ship.speed = 0.8
	simulation.bullets[2] = Bullet{
		alive: true
		position: Vec2{ x: 6.27, y: 4 }
		direction: 0.4
		speed: 0.25
		x_reverse: -1
		speed_rank: 1.2
		age: 7
	}
	mut expected := simulation.bullets[2]
	movement_x := f32(math.sin(expected.direction)) * expected.speed * expected.speed_rank * expected.x_reverse
	movement_y := f32(math.cos(expected.direction)) * expected.speed * expected.speed_rank
	movement_direction := f32(math.atan2(movement_x, movement_y))
	ratio := (1 - f32(math.abs(math.sin(movement_direction))) * 0.999) * simulation.ship.speed * 5
	expected.position.x = wrap_angle(expected.position.x + movement_x * ratio)
	expected.position.y += movement_y * ratio
	expected.age++
	mut bullets := simulation.bullet_motion_snapshot()
	assert bullets.valid()
	assert bullets.source_indices == [2]
	assert cpu_step_bullet_motion(mut bullets)
	assert simulation.apply_bullet_motion(bullets)
	assert simulation.bullets[2].position.x == expected.position.x
	assert simulation.bullets[2].position.y == expected.position.y
	assert simulation.bullets[2].age == expected.age
}

fn test_cpu_bullet_compute_rejects_mismatched_soa_fields() {
	mut bullets := BulletMotionSoa{ source_indices: [0], angles: [f32(1)] }
	assert !bullets.valid()
	assert !cpu_step_bullet_motion(mut bullets)
}

fn test_cpu_shot_compute_matches_scalar_kinematics_and_skips_charging_slots() {
	mut simulation := new_simulation(SimulationConfig{ shot_capacity: 3 })
	simulation.shots[0] = Shot{ alive: true, charging: true, range: 8 }
	simulation.shots[2] = Shot{
		alive: true
		position: Vec2{ x: 6.1, y: 2 }
		direction: -0.3
		range: 5
		age: 4
	}
	mut expected := simulation.shots[2]
	expected.position.x = wrap_angle(expected.position.x + f32(math.sin(expected.direction)) * 0.75)
	expected.position.y += f32(math.cos(expected.direction)) * 0.75
	expected.range -= 0.75
	expected.age++
	mut shots := simulation.shot_motion_snapshot()
	assert shots.valid()
	assert shots.source_indices == [2]
	assert cpu_step_shot_motion(mut shots)
	assert simulation.apply_shot_motion(shots)
	assert simulation.shots[2].position.x == expected.position.x
	assert simulation.shots[2].position.y == expected.position.y
	assert simulation.shots[2].range == expected.range
	assert simulation.shots[2].age == expected.age
}

fn test_cpu_shot_compute_rejects_mismatched_soa_fields() {
	mut shots := ShotMotionSoa{ source_indices: [0], angles: [f32(1)] }
	assert !shots.valid()
	assert !cpu_step_shot_motion(mut shots)
}

fn test_cpu_enemy_compute_matches_scalar_translation_and_stable_slots() {
	mut simulation := new_simulation(SimulationConfig{ enemy_capacity: 3 })
	simulation.enemies[1] = Enemy{
		alive: true
		position: Vec2{ x: 6.2, y: 8 }
		turn_speed: 0.2
		age: 12
	}
	mut expected := simulation.enemies[1]
	expected.position.x = wrap_angle(expected.position.x + expected.turn_speed)
	expected.position.y += f32(-0.4)
	expected.age++
	mut enemies := EnemyMotionSoa{}
	enemies.append(1, simulation.enemies[1], -0.4)
	assert enemies.valid()
	assert enemies.source_indices == [1]
	assert cpu_step_enemy_motion(mut enemies)
	assert simulation.apply_enemy_motion(enemies)
	assert simulation.enemies[1].position.x == expected.position.x
	assert simulation.enemies[1].position.y == expected.position.y
	assert simulation.enemies[1].age == expected.age
}

fn test_cpu_enemy_compute_rejects_mismatched_soa_fields() {
	mut enemies := EnemyMotionSoa{ source_indices: [0], angles: [f32(1)] }
	assert !enemies.valid()
	assert !cpu_step_enemy_motion(mut enemies)
}

fn test_enemy_motion_slots_preserve_prepared_steps_and_source_indices() {
	mut slots := new_enemy_motion_slots(5)
	slots.set(1, Enemy{
		alive: true
		position: Vec2{ x: 2, y: 7 }
		turn_speed: 0.03
		age: 9
	}, -0.4)
	slots.set(4, Enemy{
		alive: true
		position: Vec2{ x: 5, y: 3 }
		turn_speed: -0.02
		age: 12
	}, 0.1)
	compacted := slots.compact()
	assert compacted.source_indices == [1, 4]
	assert compacted.angle_steps == [f32(0.03), -0.02]
	assert compacted.depth_steps == [f32(-0.4), 0.1]
	assert compacted.ages == [10, 13]
}

fn test_cpu_shot_enemy_candidates_preserve_pair_order_and_wrapping() {
	mut shots := []Shot{len: 5}
	shots[1] = Shot{
		alive: true
		position: Vec2{ x: 0.02, y: 5 }
	}
	shots[2] = Shot{
		alive: true
		charging: true
		position: Vec2{ x: 0.04, y: 5 }
	}
	shots[4] = Shot{
		alive: true
		position: Vec2{ x: 0.08, y: 5.2 }
	}
	mut enemies := []Enemy{len: 4}
	enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 6.25, y: 5.7 }
	}
	enemies[2] = Enemy{
		alive: true
		position: Vec2{ x: 0.1, y: 5.79 }
	}
	enemies[3] = Enemy{
		alive: true
		position: Vec2{ x: 0.08, y: 6.0 }
	}
	assert shot_enemy_collision_candidates(shots, enemies) == [
		ShotCollisionCandidate{ shot_index: 1, target_index: 0 },
		ShotCollisionCandidate{ shot_index: 1, target_index: 2 },
		ShotCollisionCandidate{ shot_index: 1, target_index: 3 },
		ShotCollisionCandidate{ shot_index: 4, target_index: 0 },
		ShotCollisionCandidate{ shot_index: 4, target_index: 2 },
		ShotCollisionCandidate{ shot_index: 4, target_index: 3 },
	]
}

fn test_cpu_shot_bullet_candidates_filter_regular_and_charging_shots() {
	mut shots := []Shot{len: 5}
	shots[0] = Shot{
		alive: true
		position: Vec2{ x: 0.02, y: 5 }
	}
	shots[2] = Shot{
		alive: true
		star_shell: true
		position: Vec2{ x: 0.02, y: 5 }
	}
	shots[3] = Shot{
		alive: true
		charged: true
		charging: true
		position: Vec2{ x: 0.02, y: 5 }
	}
	shots[4] = Shot{
		alive: true
		charged: true
		position: Vec2{ x: 0.08, y: 5.2 }
	}
	mut bullets := []Bullet{len: 4}
	bullets[0] = Bullet{
		alive: true
		position: Vec2{ x: 6.25, y: 5.4 }
	}
	bullets[2] = Bullet{
		alive: true
		position: Vec2{ x: 0.14, y: 5.44 }
	}
	bullets[3] = Bullet{
		alive: true
		position: Vec2{ x: 0.08, y: 5.65 }
	}
	assert shot_bullet_collision_candidates(shots, bullets) == [
		ShotCollisionCandidate{ shot_index: 4, target_index: 0 },
		ShotCollisionCandidate{ shot_index: 4, target_index: 2 },
		ShotCollisionCandidate{ shot_index: 4, target_index: 3 },
	]
}

fn test_compute_dispatch_tracks_each_workload_and_rejects_no_valid_batches() {
	mut simulation := new_simulation(SimulationConfig{
		bullet_capacity: 2
		shot_capacity: 2
		enemy_capacity: 2
		particle_capacity: 2
	})
	simulation.bullets[0] = Bullet{ alive: true, speed: 0.1 }
	simulation.shots[0] = Shot{ alive: true, range: 2 }
	simulation.particles[0] = Particle{ alive: true, life: 2, initial_life: 2 }
	simulation.dispatch_bullet_motion()
	simulation.dispatch_shot_motion()
	simulation.dispatch_particle_motion()
	mut enemies := new_enemy_motion_slots(2)
	enemies.set(0, Enemy{ alive: true }, -0.1)
	simulation.dispatch_enemy_motion(enemies)
	assert simulation.config.compute_backend == .cpu
	assert simulation.compute_stats.bullet_items == 1
	assert simulation.compute_stats.shot_items == 1
	assert simulation.compute_stats.particle_items == 1
	assert simulation.compute_stats.enemy_items == 1
	assert simulation.compute_stats.rejected_batches == 0
}

fn test_requested_opencl_backend_falls_back_to_identical_cpu_results() {
	mut cpu := new_simulation(SimulationConfig{ bullet_capacity: 2 })
	mut fallback := new_simulation(SimulationConfig{
		compute_backend: .opencl
		bullet_capacity: 2
	})
	bullet := Bullet{
		alive: true
		position: Vec2{ x: 1, y: 2 }
		direction: 0.7
		speed: 0.2
	}
	cpu.bullets[0] = bullet
	fallback.bullets[0] = bullet
	cpu.dispatch_bullet_motion()
	fallback.dispatch_bullet_motion()
	assert fallback.active_compute_backend() == .cpu
	assert fallback.bullets[0].position.x == cpu.bullets[0].position.x
	assert fallback.bullets[0].position.y == cpu.bullets[0].position.y
	assert fallback.bullets[0].age == cpu.bullets[0].age
	assert cpu.compute_stats.fallback_batches == 0
	assert fallback.compute_stats.fallback_batches == 1
	assert fallback.compute_stats.bullet_checksum == cpu.compute_stats.bullet_checksum
	assert fallback.compute_stats.checksum() == cpu.compute_stats.checksum()
}

fn test_compute_session_explains_an_unlinked_opencl_fallback() {
	$if !opencl_compute ? {
		mut session := new_compute_session(.opencl)
		assert session.active_backend() == .cpu
		assert session.fallback().contains('-d opencl_compute')
		session.close()
	}
}

$if opencl_compute ? {
	fn test_opencl_session_matches_all_cpu_motion_kernels() {
		assert sizeof(OpenCLParticleSlot) == 24
		assert sizeof(OpenCLBulletSlot) == 36
		assert sizeof(OpenCLShotSlot) == 24
		assert sizeof(OpenCLEnemySlot) == 24
		assert sizeof(OpenCLParticleMotion) == 20
		assert sizeof(OpenCLBulletMotion) == 32
		assert sizeof(OpenCLShotMotion) == 20
		assert sizeof(OpenCLEnemyMotion) == 20
		assert sizeof(OpenCLCollisionPoint) == 16
		assert sizeof(OpenCLShotCollisionCandidate) == 8

		mut session := new_compute_session(.opencl)
		defer {
			session.close()
		}
		if session.active_backend() != .opencl {
			eprintln('OpenCL differential test skipped: ${session.fallback()}')
			return
		}

		particles := ParticleMotionSoa{
			source_indices: [0, 3]
			angles: [f32(6.27), -0.02]
			depths: [f32(2), -1]
			velocity_x: [f32(0.04), -0.2]
			velocity_y: [f32(-0.5), 0.25]
			lives: [2, 1]
		}
		mut expected_particles := particles.deep_clone()
		mut actual_particles := particles.deep_clone()
		assert cpu_step_particle_motion(mut expected_particles)
		assert session.step_particles(mut actual_particles)
		assert compare_particle_motion(expected_particles, actual_particles, 0.00001).matches()

		bullets := BulletMotionSoa{
			source_indices: [2, 5]
			angles: [f32(6.27), 0.01]
			depths: [f32(4), -2]
			directions: [f32(0.4), -0.8]
			speeds: [f32(0.25), 0.055]
			x_reverse: [f32(-1), 1]
			speed_ranks: [f32(1.2), 0.9]
			movement_scales: [f32(4), 3.5]
			ages: [7, 12]
		}
		mut expected_bullets := bullets.deep_clone()
		mut actual_bullets := bullets.deep_clone()
		assert cpu_step_bullet_motion(mut expected_bullets)
		assert session.step_bullets(mut actual_bullets)
		assert compare_bullet_motion(expected_bullets, actual_bullets, 0.00001).matches()

		shots := ShotMotionSoa{
			source_indices: [1, 4]
			angles: [f32(6.1), 0.1]
			depths: [f32(2), -3]
			directions: [f32(-0.3), 1.2]
			ranges: [f32(5), 1]
			ages: [4, 9]
		}
		mut expected_shots := shots.deep_clone()
		mut actual_shots := shots.deep_clone()
		assert cpu_step_shot_motion(mut expected_shots)
		assert session.step_shots(mut actual_shots)
		assert compare_shot_motion(expected_shots, actual_shots, 0.00001).matches()

		enemies := EnemyMotionSoa{
			source_indices: [1, 2]
			angles: [f32(6.2), -0.1]
			depths: [f32(8), 4]
			angle_steps: [f32(0.2), -0.15]
			depth_steps: [f32(-0.4), 0.05]
			ages: [13, 21]
		}
		mut expected_enemies := enemies.deep_clone()
		mut actual_enemies := enemies.deep_clone()
		assert cpu_step_enemy_motion(mut expected_enemies)
		assert session.step_enemies(mut actual_enemies)
		assert compare_enemy_motion(expected_enemies, actual_enemies, 0.00001).matches()
	}

	fn test_opencl_generates_stable_shot_enemy_candidates() ! {
		mut compute := new_opencl_compute() or {
			eprintln('OpenCL collision candidate test skipped: ${err}')
			return
		}
		defer {
			compute.close()
		}
		mut shots := []Shot{len: 5}
		shots[1] = Shot{
			alive: true
			position: Vec2{ x: 0.02, y: 5 }
		}
		shots[2] = Shot{
			alive: true
			charging: true
			position: Vec2{ x: 0.04, y: 5 }
		}
		shots[4] = Shot{
			alive: true
			position: Vec2{ x: 0.08, y: 5.2 }
		}
		mut enemies := []Enemy{len: 4}
		enemies[0] = Enemy{
			alive: true
			position: Vec2{ x: 6.25, y: 5.7 }
		}
		enemies[2] = Enemy{
			alive: true
			position: Vec2{ x: 0.1, y: 5.79 }
		}
		enemies[3] = Enemy{
			alive: true
			position: Vec2{ x: 0.08, y: 6.0 }
		}
		expected := shot_enemy_collision_candidates(shots, enemies)
		batch := compute.shot_enemy_candidates(shots, enemies)!
		actual := batch.candidates
		assert actual == expected
		assert actual.len == 6
		assert batch.active_shots == 2
		assert batch.active_targets == 3
		assert batch.tested_pairs == 6
		assert compute.collision_shot_slots.count == shots.len
		assert compute.collision_shots.count == 2
		assert compute.collision_target_slots.count == enemies.len
		assert compute.collision_targets.count == 3
		assert compute.active_flags_a.count == 6
		assert compute.active_flags_b.count == 6
		assert compute.collision_candidate_buffer.count == 6
	}

	fn test_opencl_generates_stable_shot_bullet_candidates() ! {
		mut compute := new_opencl_compute() or {
			eprintln('OpenCL shot/bullet candidate test skipped: ${err}')
			return
		}
		defer {
			compute.close()
		}
		mut shots := []Shot{len: 5}
		shots[0] = Shot{
			alive: true
			position: Vec2{ x: 0.02, y: 5 }
		}
		shots[2] = Shot{
			alive: true
			star_shell: true
			position: Vec2{ x: 0.02, y: 5 }
		}
		shots[3] = Shot{
			alive: true
			charged: true
			charging: true
			position: Vec2{ x: 0.02, y: 5 }
		}
		shots[4] = Shot{
			alive: true
			charged: true
			position: Vec2{ x: 0.08, y: 5.2 }
		}
		mut bullets := []Bullet{len: 4}
		bullets[0] = Bullet{
			alive: true
			position: Vec2{ x: 6.25, y: 5.4 }
		}
		bullets[2] = Bullet{
			alive: true
			position: Vec2{ x: 0.14, y: 5.44 }
		}
		bullets[3] = Bullet{
			alive: true
			position: Vec2{ x: 0.08, y: 5.65 }
		}
		expected := shot_bullet_collision_candidates(shots, bullets)
		batch := compute.shot_bullet_candidates(shots, bullets)!
		actual := batch.candidates
		assert actual == expected
		assert actual.len == 3
		assert batch.active_shots == 1
		assert batch.active_targets == 3
		assert batch.tested_pairs == 3
		assert compute.collision_shot_slots.count == shots.len
		assert compute.collision_shots.count == 1
		assert compute.collision_target_slots.count == bullets.len
		assert compute.collision_targets.count == 3
		// Scan buffers retain the largest slot count used earlier in the batch.
		assert compute.active_flags_a.count == shots.len
		assert compute.active_flags_b.count == shots.len
		assert compute.collision_candidate_buffer.count == 3
	}

	fn test_opencl_live_collision_candidate_validation_is_observational() {
		mut session := new_compute_session(.opencl)
		defer {
			session.close()
		}
		if session.active_backend() != .opencl {
			eprintln('OpenCL live collision candidate test skipped: ${session.fallback()}')
			return
		}
		mut simulation := new_simulation(SimulationConfig{
			compute_backend: .opencl
			shot_capacity: 3
			enemy_capacity: 3
			collisions: true
		})
		simulation.attach_compute_session(session)
		simulation.shots[1] = Shot{
			alive: true
			position: Vec2{ x: 0.02, y: 5 }
		}
		simulation.enemies[0] = Enemy{
			alive: true
			position: Vec2{ x: 6.25, y: 5.7 }
		}
		simulation.enemies[2] = Enemy{
			alive: true
			position: Vec2{ x: 2, y: 5 }
		}
		before_shots := simulation.shots.clone()
		before_enemies := simulation.enemies.clone()
		enemy_candidates := simulation.resolved_shot_enemy_candidates()
		bullet_candidates := simulation.resolved_shot_bullet_candidates()

		assert simulation.compute_stats.collision_candidate_batches == 2
		assert simulation.compute_stats.collision_candidate_items == 2
		assert simulation.compute_stats.collision_candidate_mismatched_batches == 0
		assert simulation.compute_stats.collision_candidate_mismatches == 0
		assert simulation.compute_stats.collision_active_shots == 1
		assert simulation.compute_stats.collision_active_targets == 2
		assert simulation.compute_stats.collision_tested_pairs == 2
		assert enemy_candidates == [
			ShotCollisionCandidate{ shot_index: 1, target_index: 0 },
			ShotCollisionCandidate{ shot_index: 1, target_index: 2 },
		]
		assert bullet_candidates.len == 0
		assert simulation.shots == before_shots
		assert simulation.enemies == before_enemies
	}

	fn test_opencl_validated_candidates_preserve_ordered_collision_results() {
		mut session := new_compute_session(.opencl)
		defer {
			session.close()
		}
		if session.active_backend() != .opencl {
			eprintln('OpenCL collision consumption test skipped: ${session.fallback()}')
			return
		}
		config := SimulationConfig{
			shot_capacity: 3
			bullet_capacity: 4
			enemy_capacity: 3
			particle_capacity: 64
			collisions: true
		}
		mut cpu := new_simulation(config)
		mut opencl := new_simulation(SimulationConfig{
			...config
			compute_backend: .opencl
		})
		opencl.attach_compute_session(session)
		shot := Shot{
			alive: true
			charged: true
			star_shell: true
			position: Vec2{ x: 0.02, y: 5 }
			range: 10
		}
		bullet := Bullet{
			alive: true
			position: Vec2{ x: 6.25, y: 5.75 }
		}
		enemy := Enemy{
			alive: true
			position: Vec2{ x: 0.08, y: 5.75 }
			health: 1
		}
		cpu.shots[1] = shot
		opencl.shots[1] = shot
		cpu.bullets[2] = bullet
		opencl.bullets[2] = bullet
		cpu.enemies[0] = enemy
		opencl.enemies[0] = enemy

		cpu.update_shots()
		opencl.update_shots()

		assert opencl.compute_stats.collision_candidate_batches == 2
		assert opencl.compute_stats.collision_candidate_items == 2
		assert opencl.compute_stats.collision_candidate_mismatched_batches == 0
		assert opencl.compute_stats.collision_active_shots == 2
		assert opencl.compute_stats.collision_active_targets == 2
		assert opencl.compute_stats.collision_tested_pairs == 2
		assert opencl.bullets_cleared == 0
		assert opencl.destroyed_enemies == 1
		assert opencl.checksum() == cpu.checksum()
		assert opencl.shots == cpu.shots
		assert opencl.bullets == cpu.bullets
		assert opencl.enemies == cpu.enemies
		assert opencl.particles == cpu.particles
	}

	fn test_opencl_dispatch_keeps_gameplay_state_bit_exact() {
		mut session := new_compute_session(.opencl)
		defer {
			session.close()
		}
		if session.active_backend() != .opencl {
			eprintln('OpenCL dispatch test skipped: ${session.fallback()}')
			return
		}
		mut cpu := new_simulation(SimulationConfig{ shot_capacity: 2 })
		mut opencl := new_simulation(SimulationConfig{
			compute_backend: .opencl
			shot_capacity: 2
		})
		shot := Shot{
			alive: true
			position: Vec2{ x: 0.1, y: -3 }
			direction: 1.2
			range: 4
			age: 9
		}
		cpu.shots[0] = shot
		opencl.shots[0] = shot
		opencl.attach_compute_session(session)
		cpu.dispatch_shot_motion()
		opencl.dispatch_shot_motion()
		assert opencl.active_compute_backend() == .opencl
		assert opencl.shots[0].position.x == cpu.shots[0].position.x
		assert opencl.shots[0].position.y == cpu.shots[0].position.y
		assert opencl.shots[0].range == cpu.shots[0].range
		assert opencl.shots[0].age == cpu.shots[0].age
		assert opencl.compute_stats.shot_checksum == cpu.compute_stats.shot_checksum
		assert opencl.compute_stats.verified_batches == 1
	}

	fn test_opencl_motion_helper_reuses_and_grows_typed_buffers() ! {
		mut compute := new_opencl_compute() or {
			eprintln('OpenCL buffer lifecycle test skipped: ${err}')
			return
		}
		defer {
			compute.close()
		}

		mut one := ParticleMotionSoa{
			source_indices: [0]
			angles: [f32(0.1)]
			depths: [f32(1)]
			velocity_x: [f32(0.01)]
			velocity_y: [f32(-0.02)]
			lives: [3]
		}
		compute.step_particles(mut one)!
		first_handle := compute.particle_buffer.handle
		assert !isnil(first_handle)
		assert compute.particle_buffer.count == 1

		compute.step_particles(mut one)!
		assert compute.particle_buffer.handle == first_handle

		mut three := ParticleMotionSoa{
			source_indices: [0, 1, 2]
			angles: [f32(0.1), 0.2, 0.3]
			depths: [f32(1), 2, 3]
			velocity_x: [f32(0.01), 0.02, 0.03]
			velocity_y: [f32(-0.02), -0.03, -0.04]
			lives: [3, 4, 5]
		}
		compute.step_particles(mut three)!
		assert compute.particle_buffer.count == 3
	}

	fn test_opencl_compacts_particle_pool_in_stable_order() ! {
		mut compute := new_opencl_compute() or {
			eprintln('OpenCL particle compaction test skipped: ${err}')
			return
		}
		defer {
			compute.close()
		}

		empty := compute.compact_and_step_particles([]Particle{len: 5})!
		assert empty.len() == 0

		mut simulation := new_simulation(SimulationConfig{ particle_capacity: 7 })
		simulation.particles[1] = Particle{
			alive: true
			position: Vec2{ x: 6.27, y: 2 }
			velocity: Vec2{ x: 0.04, y: -0.5 }
			life: 2
		}
		simulation.particles[3] = Particle{
			alive: true
			position: Vec2{ x: 0.3, y: -1 }
			velocity: Vec2{ x: -0.1, y: 0.2 }
			life: 5
		}
		simulation.particles[6] = Particle{
			alive: true
			position: Vec2{ x: 2.4, y: 8 }
			velocity: Vec2{ x: 0.2, y: -0.3 }
			life: 9
		}
		mut expected := simulation.particle_motion_snapshot()
		assert cpu_step_particle_motion(mut expected)
		actual := compute.compact_and_step_particles(simulation.particles)!

		assert actual.source_indices == [1, 3, 6]
		assert compare_particle_motion(expected, actual, 0.00001).matches()
		assert compute.particle_slots.count == 7
		assert compute.active_flags_a.count == 7
		assert compute.active_flags_b.count == 7
		assert compute.particle_indices.count == 7
	}

	fn test_opencl_compacts_bullet_pool_in_stable_order() ! {
		mut compute := new_opencl_compute() or {
			eprintln('OpenCL bullet compaction test skipped: ${err}')
			return
		}
		defer {
			compute.close()
		}

		empty := compute.compact_and_step_bullets([]Bullet{len: 3}, 4)!
		assert empty.len() == 0
		mut simulation := new_simulation(SimulationConfig{ bullet_capacity: 7 })
		simulation.ship.speed = 0.8
		simulation.bullets[0] = Bullet{
			alive: true
			position: Vec2{ x: 6.27, y: 4 }
			direction: 0.4
			speed: 0.25
			x_reverse: -1
			age: 7
		}
		simulation.bullets[4] = Bullet{
			alive: true
			position: Vec2{ x: 0.1, y: -2 }
			direction: -0.8
			speed: 0.055
			x_reverse: 1
			age: 12
		}
		simulation.bullets[6] = Bullet{
			alive: true
			position: Vec2{ x: 1.7, y: 9 }
			direction: 1.2
			speed: 0.09
			x_reverse: -1
			age: 20
		}
		mut expected := simulation.bullet_motion_snapshot()
		assert cpu_step_bullet_motion(mut expected)
		actual := compute.compact_and_step_bullets(simulation.bullets, simulation.ship.speed * 5)!

		assert actual.source_indices == [0, 4, 6]
		assert compare_bullet_motion(expected, actual, 0.00001).matches()
		assert compute.bullet_slots.count == 7
		assert compute.bullet_indices.count == 7
	}

	fn test_opencl_compacts_only_released_shots_in_stable_order() ! {
		mut compute := new_opencl_compute() or {
			eprintln('OpenCL shot compaction test skipped: ${err}')
			return
		}
		defer {
			compute.close()
		}

		empty := compute.compact_and_step_shots([]Shot{len: 3})!
		assert empty.len() == 0
		mut simulation := new_simulation(SimulationConfig{ shot_capacity: 7 })
		simulation.shots[0] = Shot{
			alive: true
			charging: true
			position: Vec2{ x: 5, y: 6 }
			range: 12
		}
		simulation.shots[2] = Shot{
			alive: true
			position: Vec2{ x: 6.1, y: 2 }
			direction: -0.3
			range: 5
			age: 4
		}
		simulation.shots[5] = Shot{
			alive: true
			position: Vec2{ x: 0.1, y: -3 }
			direction: 1.2
			range: 4
			age: 9
		}
		mut expected := simulation.shot_motion_snapshot()
		assert cpu_step_shot_motion(mut expected)
		actual := compute.compact_and_step_shots(simulation.shots)!

		assert actual.source_indices == [2, 5]
		assert compare_shot_motion(expected, actual, 0.00001).matches()
		assert compute.shot_slots.count == 7
		assert compute.shot_indices.count == 7
	}

	fn test_opencl_compacts_prepared_enemies_in_stable_order() ! {
		mut compute := new_opencl_compute() or {
			eprintln('OpenCL enemy compaction test skipped: ${err}')
			return
		}
		defer {
			compute.close()
		}

		empty := compute.compact_and_step_enemies(new_enemy_motion_slots(3))!
		assert empty.len() == 0
		mut slots := new_enemy_motion_slots(7)
		slots.set(1, Enemy{
			alive: true
			position: Vec2{ x: 6.2, y: 8 }
			turn_speed: 0.2
			age: 12
		}, -0.4)
		slots.set(5, Enemy{
			alive: true
			position: Vec2{ x: 0.3, y: 4 }
			turn_speed: -0.15
			age: 20
		}, 0.05)
		mut expected := slots.compact()
		assert cpu_step_enemy_motion(mut expected)
		actual := compute.compact_and_step_enemies(slots)!

		assert actual.source_indices == [1, 5]
		assert compare_enemy_motion(expected, actual, 0.00001).matches()
		assert compute.enemy_slots.count == 7
		assert compute.enemy_indices.count == 7
	}
}

fn test_compute_trace_checksum_detects_post_kernel_field_changes() {
	mut particles := ParticleMotionSoa{
		source_indices: [2]
		angles: [f32(1)]
		depths: [f32(3)]
		velocity_x: [f32(0.1)]
		velocity_y: [f32(-0.2)]
		lives: [8]
	}
	checksum := particle_motion_checksum(0, particles)
	particles.depths[0] += 0.001
	assert particle_motion_checksum(0, particles) != checksum
}

fn test_compute_differential_reports_tolerance_and_layout_mismatches() {
	reference := ParticleMotionSoa{
		source_indices: [1]
		angles: [f32(2)]
		depths: [f32(3)]
		velocity_x: [f32(0.1)]
		velocity_y: [f32(-0.2)]
		lives: [7]
	}
	mut candidate := ParticleMotionSoa{
		...reference
		source_indices: reference.source_indices.clone()
		depths: [f32(3.0005)]
	}
	within := compare_particle_motion(reference, candidate, 0.001)
	assert within.matches()
	assert within.max_error > 0
	outside := compare_particle_motion(reference, candidate, 0.0001)
	assert !outside.matches()
	assert outside.mismatches == 1
	candidate.source_indices[0] = 2
	layout := compare_particle_motion(reference, candidate, 0.001)
	assert !layout.matches()
	assert layout.mismatches == 1
}

fn test_all_compute_differential_helpers_accept_identical_empty_batches() {
	assert compare_particle_motion(ParticleMotionSoa{}, ParticleMotionSoa{}, 0).matches()
	assert compare_bullet_motion(BulletMotionSoa{}, BulletMotionSoa{}, 0).matches()
	assert compare_shot_motion(ShotMotionSoa{}, ShotMotionSoa{}, 0).matches()
	assert compare_enemy_motion(EnemyMotionSoa{}, EnemyMotionSoa{}, 0).matches()
}
