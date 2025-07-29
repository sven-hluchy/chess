#version 400 core

uniform mat4 modelMatrix;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

uniform mat4 lightViewMatrix;
uniform mat4 lightProjMatrix;

uniform float white;
uniform vec3 selectionColour;

uniform int highlighted[64];

uniform int renderingTiles;

in vec3 aPos;
in vec3 aNorm;

out vec3 pos;
out vec3 normal;

out float highlight;
out float isWhite;

out vec4 posLightSpace;

void main() {
    int row = gl_InstanceID % 8;
    int col = gl_InstanceID / 8;

    mat4 offsetMatrix = mat4(
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        row, 0, col, 1);

    mat4 modelView = renderingTiles == 0
        ? viewMatrix * modelMatrix 
        : viewMatrix * (modelMatrix * offsetMatrix);

    mat3 normalMat = transpose(inverse(mat3(modelView)));

    pos = (modelView * vec4(aPos, 1.0)).xyz;
    normal = normalize(normalMat * aNorm);

    isWhite = renderingTiles == 0
        ? white
        : (row + col) % 2 == 0
            ? 1.0
            : 0.0;

    highlight = highlighted[gl_InstanceID] == 1 && renderingTiles == 1 ? 0.5 : 0.0;

    posLightSpace = renderingTiles == 0
        ? lightProjMatrix * lightViewMatrix * modelMatrix * vec4(aPos, 1.0)
        : lightProjMatrix * lightViewMatrix * modelMatrix * offsetMatrix * vec4(aPos, 1.0);


    gl_Position = projectionMatrix * vec4(pos, 1.0);
}
