#version 450
#pragma shader_stage(fragment)

layout(location = 0) in vec4 in_color;

layout(location = 0) out vec4 f_color;

void main() {
    f_color = in_color;
}