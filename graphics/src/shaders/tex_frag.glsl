#version 330

uniform sampler2D u_tex;

in vec2 v_uv;
in vec4 v_color;

out vec4 f_color;

void main() {
    f_color = texture(u_tex, v_uv) * v_color;
}