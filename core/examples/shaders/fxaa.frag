#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;
layout(set = 0, binding = 0) uniform sampler2D inputTex;

layout(push_constant) uniform PC {
    vec2 texelSize;
} pc;

void main() {
    vec3 rgbNW = texture(inputTex, fragUV + vec2(-1, -1) * pc.texelSize).rgb;
    vec3 rgbNE = texture(inputTex, fragUV + vec2( 1, -1) * pc.texelSize).rgb;
    vec3 rgbSW = texture(inputTex, fragUV + vec2(-1,  1) * pc.texelSize).rgb;
    vec3 rgbSE = texture(inputTex, fragUV + vec2( 1,  1) * pc.texelSize).rgb;
    vec3 rgbM  = texture(inputTex, fragUV).rgb;

    vec3 luma = vec3(0.299, 0.587, 0.114);
    float lumaNW = dot(rgbNW, luma);
    float lumaNE = dot(rgbNE, luma);
    float lumaSW = dot(rgbSW, luma);
    float lumaSE = dot(rgbSE, luma);
    float lumaM  = dot(rgbM, luma);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    vec2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.03125, 0.0078125);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin, vec2(-8.0), vec2(8.0)) * pc.texelSize;

    vec3 rgbA = 0.5 * (
        texture(inputTex, fragUV + dir * (1.0/3.0 - 0.5)).rgb +
        texture(inputTex, fragUV + dir * (2.0/3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (
        texture(inputTex, fragUV + dir * -0.5).rgb +
        texture(inputTex, fragUV + dir *  0.5).rgb);

    float lumaB = dot(rgbB, luma);
    vec3 result = (lumaB < lumaMin || lumaB > lumaMax) ? rgbA : rgbB;
    outColor = vec4(result, 1.0);
}
