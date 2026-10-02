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

layout(location = 0) in vec3 mesh_position;
// Negative alpha marks a player; values below -1 mark a depth-tested preview.
layout(location = 1) in vec4 mesh_color;

layout(location = 0) out vec4 ship_color;
layout(location = 1) flat out float enemy_hull;
layout(location = 2) out vec3 panel_coordinates;

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
    bool player_preview = mesh_color.a < -1.0;
    bool foreground_player = mesh_color.a < 0.0 && !player_preview;
    vec3 point = mesh_position * frame.tunnel_scale;
    float view_depth;
    if (frame.camera_3d > 0.5) {
        gl_Position = replay_projection(point, view_depth);
    } else {
        view_depth = point.z + frame.depth_offset * depth_scale * frame.tunnel_scale;
        float clip_w = view_depth * frame.zoom;
        gl_Position = vec4(point.x / frame.aspect + frame.shake.x * view_depth,
                           point.y + frame.shake.y * view_depth,
                           projected_depth(view_depth) * clip_w, clip_w);
    }
    // Match the prior sprite behavior: the player's own hull stays legible
    // above the nearby track, while enemies still obey tunnel occlusion.
    if (foreground_player)
        gl_Position.z = 0.0;
    ship_color = vec4(mesh_color.rgb, abs(mesh_color.a) - (player_preview ? 1.0 : 0.0));
    enemy_hull = mesh_color.a < 0.0 ? 0.0 : 1.0;
    // Every hull face is an unindexed triangle. These material coordinates
    // remain attached to the face through banking, movement and replay views.
    panel_coordinates = vec3(gl_VertexIndex % 3 == 0 ? 1.0 : 0.0,
                             gl_VertexIndex % 3 == 1 ? 1.0 : 0.0,
                             gl_VertexIndex % 3 == 2 ? 1.0 : 0.0);
}
