#version 450

// Instanced star rendering: per-instance position+size from SSBO

struct Star {
    vec4 positionMass;  // xyz, w=mass (used for size)
    vec4 velocity;      // xyz, w=temperature
};

layout(std430, binding = 0) readonly buffer StarBuffer { Star stars[]; };

layout(push_constant) uniform PushConstants {
    mat4 viewProj;
} pc;

layout(location = 0) out vec4 fragColor;

void main() {
    Star s = stars[gl_VertexIndex];
    gl_Position = pc.viewProj * vec4(s.positionMass.xyz, 1.0);

    // Point size based on mass (distance falloff handled by projection)
    float mass = s.positionMass.w;
    gl_PointSize = clamp(mass * 2.0, 1.0, 8.0);

    // Color based on temperature/velocity
    float temp = length(s.velocity.xyz) * 0.5;
    vec3 cool = vec3(0.5, 0.7, 1.0);   // blue
    vec3 hot = vec3(1.0, 0.8, 0.3);    // yellow/white
    vec3 color = mix(cool, hot, clamp(temp, 0.0, 1.0));
    fragColor = vec4(color, 1.0);
}
