#version 400

float whiteAmbient = 0.5;
float whiteDiffuse = 0.8;
float whiteSpecular = 0.2;
float whiteShininess = 64.0;

float blackAmbient = 0.35;
float blackDiffuse = 0.4;
float blackSpecular = 0.1;
float blackShininess = 64.0;

vec3 selectionColour = vec3(19.0 / 255.0, 196.0 / 255.0, 163.0 / 255.0);

uniform vec3 uLightPos;

uniform sampler2D shadowMap;

out vec4 outColour;

in vec3 pos;
in vec3 normal;

flat in int isWhite;
flat in int isHighlighted;

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

    float amb = isWhite == 1 ? whiteAmbient : blackAmbient;
    float diff = isWhite == 1.0 ? whiteDiffuse : blackDiffuse;
    float spec = isWhite == 1.0 ? whiteSpecular : blackSpecular;
    float s = isWhite == 1.0 ? whiteShininess : blackShininess;

    vec3 c = mix(vec3(amb), selectionColour, isHighlighted);

    vec3 ambient = amb * c;
    vec3 diffuse = (diff * c) * max(0.0, dot(l, n));
    vec3 specular = spec * vec3(1) * pow(max(0.0, dot(v, r)), s);

    vec3 light = (ambient + (1 - shadow) * (diffuse + specular)) * vec3(1);

    outColour = vec4(light, 1.0);
}
