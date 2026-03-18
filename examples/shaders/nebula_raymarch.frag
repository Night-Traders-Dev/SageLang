#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler3D volumeTexture;

layout(push_constant) uniform PushConstants {
    mat4 invViewProj;
    vec4 cameraPos;
    float time;
    float density;
    float brightness;
    float stepSize;
} pc;

void main() {
    vec2 ndc = fragUV * 2.0 - 1.0;
    vec4 worldPos = pc.invViewProj * vec4(ndc, 1.0, 1.0);
    vec3 rayDir = normalize(worldPos.xyz / worldPos.w - pc.cameraPos.xyz);
    vec3 rayPos = pc.cameraPos.xyz;

    vec4 accumulated = vec4(0.0);
    float stepLen = pc.stepSize;

    for (int i = 0; i < 128; i++) {
        vec3 samplePos = rayPos + rayDir * float(i) * stepLen;
        // Map to 0-1 UV space (assumes volume centered at origin, size 10)
        vec3 uvw = samplePos / 10.0 + 0.5;
        if (uvw.x < 0.0 || uvw.x > 1.0 || uvw.y < 0.0 || uvw.y > 1.0 || uvw.z < 0.0 || uvw.z > 1.0)
            continue;

        vec4 sample_val = texture(volumeTexture, uvw);
        vec3 color = sample_val.rgb * pc.brightness;
        float alpha = sample_val.a * pc.density * stepLen;

        accumulated.rgb += color * alpha * (1.0 - accumulated.a);
        accumulated.a += alpha * (1.0 - accumulated.a);

        if (accumulated.a > 0.95) break;
    }

    outColor = vec4(accumulated.rgb, 1.0);
}
