#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D inputTexture;

layout(push_constant) uniform PushConstants {
    float threshold;
    float softKnee;
} pc;

void main() {
    vec3 color = texture(inputTexture, fragUV).rgb;
    float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float soft = brightness - pc.threshold + pc.softKnee;
    soft = clamp(soft, 0.0, 2.0 * pc.softKnee);
    soft = soft * soft / (4.0 * pc.softKnee + 0.00001);
    float contribution = max(soft, brightness - pc.threshold) / max(brightness, 0.00001);
    outColor = vec4(color * contribution, 1.0);
}
