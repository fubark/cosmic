#version 450
#pragma shader_stage(vertex)

layout(push_constant) uniform VertConstants {
    mat4 vp;
    mat3 normal;
    uint model_idx;
    uint material_idx;
} u_const;

layout(set = 1, binding = 1) readonly buffer Matrices {
	mat4 mats[];
};

layout(set = 2, binding = 2) uniform Camera {
    vec3 pos;
    // Directional light, assume normalized.
    vec3 light_vec;
    vec3 light_color;
    mat4 light_vp;
    bool enable_shadows;
} u_cam;

struct Material {
    float emissivity;
    float roughness;
    float metallic;
    vec4 albedo_color;
};

layout(set = 3, binding = 3) readonly buffer Materials {
    Material materials[];
};

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in uvec2 a_joints;
layout(location = 4) in uint a_weights;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;
layout(location = 2) out vec3 v_normal;
layout(location = 3) out vec3 v_pos;
layout(location = 4) out float v_emissivity;
layout(location = 5) out float v_roughness;
layout(location = 6) out float v_metallic;
layout(location = 7) out vec4 v_light_pos;

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
    uvec4 joints = decodeUintComponents4(a_joints);
    vec4 weights = decodeFloatComponents4(a_weights);
    mat4 skin = 
		weights.x * mats[joints.x] +
		weights.y * mats[joints.y] + 
		weights.z * mats[joints.z] + 
		weights.w * mats[joints.w];

    v_uv = a_uv;
    mat4 final_model = skin * mats[u_const.model_idx];
    mat3 normal_model = transpose(inverse(mat3(final_model)));
    v_normal = normalize(a_normal * normal_model);
    vec4 world_pos = a_pos * final_model;
    v_pos = world_pos.xyz;
    v_light_pos = vec4(world_pos.xyz, 1.0) * u_cam.light_vp;
    Material mat = materials[u_const.material_idx];
    v_color = mat.albedo_color;
    v_emissivity = mat.emissivity;
    v_roughness = mat.roughness;
    v_metallic = mat.metallic;
    gl_Position = world_pos * u_const.vp;
}