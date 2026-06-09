#version 450

layout(location = 0) in vec3 fragWorldPos;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform MaterialUBO {
    vec4 albedo;          // rgb + alpha
    vec4 metalRoughAO;    // metallic, roughness, ao, pad
    vec4 emission;        // rgb + pad
    vec4 camPos;          // camera position + pad
    vec4 lightPos;        // light position + intensity
    vec4 lightColor;      // light color + pad
} mat;

const float PI = 3.14159265359;

// Normal Distribution Function (GGX/Trowbridge-Reitz)
float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return a2 / (PI * denom * denom);
}

// Geometry function (Schlick-GGX)
float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
}

// Fresnel (Schlick approximation)
vec3 FresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
    vec3 albedo = mat.albedo.rgb;
    float metallic = mat.metalRoughAO.x;
    float roughness = mat.metalRoughAO.y;
    float ao = mat.metalRoughAO.z;

    vec3 N = normalize(fragNormal);
    vec3 V = normalize(mat.camPos.xyz - fragWorldPos);

    // Dielectric F0 = 0.04, metallic F0 = albedo
    vec3 F0 = mix(vec3(0.04), albedo, metallic);

    // Single point light
    vec3 L = normalize(mat.lightPos.xyz - fragWorldPos);
    vec3 H = normalize(V + L);
    float distance = length(mat.lightPos.xyz - fragWorldPos);
    float attenuation = mat.lightPos.w / (distance * distance + 1.0);
    vec3 radiance = mat.lightColor.rgb * attenuation;

    // Cook-Torrance BRDF
    float NDF = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    vec3 kS = F;
    vec3 kD = (vec3(1.0) - kS) * (1.0 - metallic);

    vec3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = numerator / denominator;

    float NdotL = max(dot(N, L), 0.0);
    vec3 Lo = (kD * albedo / PI + specular) * radiance * NdotL;

    vec3 ambient = vec3(0.03) * albedo * ao;
    vec3 color = ambient + Lo + mat.emission.rgb;

    // HDR tone mapping (Reinhard)
    color = color / (color + vec3(1.0));
    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));

    outColor = vec4(color, 1.0);
}
