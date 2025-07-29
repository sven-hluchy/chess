#version 400 core

uniform mat4 modelMatrix;
uniform mat4 view;
uniform mat4 projection;

in vec3 aPos;
in vec3 aNorm;

void main() {
    int row = gl_InstanceID % 8;
    int col = gl_InstanceID / 8;

    mat4 offsetMatrix = mat4(
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        row, 0, col, 1);

    mat4 modelView = gl_InstanceID == 0
        ? view * modelMatrix 
        : view * (modelMatrix * offsetMatrix);

    gl_Position = projection * modelView * vec4(aPos, 1.0);
}
