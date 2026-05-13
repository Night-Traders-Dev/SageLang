#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D sceneTexture;
layout(set = 0, binding = 1) uniform sampler2D bloomTexture;

layout(push_constant) uniform PushConstants {
    float exposure;
    float bloomStrength;
    int tonemapMode;  // 0=Reinhard, 1=ACES, 2=Exposure
} pc;

// ACES tone mapping
vec3 ACESFilm(vec3 x) {
    float a = 2.51; float b = 0.03; float c = 2.43; float d = 0.59; float e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
}

void main() {
    vec3 scene = texture(sceneTexture, fragUV).rgb;
    vec3 bloom = texture(bloomTexture, fragUV).rgb;
    vec3 color = scene + bloom * pc.bloomStrength;

    // Exposure
    color *= pc.exposure;

    // Tone mapping
    if (pc.tonemapMode == 1) {
        color = ACESFilm(color);
    } else {
        color = color / (color + vec3(1.0)); // Reinhard
    }

    // Gamma
    color = pow(color, vec3(1.0 / 2.2));
    outColor = vec4(color, 1.0);
}
