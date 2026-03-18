#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D inputTexture;

layout(push_constant) uniform PushConstants {
    vec2 texelSize;
    int horizontal;
} pc;

const float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
    vec3 result = texture(inputTexture, fragUV).rgb * weights[0];
    vec2 offset = pc.horizontal != 0 ? vec2(pc.texelSize.x, 0.0) : vec2(0.0, pc.texelSize.y);

    for (int i = 1; i < 5; i++) {
        result += texture(inputTexture, fragUV + offset * float(i)).rgb * weights[i];
        result += texture(inputTexture, fragUV - offset * float(i)).rgb * weights[i];
    }
    outColor = vec4(result, 1.0);
}
