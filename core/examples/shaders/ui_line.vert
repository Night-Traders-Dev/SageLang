#version 450

layout(push_constant) uniform PushConstants {
    vec4 color;
    vec2 screen;
} pc;

layout(location = 0) in vec2 inPos;
layout(location = 0) out vec4 fragColor;

void main() {
    vec2 ndc = vec2(inPos.x / pc.screen.x * 2.0 - 1.0,
                    -(inPos.y / pc.screen.y * 2.0 - 1.0));
    gl_Position = vec4(ndc, 0.0, 1.0);
    fragColor = pc.color;
}
