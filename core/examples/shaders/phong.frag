#version 450

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    mat4 model;
} pc;

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;

layout(location = 0) out vec4 outColor;

void main() {
    // Material
    vec3 baseColor = vec3(0.7, 0.3, 0.2);
    float checker = mod(floor(fragUV.x * 4.0) + floor(fragUV.y * 4.0), 2.0);
    baseColor = mix(baseColor, vec3(0.2, 0.6, 0.8), checker);

    // Light
    vec3 lightPos = vec3(3.0, 4.0, 2.0);
    vec3 lightColor = vec3(1.0, 0.95, 0.9);
    vec3 viewPos = vec3(0.0, 2.0, 5.0);

    vec3 N = normalize(fragNormal);
    vec3 L = normalize(lightPos - fragWorldPos);
    vec3 V = normalize(viewPos - fragWorldPos);
    vec3 R = reflect(-L, N);

    // Ambient
    float ambient = 0.1;

    // Diffuse
    float diff = max(dot(N, L), 0.0);

    // Specular (Blinn-Phong)
    vec3 H = normalize(L + V);
    float spec = pow(max(dot(N, H), 0.0), 64.0);

    vec3 color = baseColor * lightColor * (ambient + diff * 0.7) + lightColor * spec * 0.5;

    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));
    outColor = vec4(color, 1.0);
}
