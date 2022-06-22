#version 450
#pragma shader_stage(vertex)

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
};

layout(set = 3, binding = 3) readonly buffer Materials {
	Material materials[];
};

layout(push_constant) uniform VertConstants {
    mat4 mvp;
    mat3 normal;
    uint model_idx;
    uint material_idx;
} u_const;

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_color;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;
layout(location = 2) out vec3 v_normal;
layout(location = 3) out vec3 v_pos;
layout(location = 4) out float v_emissivity;
layout(location = 5) out float v_roughness;
layout(location = 6) out float v_metallic;
layout(location = 7) out vec4 v_light_pos;

void main()
{
    v_uv = a_uv;
    v_color = a_color;
    v_normal = normalize(a_normal * u_const.normal);
    vec4 world_pos = a_pos * mats[u_const.model_idx];
    v_pos = world_pos.xyz;
    v_light_pos = vec4(world_pos.xyz, 1.0) * u_cam.light_vp;
    Material mat = materials[u_const.material_idx];
    v_emissivity = mat.emissivity;
    v_roughness = mat.roughness;
    v_metallic = mat.metallic;
    gl_Position = world_pos * u_const.mvp;
}