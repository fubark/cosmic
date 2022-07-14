#version 330

#include "pbr.glsl"

precision mediump float;

smooth in vec2 v_uv;
smooth in vec3 v_normal;
smooth in vec3 v_pos;
smooth in vec4 v_light_pos;

layout(location = 0) out vec4 f_color;

void main() {
    // Interpolation should be normalized.
    vec3 norm_vec = normalize(v_normal);
    float roughness2 = u_material.roughness * u_material.roughness;

    vec4 color = u_material.albedo_color;
    vec3 albedo = texture(u_tex, v_uv).xyz * color.xyz;
    vec3 lambert = albedo / pi;

    // Base reflectivity is lerped from dielectic surface to metallic surface approximated by albedo.
    vec3 f0 = mix(vec3(0.04), albedo, u_material.metallic);

    // Directional light.
    vec3 l_vec = -u_light.light_vec;

    vec3 view_vec = normalize(u_light.cam_pos - v_pos);
    vec3 half_vec = normalize(view_vec + l_vec);

    vec3 ks = fs(f0, view_vec, half_vec);
    vec3 kd = (vec3(1) - ks) * (1 - u_material.metallic);

    float ndotl = dot(norm_vec, l_vec);

    // Cook Torrance.
    vec3 ctn = nd(roughness2, norm_vec, half_vec) * sm(roughness2, norm_vec, view_vec, l_vec) * ks;
    float ctd = 4 * max(dot(view_vec, norm_vec), 0) * max(ndotl, 0) + 0.000001;
    vec3 specular = ctn / ctd;
    vec3 diffuse = kd * lambert;
    float shadow = u_light.enable_shadows ? computeShadow(v_light_pos, norm_vec, l_vec) : 0;
    vec3 brdf = (1 - shadow) * (diffuse + specular);
    vec3 pbr = albedo * u_material.emissivity + brdf * u_light.light_color * max(ndotl, 0);

    // From HDR back to LDR.
    pbr = pbr / (pbr + 1);

    // Gamma correction.
    pbr = pow(pbr, vec3(1.0/2.2));

    f_color = vec4(pbr, 1);
}