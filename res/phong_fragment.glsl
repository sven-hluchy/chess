#version 400

uniform float uAmbient = 0.1;
uniform float uDiffuse = 0.8;
uniform float uSpecular = 0.3;
uniform float uShininess = 32;

uniform vec3 selectionColour;

uniform vec3 uLightPos;

uniform sampler2D shadowMap;

out vec4 outColour;

in vec3 pos;
in vec3 normal;
in vec3 colour;
in float highlight;
in vec4 posLightSpace;

void main() {
    vec3 n = normalize(normal);
    vec3 v = normalize(-pos);
    vec3 l = normalize(uLightPos - pos);
    vec3 r = reflect(-l, n);

    vec3 projected = posLightSpace.xyz / posLightSpace.w;
    projected = projected * 0.5 + 0.5;
    float bias = max(0.05 * (1.0 - dot(n, l)), 0.005);
    float shadow = projected.z > 1.0
        ? 0.0
        : projected.z - bias > texture(shadowMap, projected.xy).r
            ? 0.7
            : 0.0;

    vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
    for (int x = -2; x <= 2; ++x) {
        for (int y = -2; y < 2; ++y) {
            vec2 p = projected.xy + vec2(x, y) * texelSize;
            float pcfDepth = texture(shadowMap, p).r;
            shadow += projected.z - bias > pcfDepth ? 0.5 : 0.0;
        }
    }

    shadow /= 18.0;

    float s = uShininess;
    vec3 c = mix(colour, selectionColour, highlight);

    vec3 ambient = uAmbient * c;
    vec3 diffuse = (uDiffuse * c) * max(0.0, dot(l, n));
    vec3 specular = uSpecular * vec3(1) * pow(max(0.0, dot(v, r)), s);

    vec3 light = (ambient + (1 - shadow) * (diffuse + specular)) * vec3(1);

    outColour = vec4(light, 1.0);
}
