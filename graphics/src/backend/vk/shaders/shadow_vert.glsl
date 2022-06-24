#version 450
#pragma shader_stage(vertex)

layout(set = 1, binding = 1) readonly buffer Matrices {
	mat4 mats[];
};

layout(push_constant) uniform VertConstants {
    mat4 mvp;
    uint model_idx;
} u_const;

layout(location = 0) in vec4 a_pos;

void main() {
    vec4 world_pos = a_pos * mats[u_const.model_idx];
    gl_Position = world_pos * u_const.mvp;
}