#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;

layout(location = 0) out vec4 outColor;

struct PointLight {
    vec4 position;   // xyz + intensity
    vec4 color;      // rgb + radius
};

layout(set = 0, binding = 0) uniform LightUBO {
    PointLight lights[8];
    vec4 viewPos;    // xyz + light count in w
    vec4 ambient;    // rgb + pad
} ubo;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    mat4 model;
} pc;

void main() {
    vec3 baseColor = vec3(0.7, 0.3, 0.2);
    float checker = mod(floor(fragUV.x * 4.0) + floor(fragUV.y * 4.0), 2.0);
    baseColor = mix(baseColor, vec3(0.2, 0.6, 0.8), checker);

    vec3 N = normalize(fragNormal);
    vec3 V = normalize(ubo.viewPos.xyz - fragWorldPos);

    vec3 result = ubo.ambient.rgb * baseColor;
    int lightCount = int(ubo.viewPos.w);

    for (int i = 0; i < lightCount && i < 8; i++) {
        vec3 lightPos = ubo.lights[i].position.xyz;
        float intensity = ubo.lights[i].position.w;
        vec3 lightColor = ubo.lights[i].color.rgb;
        float radius = ubo.lights[i].color.w;

        vec3 L = normalize(lightPos - fragWorldPos);
        float dist = length(lightPos - fragWorldPos);
        float atten = intensity / (1.0 + dist * dist / (radius * radius));

        float diff = max(dot(N, L), 0.0);
        vec3 H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), 64.0);

        result += baseColor * lightColor * diff * atten;
        result += lightColor * spec * atten * 0.5;
    }

    result = pow(result, vec3(1.0 / 2.2));
    outColor = vec4(result, 1.0);
}
