#version 450

layout(location = 0) in vec3 fragDir;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PC {
    mat4 invViewProj;
    float time;
} pc;

// Hash for star placement
float hash(vec3 p) {
    p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

void main() {
    vec3 dir = normalize(fragDir);

    // Layer 1: Dense small stars
    vec3 color = vec3(0.0);
    vec3 cell = floor(dir * 200.0);
    float starVal = hash(cell);
    if (starVal > 0.985) {
        float brightness = (starVal - 0.985) * 66.0;
        // Color temperature
        float temp = hash(cell + 100.0);
        vec3 starColor = mix(vec3(0.6, 0.7, 1.0), vec3(1.0, 0.9, 0.7), temp);
        color += starColor * brightness * 0.5;
    }

    // Layer 2: Bright stars with glow
    cell = floor(dir * 50.0);
    starVal = hash(cell);
    if (starVal > 0.992) {
        float brightness = (starVal - 0.992) * 125.0;
        vec3 center = (cell + 0.5) / 50.0;
        float dist = length(dir - normalize(center));
        float glow = exp(-dist * dist * 50000.0);
        float temp = hash(cell + 200.0);
        vec3 starColor = mix(vec3(0.5, 0.6, 1.0), vec3(1.0, 0.85, 0.6), temp);
        color += starColor * glow * brightness;
    }

    // Subtle milky way band
    float band = exp(-abs(dir.y) * 3.0) * 0.015;
    color += vec3(0.4, 0.35, 0.5) * band;

    outColor = vec4(color, 1.0);
}
