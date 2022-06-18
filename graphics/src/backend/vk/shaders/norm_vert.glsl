#version 450
#pragma shader_stage(vertex)

layout(push_constant) uniform VertConstants {
    mat4 mvp;
} u_const;

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec4 a_color;

layout(location = 0) out vec4 out_color;

void main()
{
    out_color = a_color;
    gl_Position = a_pos * u_const.mvp;
}