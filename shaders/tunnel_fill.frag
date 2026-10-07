// Outputs interpolated color for filled tunnel panels.
#version 450

layout(location = 0) in vec4 fill_color;
layout(location = 0) out vec4 color;

layout(push_constant) uniform Display {
    layout(offset = 48) float brightness;
    layout(offset = 64) float transition_fade;
} display;

void main() {
    color = vec4(fill_color.rgb * display.brightness *
                 (1.0 - display.transition_fade), fill_color.a);
}
