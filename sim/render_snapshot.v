module sim

import math

const enemy_shape_code_scale = f32(1.0 / 2_097_152.0)
const enemy_shape_tier_stride = f32(0.125)
const enemy_damaged_code_offset = 100_000
const particle_payload_scale = f32(0.000002)
const particle_reflection_heading_offset = f32(10_000)
const multiplier_large_label_offset = f32(128)
const multiplier_list_slot_kind_scale = f32(0.01)
const multiplier_visible_list_slots = 8
const fragment_angle_bins = 64
const fragment_dimension_bins = 64
const fragment_width_limit = f32(4.5)
const fragment_height_limit = f32(14)

// RenderInstance is the renderer/compute boundary. Its sixteen contiguous f32
// fields can later be produced into shared storage by an OpenCL kernel. The
// first three vec4s carry placement and a complete tunnel-local frame; the
// fourth is the object's source-order rotation quaternion.
pub struct RenderInstance {
pub:
	angle          f32
	depth          f32
	kind           f32
	heading        f32
	scale          f32 = 1
	surface_radius f32
	tangent_angle  f32
	tangent_radius f32
	lateral_angle  f32
	lateral_radius f32
	normal_angle   f32
	normal_radius  f32
	rotation_x     f32
	rotation_y     f32
	rotation_z     f32
	rotation_w     f32 = 1
}

struct RenderOrientation {
	x f32
	y f32
	z f32
	w f32 = 1
}

fn render_axis_rotation(x f32, y f32, z f32, angle f32) RenderOrientation {
	length := f32(math.sqrt(f64(x * x + y * y + z * z)))
	if length <= 0.00001 {
		return RenderOrientation{}
	}
	half := angle * 0.5
	scale := f32(math.sin(half)) / length
	return RenderOrientation{
		x: x * scale
		y: y * scale
		z: z * scale
		w: f32(math.cos(half))
	}
}

fn (left RenderOrientation) multiply(right RenderOrientation) RenderOrientation {
	return RenderOrientation{
		x: left.w * right.x + left.x * right.w + left.y * right.z - left.z * right.y
		y: left.w * right.y - left.x * right.z + left.y * right.w + left.z * right.x
		z: left.w * right.z + left.x * right.y - left.y * right.x + left.z * right.w
		w: left.w * right.w - left.x * right.x - left.y * right.y - left.z * right.z
	}
}

fn render_y_rotation(angle f32) RenderOrientation {
	return render_axis_rotation(0, 1, 0, angle)
}

fn render_z_rotation(angle f32) RenderOrientation {
	return render_axis_rotation(0, 0, 1, angle)
}

// RenderScales names every independently sizeable procedural visual. These
// names deliberately mirror runtime/object_sizes.v and the calibration labels.
pub struct RenderScales {
pub:
	player            f32 = 1
	player_shot       f32 = 1
	star_shot         f32 = 1
	charged_shot      f32 = 1
	enemy_small       f32 = 1
	enemy_middle      f32 = 1
	enemy_boss        f32 = 1
	boss_bit          f32 = 1
	bullet_triangle   f32 = 1
	bullet_square     f32 = 1
	bullet_bar        f32 = 1
	particle_spark    f32 = 1
	particle_jet      f32 = 1
	particle_star     f32 = 1
	particle_fragment f32 = 1
}

// RenderEntitySoa is the CPU compute-output boundary. Keeping each field in a
// contiguous array permits a future OpenCL kernel to produce or compact fields
// independently; pack_render_instances is the current Vulkan staging step.
pub struct RenderEntitySoa {
pub mut:
	angles         []f32
	depths         []f32
	kinds          []f32
	headings       []f32
	scales         []f32
	surface_radii  []f32
	tangent_angles []f32
	tangent_radii  []f32
	lateral_angles []f32
	lateral_radii  []f32
	normal_angles  []f32
	normal_radii   []f32
	rotation_xs    []f32
	rotation_ys    []f32
	rotation_zs    []f32
	rotation_ws    []f32
}

fn (mut entities RenderEntitySoa) append(angle f32, depth f32, kind f32, heading f32) {
	entities.append_scaled(angle, depth, kind, heading, 1)
}

fn (mut entities RenderEntitySoa) append_scaled(angle f32, depth f32, kind f32, heading f32,
	scale f32) {
	entities.append_scaled_oriented(angle, depth, kind, heading, scale, RenderOrientation{})
}

fn (mut entities RenderEntitySoa) append_scaled_oriented(angle f32, depth f32, kind f32,
	heading f32, scale f32, orientation RenderOrientation) {
	entities.angles << angle
	entities.depths << depth
	entities.kinds << kind
	entities.headings << heading
	entities.scales << scale
	entities.surface_radii << 0
	entities.tangent_angles << 0
	entities.tangent_radii << 0
	entities.lateral_angles << 0
	entities.lateral_radii << 0
	entities.normal_angles << 0
	entities.normal_radii << 0
	entities.rotation_xs << orientation.x
	entities.rotation_ys << orientation.y
	entities.rotation_zs << orientation.z
	entities.rotation_ws << orientation.w
}

fn (mut entities RenderEntitySoa) append_surface_scaled(angle f32, depth f32, kind f32,
	heading f32, scale f32, surface_radius f32, tangent_angle f32, tangent_radius f32,
	lateral_angle f32, lateral_radius f32, normal_angle f32, normal_radius f32,
	orientation RenderOrientation) {
	entities.angles << angle
	entities.depths << depth
	entities.kinds << kind
	entities.headings << heading
	entities.scales << scale
	entities.surface_radii << surface_radius
	entities.tangent_angles << tangent_angle
	entities.tangent_radii << tangent_radius
	entities.lateral_angles << lateral_angle
	entities.lateral_radii << lateral_radius
	entities.normal_angles << normal_angle
	entities.normal_radii << normal_radius
	entities.rotation_xs << orientation.x
	entities.rotation_ys << orientation.y
	entities.rotation_zs << orientation.z
	entities.rotation_ws << orientation.w
}

pub fn (entities &RenderEntitySoa) len() int {
	return entities.angles.len
}

pub fn (entities &RenderEntitySoa) valid() bool {
	return entities.depths.len == entities.angles.len && entities.kinds.len == entities.angles.len
		&& entities.headings.len == entities.angles.len && entities.scales.len == entities.angles.len
		&& entities.surface_radii.len == entities.angles.len
		&& entities.tangent_angles.len == entities.angles.len
		&& entities.tangent_radii.len == entities.angles.len
		&& entities.lateral_angles.len == entities.angles.len
		&& entities.lateral_radii.len == entities.angles.len
		&& entities.normal_angles.len == entities.angles.len
		&& entities.normal_radii.len == entities.angles.len
		&& entities.rotation_xs.len == entities.angles.len
		&& entities.rotation_ys.len == entities.angles.len
		&& entities.rotation_zs.len == entities.angles.len
		&& entities.rotation_ws.len == entities.angles.len
}

fn enemy_render_kind(kind int, shape_seed int) f32 {
	return enemy_render_kind_with_damage(kind, shape_seed, false)
}

fn enemy_render_kind_with_damage(kind int, shape_seed int, damaged bool) f32 {
	tier := int_max(0, int_min(2, kind))
	seed := int_max(0, shape_seed % 99_999)
	code := seed + if damaged { enemy_damaged_code_offset } else { 0 }
	return f32(3) + f32(tier) * enemy_shape_tier_stride + f32(code) * enemy_shape_code_scale
}

struct EnemyRenderCode {
	tier    int
	seed    int
	damaged bool
}

fn decode_enemy_render_kind(value f32) EnemyRenderCode {
	tier := int_max(0, int_min(2, int((value - 3) / enemy_shape_tier_stride)))
	base := f32(3) + f32(tier) * enemy_shape_tier_stride
	packed := int((value - base) / enemy_shape_code_scale + 0.5)
	return EnemyRenderCode{
		tier: tier
		seed: packed % enemy_damaged_code_offset
		damaged: packed >= enemy_damaged_code_offset
	}
}

fn particle_render_kind(particle Particle) f32 {
	life_ratio := if particle.initial_life > 0 {
		clamp_f32(f32(particle.life) / f32(particle.initial_life), 0, 1)
	} else {
		f32(0)
	}
	life_bin := int(life_ratio * 15 + 0.5)
	height_bin := int(clamp_f32((particle.height + 64) / 0.55, 0, 127) + 0.5)
	luminosity_bin := int(clamp_f32(particle.luminosity, 0, 1) * 15 + 0.5)
	tier := int_max(0, int_min(2, particle.visual_tier))
	payload := tier * 32768 + height_bin * 256 + life_bin * 16 + luminosity_bin
	return f32(6) + f32(int(particle.kind)) * 0.25 + f32(payload) * particle_payload_scale
}

fn particle_render_heading(particle Particle, reflected bool) f32 {
	mut heading := if particle.kind == .fragment {
		f32(particle_fragment_payload(particle))
	} else {
		f32(math.atan2(particle.velocity.x, particle.velocity.y))
	}
	if particle.kind == .jet {
		// A jet's narrow end is the nozzle-facing end of the mesh. Particle
		// velocity points down the exhaust trail, so face the mesh back toward
		// its emitter instead of putting the broad plume over the ship's nose.
		heading = wrap_angle(heading + f32(math.pi))
	}
	return heading + if reflected { particle_reflection_heading_offset } else { f32(0) }
}

struct ParticleFragmentCode {
	spin_bin           int
	secondary_spin_bin int
	width_bin          int
	height_bin         int
}

fn particle_fragment_payload(particle Particle) int {
	spin_bin := particle_fragment_angle_bin(particle.spin)
	secondary_spin_bin := particle_fragment_angle_bin(particle.secondary_spin)
	width_bin := int(clamp_f32(particle.fragment_width * particle.scale / fragment_width_limit, 0, 1) * f32(fragment_dimension_bins - 1) + 0.5)
	height_bin := int(clamp_f32(particle.fragment_height * particle.scale / fragment_height_limit, 0, 1) * f32(fragment_dimension_bins - 1) + 0.5)
	return int(u32(spin_bin) | (u32(secondary_spin_bin) << 6) | (u32(width_bin) << 12) | (u32(height_bin) << 18))
}

fn particle_fragment_angle_bin(angle f32) int {
	return int(wrap_angle(angle) / f32(math.pi * 2) * fragment_angle_bins + 0.5) % fragment_angle_bins
}

fn decode_particle_fragment_payload(payload int) ParticleFragmentCode {
	return ParticleFragmentCode{
		spin_bin: payload & 63
		secondary_spin_bin: (payload >> 6) & 63
		width_bin: (payload >> 12) & 63
		height_bin: (payload >> 18) & 63
	}
}

fn multiplier_popup_payload(popup MultiplierPopup) f32 {
	size_marker := if popup.large_label { multiplier_large_label_offset } else { f32(0) }
	return f32(popup.multiplier) + size_marker + popup.alpha
}

fn multiplier_render_kind(slot int) f32 {
	return 20 + f32(slot) * multiplier_list_slot_kind_scale
}

fn multiplier_render_slot(kind f32) int {
	return int(math.round((kind - 20) / multiplier_list_slot_kind_scale))
}

fn enemy_surface_clearance(kind int) f32 {
	// Source-space half-extents implied by the shader's fixed 4.62 projection
	// scale. World-unit clearance stays valid at every output resolution.
	return match int_max(0, int_min(2, kind)) {
		0 { f32(0.12) }
		1 { f32(0.27) }
		else { f32(0.50) }
	}
}

fn player_jet_particle(particle Particle) bool {
	return particle.kind == .jet && particle.visual_tier == 0
}

fn (simulation &Simulation) particle_course_depth(particle Particle) f32 {
	if player_jet_particle(particle) {
		// Player jets are spawned before the shared particle-motion pass. Present
		// them one tick earlier, then account for the longer modern-resolution
		// hull. The narrow plume tip now starts just beyond the ship's rear edge
		// instead of appearing through the middle of the sprite.
		return particle.position.y + simulation.ship.speed - particle.velocity.y + ship_render_depth_offset - ship_exhaust_render_depth_clearance
	}
	return particle.position.y
}

fn particle_surface_offset(particle Particle, reflected bool, player_clearance f32) f32 {
	if reflected {
		return particle.height * course_render_height_scale
	}
	mut offset := -particle.height * course_render_height_scale
	if player_jet_particle(particle) {
		// The player sprite is lifted farther from the panel than source-space
		// geometry so its modern-resolution footprint remains inside the tunnel.
		// Keep its exhaust at that plane, then retain the source z=1 lift.
		offset -= player_clearance
	}
	return offset
}

pub fn (simulation &Simulation) render_entity_soa() RenderEntitySoa {
	return simulation.render_entity_soa_for_camera_with_scales(simulation.camera_angle(), RenderScales{})
}

pub fn (simulation &Simulation) render_entity_soa_for_camera(camera_angle f32) RenderEntitySoa {
	return simulation.render_entity_soa_for_camera_with_scales(camera_angle, RenderScales{})
}

pub fn (simulation &Simulation) render_entity_soa_for_camera_with_scales(camera_angle f32,
	scales RenderScales) RenderEntitySoa {
	mut entities := RenderEntitySoa{
		angles: []f32{cap: 1024}
		depths: []f32{cap: 1024}
		kinds: []f32{cap: 1024}
		headings: []f32{cap: 1024}
		scales: []f32{cap: 1024}
		surface_radii: []f32{cap: 1024}
		tangent_angles: []f32{cap: 1024}
		tangent_radii: []f32{cap: 1024}
		lateral_angles: []f32{cap: 1024}
		lateral_radii: []f32{cap: 1024}
		normal_angles: []f32{cap: 1024}
		normal_radii: []f32{cap: 1024}
		rotation_xs: []f32{cap: 1024}
		rotation_ys: []f32{cap: 1024}
		rotation_zs: []f32{cap: 1024}
		rotation_ws: []f32{cap: 1024}
	}
	player_clearance := player_ship_surface_clearance(scales.player)
	ship_hidden := simulation.ship.lifecycle_counter < -228
		|| (simulation.ship.lifecycle_counter < 0
			&& (-simulation.ship.lifecycle_counter % 32) < 16)
	if !ship_hidden {
		ship_depth := simulation.ship.relative_depth + ship_render_depth_offset
		ship_angle, ship_radius, ship_tangent_angle, ship_tangent_radius, ship_lateral_angle, ship_lateral_radius, ship_normal_angle, ship_normal_radius := simulation.actor_surface_render_pose(simulation.ship.angle, ship_depth, camera_angle, -player_clearance)
		entities.append_surface_scaled(ship_angle, ship_depth, 1, simulation.ship.bank, scales.player, ship_radius, ship_tangent_angle, ship_tangent_radius, ship_lateral_angle, ship_lateral_radius, ship_normal_angle, ship_normal_radius, render_z_rotation(-simulation.ship.bank))
	}
	for bullet in simulation.bullets {
		if !bullet.alive {
			continue
		}
		scale_marker := if bullet.visual_scale > 1.1 { f32(0.5) } else { f32(0) }
		mut kind := f32(7 + bullet.visual_shape) + scale_marker
		if bullet.disappear_ticks > 0 {
			fade := 1.0 - f32(bullet.disappear_ticks) / 45.0
			kind += 1.0 + fade * 0.49
		}
		spin := f32(bullet.age) * f32(math.pi) * 6.0 / 180.0
		// Enemy bullets use angular/depth tunnel coordinates. Convert those
		// coordinates through the generated course here;
		// leaving them raw made curved slices move away from their projectiles.
		clearance := -0.06 * bullet.visual_scale
		angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(bullet.position.x, bullet.position.y, camera_angle, clearance)
		bullet_scale := match bullet.visual_shape / 2 {
			0 { scales.bullet_triangle }
			1 { scales.bullet_square }
			else { scales.bullet_bar }
		}
		bullet_direction := bullet.direction * bullet.x_reverse
		// BulletActor.draw applies Y(direction) then Z(spin). Keep that order
		// instead of adding the two angles as if both used the same axis.
		orientation := render_y_rotation(bullet_direction).multiply(render_z_rotation(spin))
		entities.append_surface_scaled(angle, bullet.position.y, kind, bullet_direction, bullet_scale, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, orientation)
	}
	for shot in simulation.shots {
		if !shot.alive {
			continue
		}
		base_kind := if shot.star_shell { f32(2.25) } else { f32(2) }
		kind := if shot.charged {
			f32(5) + clamp_f32(shot.size / 13.6, 0, 1) * 0.49
		} else {
			base_kind + clamp_f32(shot.size, 0, 1) * 0.1
		}
		// Original ShotShape rotates another seven degrees on every simulation tick.
		spin := f32(shot.age) * f32(math.pi) * 7.0 / 180.0
		clearance := f32(-0.09)
		angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(shot.position.x, shot.position.y, camera_angle, clearance)
		shot_scale := if shot.charged {
			scales.charged_shot
		} else if shot.star_shell {
			scales.star_shot
		} else {
			scales.player_shot
		}
		// Shot.draw rotates about its unusual (0, 1, 10) axis before the axial
		// Z spin. Preserving both axes stops side shots from becoming flat turns.
		orientation := render_axis_rotation(0, 1, 10, shot.direction).multiply(render_z_rotation(spin))
		entities.append_surface_scaled(angle, shot.position.y, kind, shot.direction, shot_scale, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, orientation)
	}
	for enemy in simulation.enemies {
		if !enemy.alive {
			continue
		}
		spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
		kind := enemy_render_kind_with_damage(enemy.kind, spec.shape_seed, enemy.damaged)
		surface_clearance := enemy_surface_clearance(enemy.kind)
		angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(enemy.position.x, enemy.position.y, camera_angle, -surface_clearance)
		enemy_scale := match enemy.kind {
			0 { scales.enemy_small }
			1 { scales.enemy_middle }
			else { scales.enemy_boss }
		}
		// Enemy.draw and Ship.draw in the source both rotate by position.x - bank.
		// The shader's course basis already supplies position.x, so pass the same
		// positive bank convention used by the player rather than reversing it.
		entities.append_surface_scaled(angle, enemy.position.y, kind, enemy.turn_speed, enemy_scale, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, render_z_rotation(-enemy.turn_speed))
	}
	for enemy in simulation.passed_enemies {
		if !enemy.alive {
			continue
		}
		spec := simulation.enemy_spec_for(enemy.kind, enemy.spec_index)
		kind := enemy_render_kind(enemy.kind, spec.shape_seed)
		surface_clearance := enemy_surface_clearance(enemy.kind)
		angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(enemy.position.x, enemy.position.y, camera_angle, -surface_clearance)
		enemy_scale := match enemy.kind {
			0 { scales.enemy_small }
			1 { scales.enemy_middle }
			else { scales.enemy_boss }
		}
		entities.append_surface_scaled(angle, enemy.position.y, kind, enemy.turn_speed, enemy_scale, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, render_z_rotation(-enemy.turn_speed))
	}
	for bit in simulation.boss_bits() {
		angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(bit.position.x, bit.position.y, camera_angle, -0.2)
		entities.append_surface_scaled(angle, bit.position.y, 4.6, bit.rotation, scales.boss_bit, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, render_y_rotation(bit.rotation))
	}
	for particle in simulation.particles {
		if !particle.alive {
			continue
		}
		particle_scale := match particle.kind {
			.spark { scales.particle_spark }
			.jet { scales.particle_jet }
			.star { scales.particle_star }
			.fragment { scales.particle_fragment }
		}
		if particle.kind == .star {
			angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(particle.position.x, particle.position.y, camera_angle, -particle.height * course_render_height_scale)
			entities.append_surface_scaled(angle, particle.position.y, particle_render_kind(particle), particle_render_heading(particle, false), particle_scale, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, RenderOrientation{})
		} else if particle.kind in [.spark, .jet] {
			// The source always converts a particle's tunnel coordinates to world
			// space. `in_course` only controls whether it also draws the reflected
			// copy. Treating an out-of-course impact as raw screen coordinates made
			// its packed surface radius collapse to zero at the tunnel center.
			depth := simulation.particle_course_depth(particle)
			angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(particle.position.x, depth, camera_angle, particle_surface_offset(particle, false, player_clearance))
			entities.append_surface_scaled(angle, depth, particle_render_kind(particle), particle_render_heading(particle, false), particle_scale, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, RenderOrientation{})
		} else {
			orientation := render_z_rotation(particle.spin).multiply(render_y_rotation(particle.secondary_spin))
			entities.append_scaled_oriented(particle.position.x, particle.position.y, particle_render_kind(particle), particle_render_heading(particle, false), particle_scale, orientation)
		}
		if particle.in_course && particle.kind in [.spark, .jet] {
			reflection := Particle{
				...particle
				height: -particle.height
			}
			depth := simulation.particle_course_depth(particle)
			angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius := simulation.actor_surface_render_pose(reflection.position.x, depth, camera_angle, particle_surface_offset(particle, true, player_clearance))
			heading := particle_render_heading(reflection, false)
			entities.append_surface_scaled(angle, depth, particle_render_kind(reflection), heading + particle_reflection_heading_offset, particle_scale, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius, RenderOrientation{})
		}
	}
	// The pool cursor points at the newest popup and allocation walks backward.
	// Traverse circularly from there so new hits enter at the top while existing
	// labels move down a stable, non-overlapping screen-space list.
	mut multiplier_slot := 0
	for popup_offset in 0 .. simulation.multiplier_popups.len {
		popup_index := (simulation.multiplier_popup_cursor + popup_offset) % simulation.multiplier_popups.len
		popup := simulation.multiplier_popups[popup_index]
		if !popup.alive {
			continue
		}
		if multiplier_slot >= multiplier_visible_list_slots {
			break
		}
		// The integer payload is the label value; its fractional component is
		// the fading alpha. Kind 20 is reserved for floating letters.
		// The fractional kind payload now carries the scrolling-list slot; the
		// vertex shader owns final screen-space placement.
		entities.append(0, 0, multiplier_render_kind(multiplier_slot), multiplier_popup_payload(popup))
		multiplier_slot++
	}
	return entities
}

pub fn pack_render_instances(entities RenderEntitySoa) []RenderInstance {
	if !entities.valid() {
		return []
	}
	mut instances := []RenderInstance{len: entities.len()}
	for index in 0 .. entities.len() {
		instances[index] = RenderInstance{
			angle: entities.angles[index]
			depth: entities.depths[index]
			kind: entities.kinds[index]
			heading: entities.headings[index]
			scale: entities.scales[index]
			surface_radius: entities.surface_radii[index]
			tangent_angle: entities.tangent_angles[index]
			tangent_radius: entities.tangent_radii[index]
			lateral_angle: entities.lateral_angles[index]
			lateral_radius: entities.lateral_radii[index]
			normal_angle: entities.normal_angles[index]
			normal_radius: entities.normal_radii[index]
			rotation_x: entities.rotation_xs[index]
			rotation_y: entities.rotation_ys[index]
			rotation_z: entities.rotation_zs[index]
			rotation_w: entities.rotation_ws[index]
		}
	}
	return instances
}

pub fn (simulation &Simulation) render_instances() []RenderInstance {
	return pack_render_instances(simulation.render_entity_soa())
}

pub fn (simulation &Simulation) render_instances_for_camera(camera_angle f32) []RenderInstance {
	return pack_render_instances(simulation.render_entity_soa_for_camera(camera_angle))
}

pub fn (simulation &Simulation) render_instances_for_camera_with_scales(camera_angle f32,
	scales RenderScales) []RenderInstance {
	return pack_render_instances(simulation.render_entity_soa_for_camera_with_scales(camera_angle, scales))
}

pub fn flatten_render_instances(instances []RenderInstance, mut values []f32) {
	values.clear()
	for instance in instances {
		values << instance.angle
		values << instance.depth
		values << instance.kind
		values << instance.heading
		values << instance.scale
		values << instance.surface_radius
		values << instance.tangent_angle
		values << instance.tangent_radius
		values << instance.lateral_angle
		values << instance.lateral_radius
		values << instance.normal_angle
		values << instance.normal_radius
		values << instance.rotation_x
		values << instance.rotation_y
		values << instance.rotation_z
		values << instance.rotation_w
	}
}

pub fn render_snapshot_checksum(instances []RenderInstance) u64 {
	mut value := u64(14695981039346656037)
	value = fnv1a(value, u64(instances.len))
	for instance in instances {
		value = fnv1a(value, u64(f32_bits(instance.angle)))
		value = fnv1a(value, u64(f32_bits(instance.depth)))
		value = fnv1a(value, u64(f32_bits(instance.kind)))
		value = fnv1a(value, u64(f32_bits(instance.heading)))
		value = fnv1a(value, u64(f32_bits(instance.scale)))
		value = fnv1a(value, u64(f32_bits(instance.surface_radius)))
		value = fnv1a(value, u64(f32_bits(instance.tangent_angle)))
		value = fnv1a(value, u64(f32_bits(instance.tangent_radius)))
		value = fnv1a(value, u64(f32_bits(instance.lateral_angle)))
		value = fnv1a(value, u64(f32_bits(instance.lateral_radius)))
		value = fnv1a(value, u64(f32_bits(instance.normal_angle)))
		value = fnv1a(value, u64(f32_bits(instance.normal_radius)))
		value = fnv1a(value, u64(f32_bits(instance.rotation_x)))
		value = fnv1a(value, u64(f32_bits(instance.rotation_y)))
		value = fnv1a(value, u64(f32_bits(instance.rotation_z)))
		value = fnv1a(value, u64(f32_bits(instance.rotation_w)))
	}
	return value
}
