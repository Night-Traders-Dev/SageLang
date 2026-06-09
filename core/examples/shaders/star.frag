#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 0) out vec4 outColor;

void main() {
    vec2 pc = gl_PointCoord - vec2(0.5);
    float dist = length(pc);
    if (dist > 0.5) discard;
    float glow = exp(-dist * dist * 8.0);
    outColor = vec4(fragColor.rgb * glow, glow);
}
