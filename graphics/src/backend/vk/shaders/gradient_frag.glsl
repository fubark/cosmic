#version 450
#pragma shader_stage(fragment)

layout(push_constant) uniform FragConstants {
    layout(offset=16*4) vec4 start_color;
    vec4 end_color;
    vec2 start_pos;
    vec2 end_pos;
} u_const;

// Start from top left (0,0).
layout(origin_upper_left) in vec4 gl_FragCoord;

layout(location = 0) out vec4 f_color;

void main() {
    vec2 grad_vec = u_const.end_pos - u_const.start_pos;
    float len = length(grad_vec);
    f_color = mix(u_const.start_color, u_const.end_color, dot(grad_vec, gl_FragCoord.xy - u_const.start_pos) / (len * len));
}