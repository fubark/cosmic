#version 450
#pragma shader_stage(vertex)

layout(set = 1, binding = 1) readonly buffer Matrices {
	mat4 mats[];
};

layout(push_constant) uniform VertConstants {
    mat4 vp;
    uint model_idx;
} u_const;

layout(location = 0) in vec4 a_pos;
layout(location = 1) in uvec2 a_joints;
layout(location = 2) in uint a_weights;

uvec4 decodeUintComponents4(uvec2 val) {
    return uvec4(
        val.x & 0xFFFF,
        (val.x >> 16) & 0xFFFF,
        val.y & 0xFFFF,
        (val.y >> 16) & 0xFFFF
    );
}

const float scale = 1.0f / 255.f;
vec4 decodeFloatComponents4(uint val) {
    return vec4(
        float(val & 0xFF) * scale,
        float((val >> 8) & 0xFF) * scale,
        float((val >> 16) & 0xFF) * scale,
        float((val >> 24) & 0xFF) * scale
    );
}

void main() {
    uvec4 joints = decodeUintComponents4(a_joints);
    vec4 weights = decodeFloatComponents4(a_weights);
    mat4 skin = 
		weights.x * mats[joints.x] +
		weights.y * mats[joints.y] + 
		weights.z * mats[joints.z] + 
		weights.w * mats[joints.w];

    gl_Position = a_pos * skin * mats[u_const.model_idx] * u_const.vp;
}