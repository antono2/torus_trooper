#version 450

layout(location = 0) in vec4 ship_color;
layout(location = 1) flat in float enemy_hull;
layout(location = 0) out vec4 color;

layout(push_constant) uniform Display {
    layout(offset = 48) float brightness;
    layout(offset = 52) float luminosity;
    layout(offset = 64) float transition_fade;
} display;

void main() {
    float exposure = display.brightness + display.luminosity * 0.55;
    vec3 exposed = ship_color.rgb * exposure;
    // Preserve the seeded hull hue when brightness/luminosity would otherwise
    // clip several channels to 1.0 and turn the racing ships white.
    float peak = max(exposed.r, max(exposed.g, exposed.b));
    if (peak > 1.0)
        exposed /= peak;
    if (enemy_hull > 0.5) {
        // Enemy hulls can collide with the player. Keep their seeded hue, but
        // anchor it to a dark saturated threat color that contrasts with all
        // of the deliberately pale tunnel-panel palettes.
        exposed = mix(exposed, vec3(0.12, 0.01, 0.20), 0.42);
    }
    color = vec4(exposed * (1.0 - display.transition_fade),
                 ship_color.a);
}
