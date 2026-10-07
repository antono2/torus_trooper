// Emits the full-screen geometry and texture coordinates used by post-processing.
#version 450

layout(location = 0) out vec2 texture_coordinate;

void main() {
    vec2 position = vec2(
        gl_VertexIndex == 1 ? 3.0 : -1.0,
        gl_VertexIndex == 2 ? 3.0 : -1.0
    );
    texture_coordinate = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
