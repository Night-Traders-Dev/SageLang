#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D sceneTex;

layout(push_constant) uniform PC {
    vec2 lensCenter;    // Screen-space position of massive object
    float lensStrength; // Distortion strength
    float lensRadius;   // Effect radius
} pc;

void main() {
    vec2 uv = fragUV;
    vec2 toCenter = uv - pc.lensCenter;
    float dist = length(toCenter);

    if (dist < pc.lensRadius && dist > 0.001) {
        // Einstein ring distortion
        float normalized = dist / pc.lensRadius;
        float deflection = pc.lensStrength / (dist * dist + 0.01);
        deflection = min(deflection, 0.3);
        vec2 offset = normalize(toCenter) * deflection;
        uv = uv + offset;
    }

    outColor = texture(sceneTex, clamp(uv, vec2(0.0), vec2(1.0)));
}
