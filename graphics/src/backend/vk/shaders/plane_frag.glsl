#version 450
#pragma shader_stage(fragment)

layout(location = 1) in vec3 nearPoint;
layout(location = 2) in vec3 farPoint;

layout(location = 0) out vec4 outColor;

vec4 grid(vec3 fragPos3D, float cell_size) {
    float half_width = 1;
    vec2 dd = fwidth(fragPos3D.xz) * half_width;
    vec2 line_falloff = min(abs(mod(fragPos3D.xz + dd, cell_size) - dd) / dd, 1);
    float line = min(line_falloff.x, line_falloff.y);
    vec4 color = vec4(0.2, 0.2, 0.2, 1 - line);

    vec2 dd2 = min(dd, 10);
    if (fragPos3D.z >= -dd2.y && fragPos3D.z <= dd2.y) {
        color.x = 1;
        color.w = 1;
    }
    if (fragPos3D.x >= -dd2.x && fragPos3D.x <= dd2.x) {
        color.z = 1;
        color.w = 1;
    }
    return color;
}

void main() {
    float t = -nearPoint.y / (farPoint.y - nearPoint.y);
    vec3 fragPos3D = nearPoint + t * (farPoint - nearPoint);
    outColor = grid(fragPos3D, 10) * float(t > 0);
}