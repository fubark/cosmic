// MoltenVK doesn't support geometry shaders, keep for reference.
#version 450
#pragma shader_stage(geometry)

layout (triangles) in;
layout (line_strip, max_vertices = 2) out;

layout(push_constant) uniform VertConstants {
    mat4 mvp;
} u_const;

layout (location = 0) in vec3 in_normal[];
layout (location = 0) out vec4 out_color;

void main(void) {
    float normal_len = 0.05;
    for (int i=0; i < gl_in.length(); i+=1) {
        vec3 pos = gl_in[i].gl_Position.xyz;
        vec3 normal = in_normal[i].xyz;

        gl_Position = vec4(pos, 1.0) * u_const.mvp;
        out_color = vec4(1.0, 0.0, 0.0, 1.0);
        EmitVertex();

        gl_Position = vec4(pos + normal * normal_len, 1.0) * u_const.mvp;
        out_color = vec4(0.0, 0.0, 1.0, 1.0);
        EmitVertex();

        EndPrimitive();
    }
}
