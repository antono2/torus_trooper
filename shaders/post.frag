#version 450
#extension GL_GOOGLE_include_directive : require
#include "palette.glsl"

layout(set = 0, binding = 0) uniform sampler2D scene_image;

layout(push_constant) uniform PostProcess {
    float aspect;
    float near_blur;
    float ship_radius;
    float enabled;
    float near_fade;
} effect;

layout(location = 0) in vec2 texture_coordinate;
layout(location = 0) out vec4 color;

void main() {
    vec2 centered = texture_coordinate - vec2(0.5);
    centered.x *= effect.aspect;
    float camera_direction = length(centered);
    vec2 absolute_direction = abs(centered);
    float edge_scale = min(
        (0.5 * effect.aspect) / max(absolute_direction.x, 0.0001),
        0.5 / max(absolute_direction.y, 0.0001)
    );
    float edge_radius = camera_direction * edge_scale;
    float start_radius = clamp(effect.ship_radius, 0.12, edge_radius - 0.08);
    float near_factor = smoothstep(start_radius, edge_radius, camera_direction)
        * effect.enabled;
    float blur_factor = near_factor * clamp(effect.near_blur, 0.0, 1.0);
    float fade_factor = near_factor * clamp(effect.near_fade, 0.0, 1.0);

    if (blur_factor <= 0.001 && fade_factor <= 0.001) {
        color = texture(scene_image, texture_coordinate);
        return;
    }

    // A fixed, symmetric kernel is spatially stable. Its radius grows from
    // zero at the ship to six pixels at the camera edge, reducing rapid panel
    // transitions without creating a trailing or flashing temporal history.
    vec2 texel = 1.0 / vec2(textureSize(scene_image, 0));
    vec2 radius = texel * (1.0 + 5.0 * blur_factor);
    vec4 blurred = texture(scene_image, texture_coordinate) * 0.24;
    blurred += texture(scene_image, texture_coordinate + vec2(radius.x, 0.0)) * 0.12;
    blurred += texture(scene_image, texture_coordinate - vec2(radius.x, 0.0)) * 0.12;
    blurred += texture(scene_image, texture_coordinate + vec2(0.0, radius.y)) * 0.12;
    blurred += texture(scene_image, texture_coordinate - vec2(0.0, radius.y)) * 0.12;
    blurred += texture(scene_image, texture_coordinate + radius) * 0.07;
    blurred += texture(scene_image, texture_coordinate - radius) * 0.07;
    blurred += texture(scene_image, texture_coordinate + vec2(radius.x, -radius.y)) * 0.07;
    blurred += texture(scene_image, texture_coordinate + vec2(-radius.x, radius.y)) * 0.07;
    vec4 sharp = texture(scene_image, texture_coordinate);
    vec4 softened = mix(sharp, blurred, blur_factor);
    color = vec4(mix(softened.rgb, color_background_navy, fade_factor), softened.a);
}
