#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PushConstants {
    float time;
    float aspect;
    vec2 mousePos;
    vec4 planetParams;  // x=radius, y=oceanLevel, z=atmosphereThickness, w=rotation
} pc;

// Noise
vec3 hash(vec3 p) {
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(dot(hash(i), f),
                       dot(hash(i + vec3(1,0,0)), f - vec3(1,0,0)), f.x),
                   mix(dot(hash(i + vec3(0,1,0)), f - vec3(0,1,0)),
                       dot(hash(i + vec3(1,1,0)), f - vec3(1,1,0)), f.x), f.y),
               mix(mix(dot(hash(i + vec3(0,0,1)), f - vec3(0,0,1)),
                       dot(hash(i + vec3(1,0,1)), f - vec3(1,0,1)), f.x),
                   mix(dot(hash(i + vec3(0,1,1)), f - vec3(0,1,1)),
                       dot(hash(i + vec3(1,1,1)), f - vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
    float v = 0.0; float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.0; a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = fragUV * 2.0 - 1.0;
    uv.x *= pc.aspect;

    // Ray-sphere intersection
    vec3 ro = vec3(0, 0, 3.0);
    vec3 rd = normalize(vec3(uv, -1.5));

    float radius = pc.planetParams.x;
    vec3 center = vec3(0.0);
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - c;

    if (discriminant < 0.0) {
        // Atmosphere glow
        float atmosR = radius + pc.planetParams.z;
        float c2 = dot(oc, oc) - atmosR * atmosR;
        float d2 = b * b - c2;
        if (d2 > 0.0) {
            float glow = exp(-sqrt(d2) * 2.0) * 0.3;
            outColor = vec4(0.3, 0.5, 0.9, 1.0) * glow;
        } else {
            outColor = vec4(0.0, 0.0, 0.02, 1.0);
        }
        return;
    }

    float t = -b - sqrt(discriminant);
    vec3 hitPos = ro + rd * t;
    vec3 normal = normalize(hitPos - center);

    // Rotate surface point
    float rot = pc.planetParams.w + pc.time * 0.15;
    float cosR = cos(rot), sinR = sin(rot);
    vec3 sp = vec3(normal.x * cosR - normal.z * sinR, normal.y, normal.x * sinR + normal.z * cosR);

    // Terrain height via noise
    float height = fbm(sp * 3.0);
    float ocean = pc.planetParams.y;

    // Biome coloring
    vec3 color;
    if (height < ocean) {
        color = mix(vec3(0.05, 0.1, 0.3), vec3(0.1, 0.3, 0.6), (height + 1.0) * 0.5);
    } else if (height < ocean + 0.05) {
        color = vec3(0.76, 0.7, 0.5); // beach
    } else if (height < ocean + 0.3) {
        color = mix(vec3(0.2, 0.5, 0.15), vec3(0.4, 0.6, 0.2), (height - ocean) * 3.0);
    } else {
        float snow = smoothstep(0.5, 0.7, height);
        color = mix(vec3(0.4, 0.35, 0.3), vec3(0.9, 0.9, 0.95), snow);
    }

    // Lighting
    vec3 lightDir = normalize(vec3(1.0, 0.5, 0.5));
    float NdotL = max(dot(normal, lightDir), 0.0);
    float ambient = 0.08;
    color *= (ambient + NdotL * 0.9);

    // Atmosphere rim
    float rim = 1.0 - max(dot(normal, -rd), 0.0);
    color += vec3(0.3, 0.5, 0.9) * pow(rim, 3.0) * 0.4;

    outColor = vec4(color, 1.0);
}
