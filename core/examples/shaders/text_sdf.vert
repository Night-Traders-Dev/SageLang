#version 450

layout(push_constant) uniform PC {
    vec2 screenSize;
    vec2 offset;
    float scale;
} pc;

// Per-glyph instance data
layout(location = 0) in vec2 inPos;       // Quad vertex (0-1)
layout(location = 1) in vec4 inGlyphRect; // x, y, w, h in atlas
layout(location = 2) in vec2 inScreenPos; // Where on screen

layout(location = 0) out vec2 fragUV;

void main() {
    vec2 pos = inScreenPos + inPos * inGlyphRect.zw * pc.scale;
    // Convert pixel coords to NDC
    vec2 ndc = (pos + pc.offset) / pc.screenSize * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
    fragUV = inGlyphRect.xy + inPos * inGlyphRect.zw;
}
