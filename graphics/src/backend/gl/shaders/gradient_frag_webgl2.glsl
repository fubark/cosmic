#version 300 es

precision mediump float;

// Screen pos.
uniform vec2 u_start_pos;
uniform vec4 u_start_color;
uniform vec2 u_end_pos;
uniform vec4 u_end_color;

out vec4 f_color;

// OpenGL gl_FragCoord starts at bottom left.

void main() {
    vec2 grad_vec = u_end_pos - u_start_pos;
    float len = length(grad_vec);
    f_color = mix(u_start_color, u_end_color, dot(grad_vec, gl_FragCoord.xy - u_start_pos) / (len * len));
}