#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;
layout(location = 3) in mat3 fragTBN;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D diffuseTex;
layout(set = 0, binding = 1) uniform sampler2D normalTex;

layout(push_constant) uniform PC {
    mat4 mvp;
    mat4 model;
    vec4 lightPos;
    vec4 viewPos;
} pc;

void main() {
    vec3 albedo = texture(diffuseTex, fragUV).rgb;
    vec3 normalMap = texture(normalTex, fragUV).rgb * 2.0 - 1.0;
    vec3 N = normalize(fragTBN * normalMap);

    vec3 L = normalize(pc.lightPos.xyz - fragWorldPos);
    vec3 V = normalize(pc.viewPos.xyz - fragWorldPos);
    vec3 H = normalize(L + V);

    float diff = max(dot(N, L), 0.0);
    float spec = pow(max(dot(N, H), 0.0), 32.0);

    vec3 color = albedo * (0.1 + diff * 0.8) + vec3(1.0) * spec * 0.3;
    color = pow(color, vec3(1.0/2.2));
    outColor = vec4(color, 1.0);
}
