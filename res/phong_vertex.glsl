#version 400 core

uniform mat4 modelMatrix;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

uniform vec3 whiteColour;
uniform vec3 blackColour;
uniform vec3 objectColour;
uniform vec3 selectionColour;

uniform int highlighted[64];

in vec3 aPos;
in vec3 aNorm;

out vec3 pos;
out vec3 normal;
out vec3 colour;

void main() {
    int row = gl_InstanceID % 8;
    int col = gl_InstanceID / 8;

    mat4 offsetMatrix = mat4(
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        row, 0, col, 1);

    mat4 modelView = gl_InstanceID == 0
        ? viewMatrix * modelMatrix 
        : viewMatrix * (modelMatrix * offsetMatrix);

    mat3 normalMat = transpose(inverse(mat3(modelView)));

    pos = (modelView * vec4(aPos, 1.0)).xyz;
    normal = normalize(normalMat * aNorm);

    colour = gl_InstanceID == 0
        ? objectColour
        : highlighted[gl_InstanceID] == 1
            ? selectionColour
            : (row + col) % 2 == 0 ? whiteColour : blackColour;

    gl_Position = projectionMatrix * vec4(pos, 1.0);
}
