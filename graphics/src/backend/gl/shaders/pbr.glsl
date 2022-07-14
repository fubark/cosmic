const float pi = 3.14159265358979323846264338327950288;

struct Material {
    float emissivity;
    float roughness;
    float metallic;
    vec4 albedo_color;
};

struct Light {
    vec3 cam_pos;
    // Directional light, assume normalized.
    vec3 light_vec;
    vec3 light_color;
    mat4 light_vp;
    bool enable_shadows;
};

uniform sampler2D u_tex;
uniform Light u_light;
uniform Material u_material;
uniform sampler2D u_shadow_map;

// Fresnel-Schlick function.
vec3 fs(vec3 f0, vec3 view_vec, vec3 half_vec) {
    return f0 + (vec3(1) - f0) * pow(1.0 - max(dot(view_vec, half_vec), 0.0), 5.0);
}

// GGX/Trowbridge-Reitz Normal Distribution function.
float nd(float alpha, vec3 norm_v, vec3 half_v) {
    float num = pow(alpha, 2.0);
    float ndoth = max(dot(norm_v, half_v), 0.0);
    float denom = pi * pow(pow(ndoth, 2.0) * (num - 1.0) + 1.0, 2.0);
    denom = max(denom, 0.000001);
    return num/denom;
}

// Schlick-Beckmann Geometry Shadowing function.
float gs(float alpha, vec3 normal_v, vec3 vec) {
    float num = max(dot(normal_v, vec), 0.0);
    float k = alpha/2.0;
    float denom = num * (1.0 - k) + k;
    denom = max(denom, 0.000001);
    return num/denom;
}

// Smith Model
float sm(float alpha, vec3 normal_v, vec3 view_v, vec3 light_v) {
    return gs(alpha, normal_v, view_v) * gs(alpha, normal_v, light_v);
}

float computeShadow(vec4 light_space_pos, vec3 norm_vec, vec3 l_vec) {
    // Perspective divide and convert to texture coords.
    float z = light_space_pos.z / light_space_pos.w;
    vec2 map_uv = (light_space_pos.xy / light_space_pos.w) * 0.5 + 0.5;
    // float nearest_depth = texture(u_shadow_map, map_uv).r;   

    // Bias depends on the angle.
    float bias = max(0.005 * (1.0 - dot(norm_vec, l_vec)), 0.0005); 
    // float bias = 0.0005;
    // if (z + bias < nearest_depth) {
    //     return 1;
    // } else {
    //     return 0;
    // }

    float shadow = 0.0;
    vec2 texel_size = 1.0 / vec2(textureSize(u_shadow_map, 0));
    for (int x = -1; x <= 1; x+=1) {
        for (int y = -1; y <= 1; y+=1) {
            float nearest_depth = texture(u_shadow_map, map_uv + vec2(x, y) * texel_size).r; 
            shadow += z + bias < nearest_depth ? 1.0 : 0.0;
        }    
    }
    shadow /= 9.0;
    return shadow;
}

