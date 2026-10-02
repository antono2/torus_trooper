#version 450

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
} frame;

layout(location = 0) out float brightness;
layout(location = 1) out float camera_depth;

layout(location = 0) in vec3 course_position;
layout(location = 1) in float course_brightness;

const float tunnel_radius = 1.4175;
const float height_scale = 1.35 / 21.0;
const float depth_scale = 0.55;

vec3 tube_position(float angle, float depth, float height) {
    float radius = tunnel_radius - height * height_scale;
    return vec3(-sin(angle) * radius * frame.tunnel_scale,
                cos(angle) * radius * frame.tunnel_scale,
                depth * depth_scale * frame.tunnel_scale);
}

float projected_depth(float view_depth) {
    return clamp(1.0 - 0.1 / max(view_depth, 0.1), 0.0, 1.0);
}

vec4 replay_projection(vec3 point, out float view_depth) {
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
    float clip_w = view_depth * frame.zoom;
    return vec4(dot(relative, right) / frame.aspect + frame.shake.x * view_depth,
                dot(relative, up) + frame.shake.y * view_depth,
                projected_depth(view_depth) * clip_w, clip_w);
}

void main() {
    vec3 point = course_position;
	point *= frame.tunnel_scale;
    if (frame.camera_3d > 0.5) {
        gl_Position = replay_projection(point, camera_depth);
    } else {
        float view_depth = point.z
            + frame.depth_offset * depth_scale * frame.tunnel_scale;
        camera_depth = view_depth;
        // Keep the position homogeneous until Vulkan clips it. Collapsing each
        // vertex behind an arbitrary near depth made lines and panel edges that
        // crossed the camera plane turn into long, frame-dependent wedges.
        float clip_w = view_depth * frame.zoom;
        gl_Position = vec4(point.x / frame.aspect + frame.shake.x * view_depth,
                           point.y + frame.shake.y * view_depth,
                           projected_depth(view_depth) * clip_w, clip_w);
    }
    brightness = course_brightness;
}
