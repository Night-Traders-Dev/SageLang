#version 450

layout(push_constant) uniform PC {
    mat4 invViewProj;
    float time;
} pc;

layout(location = 0) out vec3 fragDir;

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    vec4 clipPos = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec4 worldDir = pc.invViewProj * clipPos;
    fragDir = worldDir.xyz / worldDir.w;
    gl_Position = vec4(uv * 2.0 - 1.0, 0.9999, 1.0);
}
