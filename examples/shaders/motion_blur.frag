#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D sceneTex;
layout(set = 0, binding = 1) uniform sampler2D velocityTex;

layout(push_constant) uniform PC {
    float strength;
    int samples;
} pc;

void main() {
    vec2 velocity = texture(velocityTex, fragUV).rg * pc.strength;
    vec4 color = texture(sceneTex, fragUV);
    float weight = 1.0;

    for (int i = 1; i < pc.samples; i++) {
        float t = float(i) / float(pc.samples) - 0.5;
        vec2 offset = velocity * t;
        color += texture(sceneTex, fragUV + offset);
        weight += 1.0;
    }

    outColor = color / weight;
}
