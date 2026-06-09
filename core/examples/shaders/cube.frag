#version 450

layout(location = 0) in vec3 fragNormal;
layout(location = 1) in vec2 fragUV;
layout(location = 2) in vec3 fragPos;

layout(location = 0) out vec4 outColor;

void main() {
    // Checkerboard pattern
    float cx = floor(fragUV.x * 4.0);
    float cy = floor(fragUV.y * 4.0);
    float checker = mod(cx + cy, 2.0);
    vec3 baseColor = mix(vec3(0.8, 0.2, 0.2), vec3(0.9, 0.9, 0.9), checker);

    // Simple directional light
    vec3 lightDir = normalize(vec3(1.0, 1.0, 0.5));
    float NdotL = max(dot(normalize(fragNormal), lightDir), 0.0);
    float ambient = 0.15;
    float diffuse = NdotL * 0.85;

    vec3 color = baseColor * (ambient + diffuse);
    outColor = vec4(color, 1.0);
}
