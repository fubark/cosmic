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
layout(location = 3) in uvec2 a_joints;
layout(location = 4) in uint a_weights;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;

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

void main()
{
    v_uv = a_uv;
    v_color = a_color;

    uvec4 joints = decodeUintComponents4(a_joints);
    vec4 weights = decodeFloatComponents4(a_weights);
    mat4 skin = 
		weights.x * joint_mats[joints.x] +
		weights.y * joint_mats[joints.y] + 
		weights.z * joint_mats[joints.z] + 
		weights.w * joint_mats[joints.w];

    gl_Position = a_pos * skin * u_const.mvp;
}