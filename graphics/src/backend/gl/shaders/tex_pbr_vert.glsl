#version 330

struct Light {
    vec3 cam_pos;
    // Directional light, assume normalized.
    vec3 light_vec;
    vec3 light_color;
    mat4 light_vp;
    bool enable_shadows;
};

struct VertConstants {
    mat4 vp;
    mat4 model;
    mat3 normal;
};

uniform VertConstants u_const;
uniform Light u_light;

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

smooth out vec2 v_uv;
smooth out vec3 v_normal;
smooth out vec3 v_pos;
smooth out vec4 v_light_pos;

void main() {
    v_uv = a_uv;
    v_normal = normalize(a_normal * u_const.normal);
    vec4 world_pos = a_pos * u_const.model;
    v_pos = world_pos.xyz;
    v_light_pos = vec4(world_pos.xyz, 1.0) * u_light.light_vp;
    gl_Position = world_pos * u_const.vp;
}