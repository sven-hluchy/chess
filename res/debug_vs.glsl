#version 400 core

in vec3 aPos;
in vec2 aTexCoord;

out vec2 texCoord;

void main() {
    texCoord = aTexCoord;
    gl_Position = vec4(aPos, 1.0);
}
