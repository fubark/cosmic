#version 450
#pragma shader_stage(vertex)

// layout(binding = 0) uniform ModelViewProj {
//     mat4 mat;
// } u_mvp;

layout(push_constant) uniform VertConstants {
    mat4 mat;
} u_const;

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;

void main()
{
    v_uv = a_uv;
    v_color = a_color;
    gl_Position = a_pos * u_const.mat;
}