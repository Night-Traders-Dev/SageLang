#version 450

layout(push_constant) uniform PushConstants {
    mat4 lightMVP;
} pc;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;

void main() {
    gl_Position = pc.lightMVP * vec4(inPosition, 1.0);
}
