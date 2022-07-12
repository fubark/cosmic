#version 300 es

struct VertConstants {
    mat4 mvp;
};

uniform VertConstants u_const;

out vec3 nearPoint;
out vec3 farPoint;
flat out mat4 mvp;

// Grid position are in xy clipped space
layout(location = 0) in vec4 pos;

vec3 UnprojectPoint(float x, float y, float z, mat4 mvp) {
    mat4 mvp_inv = inverse(mvp);
    vec4 unprojectedPoint = vec4(x, y, z, 1.0) * mvp_inv;
    return unprojectedPoint.xyz / unprojectedPoint.w;
}

void main() {
    vec3 p = pos.xyz;
    nearPoint = UnprojectPoint(p.x, p.y, -1.0, u_const.mvp); // unprojecting on the near plane
    farPoint = UnprojectPoint(p.x, p.y, 0.0, u_const.mvp); // unprojecting on the far plane
    mvp = u_const.mvp;
    gl_Position = vec4(p, 1); // using directly the clipped coordinates
}