#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out float outAO;

layout(set = 0, binding = 0) uniform sampler2D positionTex;
layout(set = 0, binding = 1) uniform sampler2D normalTex;

layout(push_constant) uniform PC {
    mat4 projection;
    float radius;
    float bias;
    float power;
    float pad;
} pc;

const int KERNEL_SIZE = 16;
const vec3 kernel[16] = vec3[](
    vec3( 0.05, 0.02, 0.01), vec3(-0.04, 0.06, 0.03), vec3( 0.01,-0.03, 0.07), vec3(-0.06, 0.01, 0.04),
    vec3( 0.03,-0.05, 0.02), vec3(-0.02, 0.04,-0.01), vec3( 0.07, 0.01, 0.05), vec3(-0.01,-0.06, 0.03),
    vec3( 0.04, 0.03,-0.02), vec3(-0.05,-0.01, 0.06), vec3( 0.02, 0.07,-0.04), vec3(-0.03, 0.05, 0.01),
    vec3( 0.06,-0.02,-0.05), vec3(-0.07, 0.03, 0.02), vec3( 0.01, 0.06,-0.03), vec3(-0.04,-0.07, 0.05)
);

void main() {
    vec3 fragPos = texture(positionTex, fragUV).xyz;
    vec3 normal = normalize(texture(normalTex, fragUV).xyz);

    // Random rotation from position
    vec3 randomVec = normalize(vec3(fract(sin(dot(fragUV, vec2(12.9898, 78.233))) * 43758.5453),
                                     fract(sin(dot(fragUV, vec2(93.989, 67.345))) * 24753.1232), 0.0));
    vec3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
    vec3 bitangent = cross(normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, normal);

    float occlusion = 0.0;
    for (int i = 0; i < KERNEL_SIZE; i++) {
        vec3 samplePos = fragPos + TBN * kernel[i] * pc.radius;
        vec4 offset = pc.projection * vec4(samplePos, 1.0);
        offset.xyz /= offset.w;
        offset.xyz = offset.xyz * 0.5 + 0.5;

        float sampleDepth = texture(positionTex, offset.xy).z;
        float rangeCheck = smoothstep(0.0, 1.0, pc.radius / abs(fragPos.z - sampleDepth));
        if (sampleDepth >= samplePos.z + pc.bias) {
            occlusion += rangeCheck;
        }
    }
    outAO = pow(1.0 - (occlusion / float(KERNEL_SIZE)), pc.power);
}
