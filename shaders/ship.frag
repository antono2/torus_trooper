#version 450

layout(location = 0) in vec4 ship_color;
layout(location = 1) flat in float enemy_hull;
layout(location = 2) in vec3 panel_coordinates;
layout(location = 0) out vec4 color;

layout(push_constant) uniform Display {
    layout(offset = 0) uint material_seed;
    layout(offset = 48) float brightness;
    layout(offset = 52) float luminosity;
    layout(offset = 64) float transition_fade;
} display;

uint material_hash(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    return value ^ (value >> 16);
}

void main() {
    bool hostile = enemy_hull > 0.5;
    // Use immutable run/zone identifiers, independent of the palette's smooth
    // transition. Replays regenerate the same material without advancing RNG.
    uint seed = material_hash(display.material_seed);
    float marking_position = 0.26 + float(seed & 3u) * 0.08;
    float coordinate = (seed & 4u) == 0u ? panel_coordinates.x
                                        : panel_coordinates.y;
    float footprint = max(fwidth(coordinate), 0.0001);
    // A single broad band per face, filtered in screen pixels. Stop resolving
    // individual markings when a face is too small to contain them.
    float band = 1.0 - smoothstep(0.065, 0.065 + footprint,
                                 abs(coordinate - marking_position));
    float detail = 1.0 - smoothstep(0.12, 0.40, footprint);
    float edge = min(panel_coordinates.x,
                     min(panel_coordinates.y, panel_coordinates.z));
    vec3 widths = max(fwidth(panel_coordinates), vec3(0.0001));
    vec3 edge_pixels = panel_coordinates / widths;
    float pixel_edge = min(edge_pixels.x, min(edge_pixels.y, edge_pixels.z));
    float seam = 1.0 - smoothstep(0.35, 1.15, pixel_edge);
    float rim = smoothstep(0.7, 1.4, pixel_edge)
              * (1.0 - smoothstep(1.5, 2.3, pixel_edge));
    // Both light and dark regions are present regardless of panel visibility.
    // Keep semantic colors stable; only panel markings change between zones.
    vec3 dark = hostile ? vec3(0.055, 0.008, 0.085) : vec3(0.008, 0.045, 0.065);
    vec3 trim = hostile ? vec3(1.0, 0.36, 0.12) : vec3(0.30, 0.95, 1.0);
    vec3 body = mix(dark, ship_color.rgb, hostile ? 0.38 : 0.42);
    vec3 material = mix(body, trim, max(band * detail * 0.85, rim * detail * 0.70));
    material = mix(material, dark, seam * detail);
    // At long range retain a simple two-tone face instead of a tiny dark cage.
    material = mix(material, mix(body, trim, smoothstep(0.03, 0.20, edge) * 0.55),
                   1.0 - detail);
    float exposure = display.brightness + display.luminosity * 0.55;
    vec3 exposed = material * exposure;
    float peak = max(exposed.r, max(exposed.g, exposed.b));
    if (peak > 1.0) exposed /= peak;
    color = vec4(exposed * (1.0 - display.transition_fade), max(ship_color.a, 0.94));
}
