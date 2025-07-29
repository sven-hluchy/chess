#version 400

uniform vec3 whiteAmbient = vec3(0.5, 0.45, 0.3);
uniform vec3 whiteDiffuse = vec3(0.8, 0.7, 0.5);
uniform vec3 whiteSpecular = vec3(0.2);
uniform float whiteShininess = 16.0;

uniform vec3 blackAmbient = vec3(0.35, 0.3, 0.2);
uniform vec3 blackDiffuse = vec3(0.4, 0.25, 0.15);
uniform vec3 blackSpecular = vec3(0.1);
uniform float blackShininess = 8.0;

uniform vec3 selectionColour;

uniform vec3 uLightPos;

uniform sampler2D shadowMap;

out vec4 outColour;

in vec3 pos;
in vec3 normal;

in float isWhite;
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

    vec3 amb = isWhite == 1.0 ? whiteAmbient : blackAmbient;
    vec3 diff = isWhite == 1.0 ? whiteDiffuse : blackDiffuse;
    vec3 spec = isWhite == 1.0 ? whiteSpecular : blackSpecular;
    float s = isWhite == 1.0 ? whiteShininess : blackShininess;

    vec3 c = mix(amb, selectionColour, highlight);

    vec3 ambient = amb * c;
    vec3 diffuse = (diff * c) * max(0.0, dot(l, n));
    vec3 specular = spec * pow(max(0.0, dot(v, r)), s);

    vec3 light = (ambient + (1 - shadow) * (diffuse + specular)) * vec3(1);

    outColour = vec4(light, 1.0);
}
