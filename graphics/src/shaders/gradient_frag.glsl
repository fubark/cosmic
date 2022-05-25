#version 330

// Screen pos.
uniform vec2 u_start_pos;
uniform vec4 u_start_color;
uniform vec2 u_end_pos;
uniform vec4 u_end_color;

// Start from top left (0,0).
layout(origin_upper_left) in vec4 gl_FragCoord;

out vec4 f_color;

void main() {
    vec2 grad_vec = u_end_pos - u_start_pos;
    float len = length(grad_vec);
    f_color = mix(u_start_color, u_end_color, dot(grad_vec, gl_FragCoord.xy - u_start_pos) / (len * len));
}