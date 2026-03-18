#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PC {
    float time;
    float aspect;
    float planetRadius;
    float atmosphereRadius;
    vec4 sunDir;
    vec4 cameraPos;
} pc;

const float PI = 3.14159265;
const vec3 rayleighCoeff = vec3(5.5e-6, 13.0e-6, 22.4e-6);
const float mieCoeff = 21e-6;
const float rayleighScale = 8500.0;
const float mieScale = 1200.0;

float raySphere(vec3 ro, vec3 rd, float radius) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - radius * radius;
    float d = b * b - c;
    if (d < 0.0) return -1.0;
    return -b - sqrt(d);
}

void main() {
    vec2 uv = fragUV * 2.0 - 1.0;
    uv.x *= pc.aspect;

    vec3 ro = pc.cameraPos.xyz;
    vec3 rd = normalize(vec3(uv, -1.5));

    // Intersect atmosphere shell
    float tAtmos = raySphere(ro, rd, pc.atmosphereRadius);
    float tPlanet = raySphere(ro, rd, pc.planetRadius);

    if (tAtmos < 0.0) {
        outColor = vec4(0.0, 0.0, 0.0, 0.0);
        return;
    }

    float pathLength = (tPlanet > 0.0) ? tPlanet - tAtmos : 2.0 * sqrt(pc.atmosphereRadius * pc.atmosphereRadius - dot(ro + rd * tAtmos, ro + rd * tAtmos) + (ro.x + rd.x * tAtmos) * (ro.x + rd.x * tAtmos) + (ro.y + rd.y * tAtmos) * (ro.y + rd.y * tAtmos) + (ro.z + rd.z * tAtmos) * (ro.z + rd.z * tAtmos));
    if (pathLength <= 0.0) pathLength = 0.5;

    vec3 sunDir = normalize(pc.sunDir.xyz);
    float sunDot = max(dot(rd, sunDir), 0.0);

    // Rayleigh phase
    float rayleighPhase = 0.75 * (1.0 + sunDot * sunDot);
    // Mie phase (Henyey-Greenstein)
    float g = 0.76;
    float miePhase = 1.5 * (1.0 - g*g) / (4.0 * PI * pow(1.0 + g*g - 2.0*g*sunDot, 1.5));

    vec3 scatter = rayleighCoeff * rayleighPhase + mieCoeff * miePhase;
    float density = exp(-max(length(ro) - pc.planetRadius, 0.0) / rayleighScale) * pathLength * 0.001;

    vec3 color = scatter * density * 20.0;
    float alpha = clamp(length(color) * 5.0, 0.0, 0.8);

    outColor = vec4(color, alpha);
}
