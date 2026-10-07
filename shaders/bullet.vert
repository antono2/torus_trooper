// Transforms bullet instances into tunnel-space geometry for rendering.
#version 450
#extension GL_GOOGLE_include_directive : require
#include "render_codes.glsl"

// Four vec4s keep the compute/Vulkan boundary aligned: placement and payload,
// scale plus forward sample, circumferential/radial samples, and the original
// source-order object rotation as a quaternion.
layout(location = 0) in vec4 instance_data;
layout(location = 1) in vec4 instance_surface;
layout(location = 2) in vec4 instance_frame;
layout(location = 3) in vec4 instance_rotation;

layout(push_constant) uniform Frame {
    float time;
    float aspect;
    float view_angle;
    layout(offset = 44) float tunnel_scale;
    layout(offset = 56) float depth_offset;
    layout(offset = 60) float zoom;
    layout(offset = 80) vec2 shake;
    layout(offset = 88) float camera_3d;
    layout(offset = 92) float eye_height;
    layout(offset = 96) float look_angle;
    layout(offset = 100) float look_depth;
    layout(offset = 104) float look_height;
    layout(offset = 108) float rotation;
    layout(offset = 124) float ship_surface_radius;
} frame;

layout(location = 0) out vec2 local_position;
layout(location = 1) flat out float instance_kind;
layout(location = 2) flat out float instance_payload;
layout(location = 3) flat out float instance_selected;

const vec2 corners[6] = vec2[](
    vec2(-1.0, -1.0), vec2( 1.0, -1.0), vec2( 1.0,  1.0),
    vec2(-1.0, -1.0), vec2( 1.0,  1.0), vec2(-1.0,  1.0)
);

const float tunnel_radius = 1.4175;
const float height_scale = 1.35 / 21.0;
const float depth_scale = 0.55;
const float particle_payload_scale = 0.000002;
const float particle_reflection_heading_offset = 10000.0;
const float enemy_shape_tier_stride = 0.125;
const float fragment_width_limit = 4.5;
const float fragment_height_limit = 14.0;
const int multiplier_large_label_offset = 128;
const float multiplier_list_slot_kind_scale = 0.01;
const float source_projection_near_depth = 2.2;
const float source_projection_near_scale = 2.1;
const float player_shot_depth_bias = 0.0075;
const float enemy_bullet_depth_bias = 0.0045;
const float calibration_visual_kind_base = 64.0;
const float calibration_label_kind_base = 96.0;

float calibration_visual_kind(int index) {
	const float kinds[16] = float[](
		1.0, 2.1, 2.35, 5.49, 3.00001, 3.12501, 3.25001, 4.6,
		7.0, 9.0, 11.0, 6.00051, 6.25051, 6.50051, 6.75051, 63.0
	);
	return kinds[clamp(index, 0, 15)];
}

int calibration_label_length(int index) {
	const int lengths[16] = int[](6, 11, 9, 12, 11, 12, 10, 8, 15, 13,
		10, 14, 12, 13, 17, 6);
	return lengths[clamp(index, 0, 15)];
}

float calibration_visual_base_size(int index) {
	const float sizes[16] = float[](0.030, 0.012, 0.012, 0.272,
		0.024, 0.056, 0.105, 0.030, 0.012, 0.012, 0.012, 0.019,
		0.019, 0.027, 0.019, tunnel_radius / (4.62 * 0.94));
	return sizes[clamp(index, 0, 15)];
}

float projected_depth(float view_depth) {
    return clamp(1.0 - 0.1 / max(view_depth, 0.1), 0.0, 1.0);
}

vec3 tube_position(float angle, float depth, float height) {
    float radius = tunnel_radius - height * height_scale;
    return vec3(-sin(angle) * radius * frame.tunnel_scale,
                cos(angle) * radius * frame.tunnel_scale,
                depth * depth_scale * frame.tunnel_scale);
}

vec2 replay_projection(vec3 point, out float view_depth) {
    vec3 eye = tube_position(frame.view_angle, frame.depth_offset,
                             frame.eye_height);
    vec3 target = tube_position(frame.look_angle, frame.look_depth,
                                frame.look_height);
    vec3 forward = normalize(target - eye);
    vec3 up_hint = vec3(sin(frame.rotation), -cos(frame.rotation), 0.0);
    vec3 right = normalize(cross(forward, up_hint));
    vec3 up = cross(right, forward);
    vec3 relative = point - eye;
    view_depth = dot(relative, forward);
    if (view_depth <= 0.05) return vec2(2.0);
    return vec2(dot(relative, right) / frame.aspect, dot(relative, up)) /
           (view_depth * frame.zoom) + frame.shake;
}

vec3 quaternion_rotate(vec4 quaternion, vec3 point) {
	float quaternion_length = length(quaternion);
	vec4 q = quaternion_length > 0.00001
		? quaternion / quaternion_length : vec4(0.0, 0.0, 0.0, 1.0);
	return point + 2.0 * cross(q.xyz, cross(q.xyz, point) + q.w * point);
}

void main() {
	float instance_scale = instance_surface.x;
	float instance_surface_radius = instance_surface.y;
	float instance_tangent_angle = instance_surface.z;
	float instance_tangent_radius = instance_surface.w;
	float instance_lateral_angle = instance_frame.x;
	float instance_lateral_radius = instance_frame.y;
	float instance_normal_angle = instance_frame.z;
	float instance_normal_radius = instance_frame.w;
	float raw_kind = instance_data.z;
	bool calibration_visual = raw_kind >= calibration_visual_kind_base
		&& raw_kind < calibration_visual_kind_base + 16.0;
	bool calibration_label = raw_kind >= calibration_label_kind_base
		&& raw_kind < calibration_label_kind_base + 16.0;
	int calibration_index = calibration_visual
		? int(round(raw_kind - calibration_visual_kind_base))
		: int(round(raw_kind - calibration_label_kind_base));
	float visual_kind = calibration_visual
		? calibration_visual_kind(calibration_index) : raw_kind;
	float visual_payload = calibration_visual ? 0.0 : instance_data.w;
    vec2 bullet = instance_data.xy;
	bool player_visual = visual_kind > render_player_lower_bound && visual_kind < render_player_upper_bound;
	bool enemy_body_visual = visual_kind > render_shot_upper_bound && visual_kind < render_enemy_upper_bound;
	// Gameplay ships are emitted as closed, volumetric hull meshes. Keep these
	// procedural cards only in the tuning scene, where they remain useful as
	// selection proxies. Rendering both left the old axis-locked silhouette on
	// top of the corrected hull and made orientation changes appear ineffective.
	if (!calibration_visual && !calibration_label
		&& (player_visual || enemy_body_visual)) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		return;
	}
	bool player_shot_visual = visual_kind >= render_shot_kind && visual_kind < render_shot_upper_bound;
	bool super_shot_visual = visual_kind >= render_charged_shot_kind && visual_kind < render_charged_shot_upper_bound;
	bool boss_bit_visual = visual_kind > render_boss_bit_lower_bound && visual_kind < render_boss_bit_upper_bound;
	bool background_star_visual = visual_kind >= render_particle_star_kind && visual_kind < render_particle_fragment_kind;
	bool enemy_bullet_visual = visual_kind >= render_bullet_kind && visual_kind < render_multiplier_lower_bound;
	bool multiplier_popup_visual = visual_kind >= render_multiplier_lower_bound && !calibration_visual
		&& !calibration_label;
	bool surface_particle_visual = visual_kind >= render_particle_kind && visual_kind < render_particle_star_kind;
	bool reflected_particle = surface_particle_visual
		&& visual_payload > particle_reflection_heading_offset * 0.5;
	float surface_payload = visual_payload
		- (reflected_particle ? particle_reflection_heading_offset : 0.0);
	bool surface_bound_visual = (visual_kind > render_shot_upper_bound && visual_kind < render_enemy_upper_bound)
		|| boss_bit_visual
		|| player_shot_visual || super_shot_visual
		|| surface_particle_visual || background_star_visual || enemy_bullet_visual;
	float surface_radius = surface_bound_visual || player_visual
		? instance_surface_radius : 0.0;
	bool explicit_course_tangent = instance_tangent_radius > 0.0
		&& (surface_bound_visual || player_visual);
	bool explicit_course_frame = explicit_course_tangent
		&& instance_lateral_radius > 0.0 && instance_normal_radius > 0.0;
	float tangent_surface_radius = explicit_course_tangent ? instance_tangent_radius : 0.0;
	float tangent_surface_angle = instance_tangent_angle;
	float particle_height = 0.0;
	if (visual_kind >= render_particle_kind && visual_kind < render_bullet_kind) {
		float particle_code = visual_kind - render_particle_kind;
		float particle_variant = floor(particle_code / 0.25 + 0.001);
		float particle_detail = particle_code - particle_variant * 0.25;
		int particle_payload = int(round(particle_detail / particle_payload_scale));
		int height_bin = (particle_payload / 256) % 128;
		particle_height = float(height_bin) * 0.55 - 64.0;
	}
    float depth = max(0.6, (2.2 + bullet.y * depth_scale
		+ frame.depth_offset * depth_scale) * frame.tunnel_scale);
    float travel = frame.time * 3.2;
    // The ship sits just inside the course surface. Do not apply the ambient
    // actor bob to it: that made the replay ship cross the track every cycle.
	float radius = player_visual ? surface_radius
		: multiplier_popup_visual
		? tunnel_radius
		: surface_bound_visual ? surface_radius
		: 1.35 + 0.12 * sin(depth * 0.7 + travel)
		- particle_height * height_scale;
	vec2 bend = surface_bound_visual || player_visual || multiplier_popup_visual ? vec2(0.0)
		: vec2(sin((depth + travel) * 0.23),
		       cos((depth + travel) * 0.17)) * depth * 0.035;
    // Keep the player at the near/bottom side of the tunnel. Vulkan's positive
    // viewport height maps positive clip-space Y toward the bottom of the window.
    float view_relative_angle = bullet.x - frame.view_angle + 1.57079632679;
    vec2 world = vec2(cos(view_relative_angle), sin(view_relative_angle)) * radius + bend;
	if (!calibration_visual && !calibration_label) world *= frame.tunnel_scale;
    vec2 projected = vec2(world.x / frame.aspect, world.y) / depth;
    float projection_depth = depth;
    vec2 world_ring = vec2(-sin(bullet.x), cos(bullet.x)) * radius;
    vec2 world_bend = vec2(-bend.y, bend.x);
	if (!calibration_visual && !calibration_label) {
		world_ring *= frame.tunnel_scale;
		world_bend *= frame.tunnel_scale;
	}
    if (frame.camera_3d > 0.5) {
        projected = replay_projection(vec3(world_ring + world_bend,
                                           bullet.y * depth_scale * frame.tunnel_scale),
                                      projection_depth);
        projection_depth = max(projection_depth, 0.6);
    }
	if (calibration_visual || calibration_label) {
		projected = replay_projection(vec3(instance_data.x, instance_data.y,
			instance_data.w), projection_depth);
		projection_depth = max(projection_depth, 0.06);
	}
	// Derive an isotropic screen-space basis from nearby projections instead of
	// treating every actor as if the tunnel always ran down the display. A zero
	// heading now follows the local flight direction; positive lateral motion
	// follows increasing tunnel angle. This also makes distant star streaks
	// radiate away from the camera's vanishing direction.
	vec2 forward_projected;
	vec2 lateral_projected;
	vec2 normal_projected;
	if (calibration_visual || calibration_label) {
		forward_projected = projected + vec2(0.0, -0.01);
		lateral_projected = projected + vec2(-0.01 / frame.aspect, 0.0);
		normal_projected = projected + vec2(0.0, 0.01);
	} else if (frame.camera_3d > 0.5) {
		float ignored_depth;
		vec2 next_ring = explicit_course_tangent
			? vec2(-sin(tangent_surface_angle), cos(tangent_surface_angle))
				* tangent_surface_radius * frame.tunnel_scale
			: world_ring + world_bend;
		forward_projected = replay_projection(vec3(next_ring,
			(bullet.y + 0.5) * depth_scale * frame.tunnel_scale), ignored_depth);
		vec2 lateral_ring = explicit_course_frame
			? vec2(-sin(instance_lateral_angle), cos(instance_lateral_angle))
				* instance_lateral_radius * frame.tunnel_scale
			: world_ring + world_bend;
		lateral_projected = replay_projection(vec3(lateral_ring,
			bullet.y * depth_scale * frame.tunnel_scale), ignored_depth);
		vec2 normal_ring = explicit_course_frame
			? vec2(-sin(instance_normal_angle), cos(instance_normal_angle))
				* instance_normal_radius * frame.tunnel_scale
			: world_ring + world_bend;
		normal_projected = replay_projection(vec3(normal_ring,
			bullet.y * depth_scale * frame.tunnel_scale), ignored_depth);
	} else {
		float forward_depth = max(0.6, (2.2 + (bullet.y + 0.5) * depth_scale
			+ frame.depth_offset * depth_scale) * frame.tunnel_scale);
		float forward_angle = explicit_course_tangent
			? tangent_surface_angle - frame.view_angle + 1.57079632679
			: view_relative_angle;
		float forward_radius = explicit_course_tangent ? tangent_surface_radius : radius;
		vec2 forward_world = vec2(cos(forward_angle), sin(forward_angle))
			* forward_radius;
		if (!calibration_visual && !calibration_label)
			forward_world *= frame.tunnel_scale;
		forward_projected = vec2(forward_world.x / frame.aspect, forward_world.y)
			/ forward_depth;
		float lateral_world_angle = instance_lateral_angle - frame.view_angle
			+ 1.57079632679;
		vec2 lateral_world = explicit_course_frame
			? vec2(cos(lateral_world_angle), sin(lateral_world_angle))
				* instance_lateral_radius * frame.tunnel_scale
			: world;
		lateral_projected = vec2(lateral_world.x / frame.aspect, lateral_world.y)
			/ depth;
		float normal_world_angle = instance_normal_angle - frame.view_angle
			+ 1.57079632679;
		vec2 normal_world = explicit_course_frame
			? vec2(cos(normal_world_angle), sin(normal_world_angle))
				* instance_normal_radius * frame.tunnel_scale
			: world;
		normal_projected = vec2(normal_world.x / frame.aspect, normal_world.y)
			/ depth;
	}
	vec2 forward_delta = forward_projected - projected;
	forward_delta.x *= frame.aspect;
	vec2 forward_axis = length(forward_delta) > 0.00001
		? normalize(forward_delta) : vec2(0.0, -1.0);
	vec2 lateral_delta = lateral_projected - projected;
	lateral_delta.x *= frame.aspect;
	vec2 lateral_axis = length(lateral_delta) > 0.00001
		? normalize(lateral_delta) : vec2(forward_axis.y, -forward_axis.x);
	vec2 normal_delta = normal_projected - projected;
	normal_delta.x *= frame.aspect;
	vec2 normal_axis = length(normal_delta) > 0.00001
		? normalize(normal_delta) : -forward_axis;
	local_position = corners[gl_VertexIndex];
	instance_kind = calibration_label ? raw_kind : visual_kind;
	instance_payload = calibration_label ? float(calibration_index) : visual_payload;
	bool calibration_ship_proxy = calibration_visual
		&& (calibration_index == 0 || (calibration_index >= 4 && calibration_index <= 6));
	instance_selected = calibration_ship_proxy
		? (instance_scale < 0.0 ? 3.0 : 2.0)
		: calibration_visual && instance_scale < 0.0 ? 1.0 : 0.0;
	if (calibration_label) {
		float label_height = 0.0105;
		float label_width = label_height * float(calibration_label_length(calibration_index))
			* 6.0 / 7.0 / frame.aspect;
		float preview_half_height = calibration_visual_base_size(calibration_index)
			* abs(instance_scale) * source_projection_near_scale
			* source_projection_near_depth / projection_depth;
		float label_offset = preview_half_height + 0.035;
		vec2 label_anchor = projected + vec2(0.0, -label_offset);
		gl_Position = vec4(label_anchor + local_position * vec2(label_width,
			label_height), 0.0, 1.0);
		return;
	}
	bool multiplier_popup = multiplier_popup_visual;
	if (multiplier_popup) {
		int popup_code = int(floor(instance_payload));
		bool large_label = popup_code >= multiplier_large_label_offset;
		int multiplier = popup_code - (large_label ? multiplier_large_label_offset : 0);
		float character_count = multiplier >= 100 ? 4.0 :
		                        (multiplier >= 10 ? 3.0 : 2.0);
		float popup_height = (large_label ? 0.032 : 0.0112)
			* (1.0 + float(multiplier) * 0.01);
		vec2 popup_size = vec2(popup_height * character_count * 6.0 / 7.0 /
		                           frame.aspect, popup_height);
		float clip_zoom = frame.camera_3d > 0.5 ? 1.0 : frame.zoom;
		// Multiplier labels are presentation feedback, not tunnel occupants. New
		// hits enter at the top of a stable side list and push older labels down,
		// so simultaneous hits can never cover one another or the flight path.
		int popup_slot = int(round((instance_kind - render_multiplier_kind) /
		                           multiplier_list_slot_kind_scale));
		float horizontal_margin = 0.035;
		vec2 popup_anchor = vec2(-1.0 + popup_size.x + horizontal_margin,
		                         -0.52 + float(popup_slot) * 0.145);
		// The bullet pipeline reads tunnel depth but does not write it. Depth zero
		// makes this final instance an unobscured overlay without affecting later
		// HUD rendering.
		gl_Position = vec4((popup_anchor + local_position * popup_size) * clip_zoom,
		                   0.0, clip_zoom);
		return;
	}
	float charge_ratio = clamp((instance_kind - render_charged_shot_kind) / 0.49, 0.0, 1.0);
	float charge_size = 0.020 * charge_ratio * 13.6;
	float shot_code = clamp(instance_kind - render_shot_kind, 0.0, 0.49);
	bool star_shell = shot_code >= 0.2;
	float shot_size = clamp((shot_code - (star_shell ? 0.25 : 0.0)) / 0.1, 0.0, 1.0);
	float particle_code = max(visual_kind - render_particle_kind, 0.0);
	float particle_variant = floor(particle_code / 0.25 + 0.001);
	float particle_detail = particle_code - particle_variant * 0.25;
	int particle_payload = int(round(particle_detail / particle_payload_scale));
	float particle_tier = float(particle_payload / 32768);
	bool player_jet_visual = surface_particle_visual
		&& particle_variant >= 0.5 && particle_variant < 1.5
		&& particle_tier < 0.5;
	float particle_life = float((particle_payload / 16) % 16) / 15.0;
	bool fragment_particle = particle_variant == 3.0;
	int fragment_payload = fragment_particle ? int(round(visual_payload)) : 0;
	int fragment_width_bin = (fragment_payload >> 12) & 63;
	int fragment_height_bin = (fragment_payload >> 18) & 63;
	float fragment_width = float(fragment_width_bin) / 63.0 * fragment_width_limit;
	float fragment_height = float(fragment_height_bin) / 63.0 * fragment_height_limit;
    float particle_size = (0.005 + particle_life * 0.014
		+ (particle_variant == 2.0 ? 0.008 : 0.0))
		* (particle_variant == 3.0 ? 1.0 + particle_tier * 0.48 : 1.0);
	float enemy_tier = clamp(floor((visual_kind - render_enemy_kind) /
	                               enemy_shape_tier_stride + 0.001), 0.0, 2.0);
	float enemy_size = enemy_tier < 0.5 ? 0.024
		: enemy_tier < 1.5 ? 0.056 : 0.105;
	float bullet_code = max(visual_kind - render_bullet_kind, 0.0);
	int bullet_shape = int(floor(bullet_code + 0.001));
	bool disappearing_bullet = visual_kind >= render_bullet_kind && (bullet_shape & 1) != 0;
	float bullet_detail = fract(bullet_code);
	float bullet_visual_scale = bullet_detail >= 0.5 ? 1.2 : 1.0;
	float bullet_fade = disappearing_bullet
		? clamp((bullet_detail - (bullet_visual_scale > 1.1 ? 0.5 : 0.0)) / 0.49, 0.0, 1.0)
		: 1.0;
	float base_size = player_visual ? 0.030
		: player_shot_visual ? 0.012 * shot_size
		: super_shot_visual ? charge_size
		: boss_bit_visual ? 0.030
		: (visual_kind > render_shot_upper_bound && visual_kind < render_enemy_upper_bound) ? enemy_size
		: visual_kind > render_charged_shot_upper_bound ? particle_size : 0.010;
	if (visual_kind >= render_bullet_kind && visual_kind < render_tunnel_lower_bound)
		base_size = 0.012 * bullet_visual_scale * bullet_fade;
	if (visual_kind > render_tunnel_lower_bound) base_size = tunnel_radius / (4.62 * 0.94);
	base_size *= abs(instance_scale);
	// Source actors are world-space geometry. Reciprocal-depth projection keeps
	// their physical footprint constant; the former square-root falloff made
	// distant ships grow through the tunnel. Keep dimensions isotropic until
	// after rotation, then apply aspect correction in screen space.
	float perspective_scale = source_projection_near_scale
		* source_projection_near_depth / projection_depth;
	vec2 size = vec2(base_size) * perspective_scale;
	if (fragment_particle && fragment_width > 0.0 && fragment_height > 0.0) {
		size = vec2(fragment_width, fragment_height) * 0.003 * perspective_scale;
	}
	float surface_heading = surface_payload;
	float heading = surface_bound_visual ? surface_heading
		: visual_payload - (reflected_particle ? particle_reflection_heading_offset : 0.0);
	if (calibration_visual) heading = 0.0;
	mat2 heading_rotation = mat2(cos(heading), -sin(heading),
	                             sin(heading), cos(heading));
	bool banked_body_visual = !calibration_visual && (player_visual || enemy_body_visual);
	bool course_oriented_visual = !calibration_visual
		&& (surface_bound_visual || player_visual);
	bool rigid_source_visual = banked_body_visual || player_shot_visual
		|| super_shot_visual || boss_bit_visual || enemy_bullet_visual
		|| fragment_particle;
	// The source's local axes become decreasing circumference (X), outward
	// radial (Y), and course-forward (Z). Project the stored quaternion through
	// those axes instead of adding unlike Euler rotations into one screen angle.
	vec2 source_x_axis = -lateral_axis;
	vec2 source_y_axis = normal_axis;
	vec2 source_z_axis = forward_axis;
	vec3 rotated_x = quaternion_rotate(instance_rotation, vec3(1.0, 0.0, 0.0));
	vec3 rotated_second = quaternion_rotate(instance_rotation,
		(player_shot_visual || super_shot_visual)
			? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
	vec2 rigid_x_axis = source_x_axis * rotated_x.x
		+ source_y_axis * rotated_x.y + source_z_axis * rotated_x.z;
	vec2 rigid_second_axis = source_x_axis * rotated_second.x
		+ source_y_axis * rotated_second.y + source_z_axis * rotated_second.z;
	// A ship bank is a roll around source Z, the longitudinal flight axis.
	// The procedural hull is a flat silhouette, so it cannot retain the depth
	// component of its rotated wing. Remove only the component parallel to the
	// projected nose: otherwise the tunnel normal becomes nearly collinear with
	// the nose in the chase view and makes a correct roll look like a forward
	// tumble. Keeping the transverse magnitude preserves bank foreshortening.
	vec2 body_lateral_axis = source_x_axis
		- source_z_axis * dot(source_x_axis, source_z_axis);
	body_lateral_axis = length(body_lateral_axis) > 0.00001
		? normalize(body_lateral_axis)
		: vec2(source_z_axis.y, -source_z_axis.x);
	vec2 body_normal_axis = source_y_axis
		- source_z_axis * dot(source_y_axis, source_z_axis);
	vec2 banked_x_axis = body_lateral_axis * rotated_x.x
		+ body_normal_axis * rotated_x.y;
	mat2 banked_body_orientation = mat2(banked_x_axis, source_z_axis);
	mat2 orientation = rigid_source_visual
		? (banked_body_visual ? banked_body_orientation
			: mat2(rigid_x_axis, rigid_second_axis))
		: course_oriented_visual
		? mat2(lateral_axis, forward_axis) * heading_rotation
		: heading_rotation;
    vec2 camera_shake = frame.camera_3d > 0.5 ? vec2(0.0) : frame.shake;
    float clip_zoom = frame.camera_3d > 0.5 ? 1.0 : frame.zoom;
    float visual_depth = projected_depth(projection_depth);
    if (player_visual) {
		// The source renderer draws the player after particles and enemies with
		// depth testing disabled. Keep the ship on the foremost layer so its hull
		// masks the attached exhaust instead of the flame painting over its nose.
		visual_depth = 0.0;
    }
	bool enemy_visual = visual_kind > render_shot_upper_bound && visual_kind < render_boss_bit_upper_bound;
    if (super_shot_visual) {
		// The charged weapon spans several source units and remains a luminous
		// foreground effect so its long blades are not cut up by its own slice.
		visual_depth = 0.0;
	} else if (enemy_bullet_visual) {
		// Win against the panel that emitted the bullet while retaining real
		// depth, so nearer tunnel walls can occlude it as in the original 3D
		// renderer. The bullet center has already been lifted from the surface.
		visual_depth = max(visual_depth - enemy_bullet_depth_bias, 0.0);
	} else if (player_shot_visual) {
        visual_depth = max(visual_depth - player_shot_depth_bias, 0.0);
	} else if (player_jet_visual && !reflected_particle) {
		// Stay in front of every course panel, but one layer behind the player.
		// This reproduces the source draw order while retaining Vulkan depth for
		// the rest of the tunnel scene.
		visual_depth = 0.0001;
	} else if (surface_particle_visual && !reflected_particle) {
		// Course-bound sparks and jets sit above the panel that emitted them.
		// A small bias prevents equal-depth fragments from cutting through the
		// translucent flame while nearer tunnel walls can still occlude it.
		visual_depth = max(visual_depth - 0.0055, 0.0);
	} else if (enemy_visual) {
		// Keep the complete sprite just above its sampled surface. Closer course
		// panels still occlude it because their depth separation is much larger.
		visual_depth = max(visual_depth - 0.0035, 0.0);
	} else if (background_star_visual) {
		// Stars are the backdrop: every solid course fragment must win, while
		// genuine openings retain the clear depth and reveal the streak.
		visual_depth = 1.0;
    }
	vec2 visual_origin = projected;
	if (player_jet_visual && !reflected_particle) {
		// The instance position is the previous-frame rocket/nozzle point, just
		// like Particle.drawSpark in the source. Put the narrow forward tip at
		// that point so the complete widening plume extends behind the ship.
		vec2 nozzle_to_center = orientation * (vec2(0.0, 0.80) * size);
		nozzle_to_center.x /= frame.aspect;
		visual_origin -= nozzle_to_center;
	}
	if (banked_body_visual && explicit_course_frame) {
		// A ship is source-space geometry, not a screen-facing sprite. Reconstruct
		// its sampled tunnel frame, apply the source roll in 3D, and only then
		// project each hull vertex. Do this for the gameplay camera too: applying
		// the same roll after projection collapses the hull onto a track-relative
		// screen axis whenever the tunnel curves.
		vec2 center_xy = frame.camera_3d > 0.5 ? world_ring : world;
		float tangent_view_angle = tangent_surface_angle - frame.view_angle
			+ 1.57079632679;
		vec2 tangent_xy = frame.camera_3d > 0.5
			? vec2(-sin(tangent_surface_angle), cos(tangent_surface_angle))
				* tangent_surface_radius * frame.tunnel_scale
			: vec2(cos(tangent_view_angle), sin(tangent_view_angle))
				* tangent_surface_radius * frame.tunnel_scale;
		float normal_view_angle = instance_normal_angle - frame.view_angle
			+ 1.57079632679;
		vec2 normal_xy = frame.camera_3d > 0.5
			? vec2(-sin(instance_normal_angle), cos(instance_normal_angle))
				* instance_normal_radius * frame.tunnel_scale
			: vec2(cos(normal_view_angle), sin(normal_view_angle))
				* instance_normal_radius * frame.tunnel_scale;
		vec3 center_world = vec3(center_xy,
			bullet.y * depth_scale * frame.tunnel_scale);
		vec3 tangent_world = vec3(
			tangent_xy,
			(bullet.y + 0.5) * depth_scale * frame.tunnel_scale);
		vec3 normal_world = vec3(
			normal_xy,
			bullet.y * depth_scale * frame.tunnel_scale);
		vec3 course_forward = normalize(tangent_world - center_world);
		vec3 course_normal = normal_world - center_world;
		course_normal -= course_forward * dot(course_normal, course_forward);
		course_normal = length(course_normal) > 0.00001
			? normalize(course_normal) : vec3(0.0, 1.0, 0.0);
		vec3 course_lateral = normalize(cross(course_normal, course_forward));
		vec3 hull_x = course_lateral * rotated_x.x
			+ course_normal * rotated_x.y + course_forward * rotated_x.z;
		vec3 hull_forward = course_lateral * rotated_second.x
			+ course_normal * rotated_second.y + course_forward * rotated_second.z;
		float body_world_scale = base_size * source_projection_near_scale
			* source_projection_near_depth;
		vec3 hull_vertex = center_world + (hull_x * local_position.x
			+ hull_forward * local_position.y) * body_world_scale;
		float hull_view_depth;
		vec2 hull_projected;
		if (frame.camera_3d > 0.5) {
			hull_projected = replay_projection(hull_vertex, hull_view_depth);
		} else {
			hull_view_depth = max(0.6, 2.2 * frame.tunnel_scale
				+ hull_vertex.z
				+ frame.depth_offset * depth_scale * frame.tunnel_scale);
			hull_projected = vec2(hull_vertex.x / frame.aspect, hull_vertex.y)
				/ hull_view_depth;
		}
		gl_Position = vec4(hull_projected, visual_depth, 1.0);
		return;
	}
	vec2 oriented_offset = orientation * (local_position * size);
	oriented_offset.x /= frame.aspect;
    gl_Position = vec4(visual_origin + camera_shake + oriented_offset,
                       visual_depth * clip_zoom, clip_zoom);
}
