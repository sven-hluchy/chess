#version 400 core

in vec2 texCoord;

uniform sampler2D depthMap;

out vec4 outColour;

void main() {
    float d = texture(depthMap, texCoord).r;
    outColour = vec4(vec3(d), 1.0);
}
