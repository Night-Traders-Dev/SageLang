#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D fontAtlas;

layout(push_constant) uniform PC {
    vec2 screenSize;
    vec2 offset;
    float scale;
} pc;

void main() {
    float dist = texture(fontAtlas, fragUV).r;
    float edge = 0.5;
    float smoothing = 0.1 / pc.scale;
    float alpha = smoothstep(edge - smoothing, edge + smoothing, dist);
    if (alpha < 0.01) discard;
    outColor = vec4(1.0, 1.0, 1.0, alpha);
}
