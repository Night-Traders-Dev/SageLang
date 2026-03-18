#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;
layout(location = 3) in vec4 fragLightSpace;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D shadowMap;
layout(set = 0, binding = 1) uniform SceneUBO {
    vec4 lightDir;
    vec4 lightColor;
    vec4 viewPos;
} scene;

float PCFShadow(vec4 lightSpacePos) {
    vec3 projCoords = lightSpacePos.xyz / lightSpacePos.w;
    projCoords.xy = projCoords.xy * 0.5 + 0.5;
    if (projCoords.z > 1.0) return 0.0;

    float shadow = 0.0;
    vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float closestDepth = texture(shadowMap, projCoords.xy + vec2(x, y) * texelSize).r;
            shadow += (projCoords.z - 0.005 > closestDepth) ? 1.0 : 0.0;
        }
    }
    return shadow / 9.0;
}

void main() {
    vec3 baseColor = vec3(0.8);
    float checker = mod(floor(fragUV.x * 8.0) + floor(fragUV.y * 8.0), 2.0);
    baseColor = mix(vec3(0.6, 0.6, 0.65), vec3(0.9), checker);

    vec3 N = normalize(fragNormal);
    vec3 L = normalize(-scene.lightDir.xyz);
    float NdotL = max(dot(N, L), 0.0);

    float shadow = PCFShadow(fragLightSpace);
    vec3 color = baseColor * scene.lightColor.rgb * ((1.0 - shadow * 0.7) * NdotL * 0.8 + 0.15);
    color = pow(color, vec3(1.0/2.2));
    outColor = vec4(color, 1.0);
}
