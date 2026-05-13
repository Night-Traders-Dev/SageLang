#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 0) out vec4 outColor;

void main() {
    // Soft point sprite
    vec2 pc = gl_PointCoord - vec2(0.5);
    float dist = length(pc);
    if (dist > 0.5) discard;
    float alpha = 1.0 - smoothstep(0.3, 0.5, dist);
    outColor = vec4(fragColor.rgb, fragColor.a * alpha);
}
