#version 300 es

precision mediump float;

in vec3 nearPoint;
in vec3 farPoint;
flat in mat4 mvp;

out vec4 outColor;

vec4 grid(vec3 fragPos3D, float cell_size) {
    float half_width = 1.0;
    vec2 dd = fwidth(fragPos3D.xz) * half_width;
    vec2 line_falloff = min(abs(mod(fragPos3D.xz + dd, cell_size) - dd) / dd, 1.0);
    float line = min(line_falloff.x, line_falloff.y);
    vec4 color = vec4(0.2, 0.2, 0.2, 1.0 - line);

    vec2 dd2 = min(dd, 10.0);
    if (fragPos3D.z >= -dd2.y && fragPos3D.z <= dd2.y) {
        color.x = 1.0;
        color.w = 1.0;
    }
    if (fragPos3D.x >= -dd2.x && fragPos3D.x <= dd2.x) {
        color.z = 1.0;
        color.w = 1.0;
    }
    return color;
}

void main() {
    float t = -nearPoint.y / (farPoint.y - nearPoint.y);
    vec3 fragPos3D = nearPoint + t * (farPoint - nearPoint);

    // Output depth buffer value.
    vec4 clip_space_pos = vec4(fragPos3D.xyz, 1.0) * mvp;
    gl_FragDepth = ((clip_space_pos.z / clip_space_pos.w) + 1.0) * 0.5;

    outColor = grid(fragPos3D, 10.0) * float(t > 0.0);
}