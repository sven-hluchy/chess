#version 400

uniform float uAmbient = 0.7;
uniform float uDiffuse = 0.4;
uniform float uSpecular = 0.8;
uniform float uShininess = 0.9;

uniform float isSelected;

uniform vec3 uLightPos = vec3(5.0, 5.0, 0.0);

out vec4 outColour;

in vec3 pos;
in vec3 normal;
in vec3 colour;

void main() {
    vec3 n = normalize(normal);
    vec3 v = normalize(-pos);
    vec3 l = normalize(uLightPos - pos);
    vec3 r = reflect(-l, n);

    vec3 c = colour;

    vec3 ca = uAmbient * c;
    vec3 cd = uDiffuse * c;
    vec3 cs = uSpecular * c;
    float s = uShininess;

    vec3 light = (ca + cd * max(0.0, dot(l, n)) + cs * pow(max(0.0, dot(v, r)), s)) * c;

    outColour = vec4(light, 1.0);
}
