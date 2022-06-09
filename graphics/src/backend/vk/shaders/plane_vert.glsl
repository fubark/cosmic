#version 450
#pragma shader_stage(vertex)

layout(push_constant) uniform VertConstants {
    mat4 mvp;
} u_const;

layout(location = 1) out vec3 nearPoint;
layout(location = 2) out vec3 farPoint;

// Grid position are in xy clipped space
vec3 gridPlane[6] = vec3[](
    vec3(1, 1, 1), vec3(-1, -1, 1), vec3(-1, 1, 1),
    vec3(-1, -1, 1), vec3(1, 1, 1), vec3(1, -1, 1)
);

vec3 UnprojectPoint(float x, float y, float z, mat4 mvp) {
    mat4 mvp_inv = inverse(mvp);
    vec4 unprojectedPoint =  vec4(x, y, z, 1.0) * mvp_inv;
    return unprojectedPoint.xyz / unprojectedPoint.w;
}

void main() {
    vec3 p = gridPlane[gl_VertexIndex].xyz;
    nearPoint = UnprojectPoint(p.x, p.y, 1, u_const.mvp).xyz; // unprojecting on the near plane
    farPoint = UnprojectPoint(p.x, p.y, 0, u_const.mvp).xyz; // unprojecting on the far plane
    gl_Position = vec4(p, 1); // using directly the clipped coordinates
}