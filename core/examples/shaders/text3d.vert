#version 450

layout(push_constant) uniform PushConstants {
    float time;
    float aspect;
    float pad1;
    float pad2;
} pc;

// Each vertex: vec2 position (XY), sent from vertex buffer
layout(location = 0) in vec2 inPosition;

layout(location = 0) out vec3 fragColor;

void main() {
    // Rotate around Y axis
    float angle = pc.time * 0.8;
    float cosA = cos(angle);
    float sinA = sin(angle);

    // Apply 3D rotation (rotate X around Y, add Z depth)
    float x = inPosition.x * cosA;
    float z = inPosition.x * sinA;
    float y = inPosition.y;

    // Perspective projection
    float depth = 2.5 - z;
    float px = x / (depth * pc.aspect);
    float py = y / depth;

    gl_Position = vec4(px, py, z * 0.1, 1.0);

    // Color varies by position and time
    float r = 0.5 + 0.5 * sin(pc.time + inPosition.x * 3.0);
    float g = 0.5 + 0.5 * sin(pc.time * 1.3 + inPosition.y * 3.0);
    float b = 0.5 + 0.5 * sin(pc.time * 0.7 + 1.0);
    fragColor = vec3(r, g, b);
}
