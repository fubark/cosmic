#version 300 es

uniform mat4 u_mvp;

layout(location = 0) in vec4 a_pos;

void main()
{
    gl_Position = a_pos * u_mvp;
}