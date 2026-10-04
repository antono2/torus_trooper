#version 450
#extension GL_GOOGLE_include_directive : require
#include "palette.glsl"
#include "hud_state.h"

layout(location = 0) in float brightness;
layout(location = 1) in float camera_depth;
layout(location = 0) out vec4 color;

layout(push_constant) uniform FrameColor {
    layout(offset = 28) int state;
    layout(offset = 32) vec4 tunnel_color;
    layout(offset = 48) float display_brightness;
    layout(offset = 52) float luminosity;
    layout(offset = 64) float transition_fade;
} frame;

const float camera_near_depth = 0.0;

void main() {
    // Open near slices must leave both color and depth untouched so geometry
    // farther down the tunnel remains visible through the course opening.
    if (brightness <= 0.0) discard;
    // Clip replay geometry at the camera itself. This rejects course vertices
    // behind the eye without removing the track beneath the replay ship.
    if ((frame.state & TT_HUD_TITLE) != 0 && camera_depth <= camera_near_depth) discard;
    vec4 line_color = vec4(frame.tunnel_color.rgb, 1.0);
    float line_brightness = brightness;
    if (brightness >= 6.0) {
        line_color = vec4(color_border_pale_yellow, 1.0);
        line_brightness -= 6.0;
    } else if (brightness >= 4.0) {
        line_color = vec4(color_final_ring_gold, 1.0);
        line_brightness -= 4.0;
    } else if (brightness >= 2.0) {
        line_color = vec4(color_normal_ring_mint, 1.0);
        line_brightness -= 2.0;
    }
    float display = line_brightness * frame.display_brightness * (1.0 - frame.transition_fade);
    // Vulkan line width is fixed for a draw call. Convert the distant part of
    // the wire to fractional sample coverage instead: MSAA renders it as a
    // genuinely sub-pixel line and the alpha fallback still prevents densely
    // packed far rings from merging into a solid wall.
    float distance_coverage = 1.0 - smoothstep(7.0, 88.0, max(camera_depth, 0.0));
    distance_coverage = mix(0.025, 1.0, distance_coverage);
    // Course-edge marker lines must remain useful slightly farther ahead than
    // the ordinary grid, without returning to full-width distant strokes.
    if (brightness >= 2.0) {
        distance_coverage = max(distance_coverage, 0.16);
    }
    color = vec4(line_color.rgb * display, clamp(display * distance_coverage, 0.0, 1.0));
}
