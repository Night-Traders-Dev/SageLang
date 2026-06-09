#version 450

layout(location = 0) in vec3 fragTexCoord;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform samplerCube skybox;

void main() {
    outColor = texture(skybox, fragTexCoord);
}
