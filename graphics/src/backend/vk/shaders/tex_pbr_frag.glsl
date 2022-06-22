#version 450
#pragma shader_stage(fragment)

layout(set = 0, binding = 0) uniform sampler2D u_tex;
layout(set = 2, binding = 2) uniform Camera {
    vec3 pos;
    // Directional light, assume normalized.
    vec3 light_vec;
    vec3 light_color;
    mat4 light_vp;
} u_cam;

layout(set = 4, binding = 4) uniform sampler2D u_shadow_map;

const float pi = 3.14159265358979323846264338327950288;

layout(location = 0) in vec2 in_uv;
layout(location = 1) in vec4 in_color;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec3 in_pos;
layout(location = 4) in float in_emissivity;
layout(location = 5) in float in_roughness;
layout(location = 6) in float in_metallic;
layout(location = 7) in vec4 in_light_pos;

layout(location = 0) out vec4 f_color;

// Fresnel-Schlick function.
vec3 fs(vec3 f0, vec3 view_vec, vec3 half_vec) {
    return f0 + (vec3(1) - f0) * pow(1 - max(dot(view_vec, half_vec), 0), 5);
}

// GGX/Trowbridge-Reitz Normal Distribution function.
float nd(float alpha, vec3 norm_v, vec3 half_v) {
    float num = pow(alpha, 2);
    float ndoth = max(dot(norm_v, half_v), 0);
    float denom = pi * pow(pow(ndoth, 2) * (num - 1) + 1, 2);
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

float computeShadow(vec4 light_space_pos, vec3 l_vec) {
    // Perspective divide and convert to texture coords.
    float z = light_space_pos.z / light_space_pos.w;
    vec2 map_uv = (light_space_pos.xy / light_space_pos.w) * 0.5 + 0.5;
    // float nearest_depth = texture(u_shadow_map, map_uv).r;   

    // Bias depends on the angle.
    float bias = max(0.05 * (1.0 - dot(in_normal, l_vec)), 0.005); 
    // if (z + bias < nearest_depth) {
    //     return 1;
    // } else {
    //     return 0;
    // }

    float shadow = 0.0;
    vec2 texel_size = 1.0 / textureSize(u_shadow_map, 0);
    for (int x = -1; x <= 1; x+=1) {
        for (int y = -1; y <= 1; y+=1) {
            float nearest_depth = texture(u_shadow_map, map_uv + vec2(x, y) * texel_size).r; 
            shadow += z + bias < nearest_depth ? 1.0 : 0.0;
        }    
    }
    shadow /= 9.0;
    return shadow;
}

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
    float shadow = computeShadow(in_light_pos, l_vec);  
    vec3 brdf = (1 - shadow) * (diffuse + specular);
    vec3 pbr = albedo * in_emissivity + brdf * u_cam.light_color * max(ndotl, 0);

    // From HDR back to LDR.
    pbr = pbr / (pbr + 1);

    // Gamma correction.
    pbr = pow(pbr, vec3(1.0/2.2));

    f_color = vec4(pbr, 1);
}