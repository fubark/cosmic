#version 450
#pragma shader_stage(vertex)

layout(push_constant) uniform VertConstants {
    mat4 mvp;
} u_const;

layout(set = 1, binding = 1) readonly buffer JointMatrices {
	mat4 joint_mats[];
};

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;
// Reduce to uvec2.
layout(location = 3) in uvec4 a_joints;
layout(location = 4) in uint a_weights;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;

uvec4 decodeUintComponents4(uint val) {
    return uvec4(
        val & 0xFF,
        (val >> 8) & 0xFF,
        (val >> 16) & 0xFF,
        (val >> 24) & 0xFF
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

void main()
{
    v_uv = a_uv;
    v_color = a_color;

    vec4 weights = decodeFloatComponents4(a_weights);
    mat4 skin = 
		weights.x * joint_mats[a_joints.x] +
		weights.y * joint_mats[a_joints.y] + 
		weights.z * joint_mats[a_joints.z] + 
		weights.w * joint_mats[a_joints.w];

    gl_Position = a_pos * skin * u_const.mvp;
}