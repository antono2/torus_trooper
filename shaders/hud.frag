#version 450
#extension GL_GOOGLE_include_directive : require
#include "palette.glsl"
#include "hud_state.h"

layout(location = 0) in vec3 glyph_color;
layout(location = 1) flat in float ignore_transition;
layout(location = 2) flat in float glyph_alpha;
layout(location = 0) out vec4 color;

layout(push_constant) uniform Display {
    layout(offset = 28) int state;
    layout(offset = 48) float brightness;
    layout(offset = 52) float luminosity;
    layout(offset = 64) float transition_fade;
    layout(offset = 88) float shadow_pass;
} display;

void main() {
    if ((display.state & TT_HUD_REPLAY_LIBRARY) != 0) {
        color = vec4(glyph_color, glyph_alpha);
        return;
    }
    float fade = mix(1.0 - display.transition_fade, 1.0, ignore_transition);
    if (display.shadow_pass < -0.5) {
        color = vec4(color_black, max(glyph_alpha, 0.68) * fade * 0.92);
        return;
    }
    color = vec4(glyph_color * display.brightness * fade, glyph_alpha);
}
