#version 450
#pragma shader_stage(fragment)
#extension GL_GOOGLE_include_directive : require

#include "pbr.glsl"

layout(location = 0) in vec2 in_uv;
layout(location = 1) in vec4 in_color;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec3 in_pos;
layout(location = 4) in float in_emissivity;
layout(location = 5) in float in_roughness;
layout(location = 6) in float in_metallic;
layout(location = 7) in vec4 in_light_pos;

layout(location = 0) out vec4 f_color;

void main() {
    // Interpolation should be normalized.
    vec3 norm_vec = normalize(in_normal);
    float roughness2 = in_roughness * in_roughness;

    vec3 albedo = texture(u_tex, in_uv).xyz * in_color.xyz;
    vec3 lambert = albedo / pi;

    // Base reflectivity is lerped from dielectic surface to metallic surface approximated by albedo.
    vec3 f0 = mix(vec3(0.04), albedo, in_metallic);

    // Directional light.
    vec3 l_vec = -u_cam.light_vec;

    vec3 view_vec = normalize(u_cam.pos - in_pos);
    vec3 half_vec = normalize(view_vec + l_vec);

    vec3 ks = fs(f0, view_vec, half_vec);
    vec3 kd = (vec3(1) - ks) * (1 - in_metallic);

    float ndotl = dot(norm_vec, l_vec);

    // Cook Torrance.
    vec3 ctn = nd(roughness2, norm_vec, half_vec) * sm(roughness2, norm_vec, view_vec, l_vec) * ks;
    float ctd = 4 * max(dot(view_vec, norm_vec), 0) * max(ndotl, 0) + 0.000001;
    vec3 specular = ctn / ctd;
    vec3 diffuse = kd * lambert;
    float shadow = u_cam.enable_shadows ? computeShadow(in_light_pos, norm_vec, l_vec) : 0;
    vec3 brdf = (1 - shadow) * (diffuse + specular);
    vec3 pbr = albedo * in_emissivity + brdf * u_cam.light_color * max(ndotl, 0);

    // From HDR back to LDR.
    pbr = pbr / (pbr + 1);

    // Gamma correction.
    pbr = pow(pbr, vec3(1.0/2.2));

    f_color = vec4(pbr, 1);
}