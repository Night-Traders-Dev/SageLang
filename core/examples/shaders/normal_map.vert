#version 450

layout(push_constant) uniform PC {
    mat4 mvp;
    mat4 model;
    vec4 lightPos;
    vec4 viewPos;
} pc;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;

layout(location = 0) out vec3 fragWorldPos;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec2 fragUV;
layout(location = 3) out mat3 fragTBN;

void main() {
    gl_Position = pc.mvp * vec4(inPosition, 1.0);
    fragWorldPos = (pc.model * vec4(inPosition, 1.0)).xyz;
    fragNormal = normalize(mat3(pc.model) * inNormal);
    fragUV = inUV;

    // Compute TBN from normal and UV derivatives
    vec3 N = fragNormal;
    vec3 T = normalize(cross(N, vec3(0.0, 1.0, 0.0)));
    if (length(T) < 0.001) T = normalize(cross(N, vec3(1.0, 0.0, 0.0)));
    vec3 B = cross(N, T);
    fragTBN = mat3(T, B, N);
}
