#version 450
#pragma shader_stage(vertex)

layout(push_constant) uniform VertConstants {
    mat4 mvp;
} u_const;

layout(location = 0) in vec4 a_pos;

void main()
{
    gl_Position = a_pos * u_const.mvp;
}