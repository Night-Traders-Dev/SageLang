#version 450

layout(push_constant) uniform PushConstants {
    mat4 viewProj;  // view-projection with translation removed
} pc;

layout(location = 0) out vec3 fragTexCoord;

// Cube vertices (36 verts = 12 triangles)
const vec3 positions[36] = vec3[](
    vec3(-1, 1,-1), vec3(-1,-1,-1), vec3( 1,-1,-1), vec3( 1,-1,-1), vec3( 1, 1,-1), vec3(-1, 1,-1),
    vec3(-1,-1, 1), vec3(-1,-1,-1), vec3(-1, 1,-1), vec3(-1, 1,-1), vec3(-1, 1, 1), vec3(-1,-1, 1),
    vec3( 1,-1,-1), vec3( 1,-1, 1), vec3( 1, 1, 1), vec3( 1, 1, 1), vec3( 1, 1,-1), vec3( 1,-1,-1),
    vec3(-1,-1, 1), vec3(-1, 1, 1), vec3( 1, 1, 1), vec3( 1, 1, 1), vec3( 1,-1, 1), vec3(-1,-1, 1),
    vec3(-1, 1,-1), vec3( 1, 1,-1), vec3( 1, 1, 1), vec3( 1, 1, 1), vec3(-1, 1, 1), vec3(-1, 1,-1),
    vec3(-1,-1,-1), vec3(-1,-1, 1), vec3( 1,-1, 1), vec3( 1,-1, 1), vec3( 1,-1,-1), vec3(-1,-1,-1)
);

void main() {
    vec3 pos = positions[gl_VertexIndex];
    fragTexCoord = pos;
    vec4 clipPos = pc.viewProj * vec4(pos, 1.0);
    gl_Position = clipPos.xyww;  // depth = 1.0 (far plane)
}
