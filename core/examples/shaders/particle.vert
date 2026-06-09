#version 450

struct Particle {
    vec2 position;
    vec2 velocity;
    vec4 color;
};

layout(std430, binding = 0) readonly buffer ParticleSSBO {
    Particle particles[];
};

layout(location = 0) out vec4 fragColor;

void main() {
    Particle p = particles[gl_VertexIndex];
    gl_Position = vec4(p.position, 0.0, 1.0);
    gl_PointSize = 3.0;
    fragColor = p.color;
}
