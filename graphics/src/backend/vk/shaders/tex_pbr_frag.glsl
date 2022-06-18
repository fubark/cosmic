#version 450
#pragma shader_stage(fragment)

layout(set = 0, binding = 0) uniform sampler2D u_tex;
layout(set = 1, binding = 1) uniform Camera {
    vec3 pos;
    // Directional light, assume normalized.
    vec3 light_vec;
    vec3 light_color;
} u_cam;

const float pi = 3.14159265358979323846264338327950288;

layout(location = 0) in vec2 in_uv;
layout(location = 1) in vec4 in_color;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec3 in_pos;
layout(location = 4) in float in_emissivity;
layout(location = 5) in float in_roughness;
layout(location = 6) in float in_reflectivity;
layout(location = 7) in float in_metallic;

layout(location = 0) out vec4 f_color;

// Fresnel-Schlick function.
vec3 fs(vec3 f0, vec3 view_vec, vec3 half_vec) {
    return f0 + (vec3(1) - f0) * pow(1 - max(dot(view_vec, half_vec), 0), 5);
}

// GGX/Trowbridge-Reitz Normal Distribution function.
float nd(float alpha, vec3 norm_v, vec3 half_v) {
    float num = pow(alpha, 2);
    float n_dot_h = max(dot(norm_v, half_v), 0);
    float denom = pi * pow(pow(n_dot_h, 2) * (pow(alpha, 2) - 1) + 1, 2);
    denom = max(denom, 0.000001);
    return num/denom;
}

// Schlick-Beckmann Geometry Shadowing function.
float gs(float alpha, vec3 normal_v, vec3 vec) {
    float num = max(dot(normal_v, vec), 0);
    float k = alpha/2;
    float denom = num * (1 - k) + k;
    denom = max(denom, 0.000001);
    return num/denom;
}

// Smith Model
float sm(float alpha, vec3 normal_v, vec3 view_v, vec3 light_v) {
    return gs(alpha, normal_v, view_v) * gs(alpha, normal_v, light_v);
}

void main() {
    // Interpolation should be normalized.
    vec3 norm_vec = normalize(in_normal);
    float roughness2 = in_roughness * in_roughness;
    vec3 base_reflectance = vec3(in_reflectivity);

    // Directional light.
    vec3 l_vec = -u_cam.light_vec;

    vec3 view_vec = normalize(u_cam.pos - in_pos);
    vec3 half_vec = normalize(view_vec + l_vec);

    vec3 ks = fs(base_reflectance, view_vec, half_vec);
    vec3 kd = (vec3(1) - ks) * (1 - in_metallic);
    vec3 albedo = texture(u_tex, in_uv).xyz * in_color.xyz;
    vec3 lambert = albedo / pi;

    // Cook Torrance.
    vec3 ctn = nd(roughness2, norm_vec, half_vec) * sm(roughness2, norm_vec, view_vec, l_vec) * ks;
    float ctd = 4 * max(dot(view_vec, norm_vec), 0) * max(dot(l_vec, norm_vec), 0) + 0.000001;
    vec3 ct = ctn / ctd;

    vec3 brdf = kd * lambert * ct;
    vec3 pbr = albedo * in_emissivity + brdf * u_cam.light_color * max(dot(l_vec, norm_vec), 0);
    f_color = vec4(pbr, 1);
}