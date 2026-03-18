// src/c/graphics.c - SageLang Vulkan Graphics Native Module
// Phase 15: Professional GPU compute & graphics library
//
// Provides `import gpu` with full Vulkan backend.
// Conditional compilation: compiles as stubs without SAGE_HAS_VULKAN.

#include "graphics.h"
#include "module.h"
#include "value.h"
#include "env.h"
#include "gc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ============================================================================
// Stub mode: when Vulkan SDK is not available
// ============================================================================

#ifndef SAGE_HAS_VULKAN

static Value gpu_has_vulkan(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_bool(0);
}

static Value gpu_init_stub(int argCount, Value* args) {
    (void)argCount; (void)args;
    fprintf(stderr, "gpu: Vulkan not available (compile with SAGE_HAS_VULKAN)\n");
    return val_bool(0);
}

Module* create_graphics_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "gpu");
    Environment* e = m->env;
    env_define(e, "has_vulkan", 10, val_native(gpu_has_vulkan));
    env_define(e, "initialize", 10, val_native(gpu_init_stub));

    // Export all constants so Sage code can reference them without runtime errors
    // Buffer usage
    env_define(e, "BUFFER_STORAGE",      14, val_number(SAGE_BUFFER_STORAGE));
    env_define(e, "BUFFER_UNIFORM",      14, val_number(SAGE_BUFFER_UNIFORM));
    env_define(e, "BUFFER_VERTEX",       13, val_number(SAGE_BUFFER_VERTEX));
    env_define(e, "BUFFER_INDEX",        12, val_number(SAGE_BUFFER_INDEX));
    env_define(e, "BUFFER_STAGING",      14, val_number(SAGE_BUFFER_STAGING));
    env_define(e, "BUFFER_INDIRECT",     15, val_number(SAGE_BUFFER_INDIRECT));
    env_define(e, "BUFFER_TRANSFER_SRC", 19, val_number(SAGE_BUFFER_TRANSFER_SRC));
    env_define(e, "BUFFER_TRANSFER_DST", 19, val_number(SAGE_BUFFER_TRANSFER_DST));

    // Memory properties
    env_define(e, "MEMORY_DEVICE_LOCAL",  19, val_number(SAGE_MEMORY_DEVICE_LOCAL));
    env_define(e, "MEMORY_HOST_VISIBLE",  19, val_number(SAGE_MEMORY_HOST_VISIBLE));
    env_define(e, "MEMORY_HOST_COHERENT", 20, val_number(SAGE_MEMORY_HOST_COHERENT));

    // Formats
    env_define(e, "FORMAT_RGBA8", 12, val_number(SAGE_FORMAT_RGBA8));
    env_define(e, "FORMAT_RGBA16F", 14, val_number(SAGE_FORMAT_RGBA16F));
    env_define(e, "FORMAT_RGBA32F", 14, val_number(SAGE_FORMAT_RGBA32F));
    env_define(e, "FORMAT_R32F", 11, val_number(SAGE_FORMAT_R32F));
    env_define(e, "FORMAT_RG32F", 12, val_number(SAGE_FORMAT_RG32F));
    env_define(e, "FORMAT_DEPTH32F", 15, val_number(SAGE_FORMAT_DEPTH32F));
    env_define(e, "FORMAT_DEPTH24_S8",17, val_number(SAGE_FORMAT_DEPTH24_S8));
    env_define(e, "FORMAT_R8",        9,  val_number(SAGE_FORMAT_R8));
    env_define(e, "FORMAT_RG8",       10, val_number(SAGE_FORMAT_RG8));
    env_define(e, "FORMAT_BGRA8",     12, val_number(SAGE_FORMAT_BGRA8));
    env_define(e, "FORMAT_R32U", 11, val_number(SAGE_FORMAT_R32U));
    env_define(e, "FORMAT_RG16F", 12, val_number(SAGE_FORMAT_RG16F));
    env_define(e, "FORMAT_R16F", 11, val_number(SAGE_FORMAT_R16F));

    // Image usage
    env_define(e, "IMAGE_SAMPLED",      13, val_number(SAGE_IMAGE_SAMPLED));
    env_define(e, "IMAGE_STORAGE",      13, val_number(SAGE_IMAGE_STORAGE));
    env_define(e, "IMAGE_COLOR_ATTACH", 18, val_number(SAGE_IMAGE_COLOR_ATTACH));
    env_define(e, "IMAGE_DEPTH_ATTACH", 18, val_number(SAGE_IMAGE_DEPTH_ATTACH));
    env_define(e, "IMAGE_TRANSFER_SRC", 18, val_number(SAGE_IMAGE_TRANSFER_SRC));
    env_define(e, "IMAGE_TRANSFER_DST", 18, val_number(SAGE_IMAGE_TRANSFER_DST));

    // Image types
    env_define(e, "IMAGE_1D",  8, val_number(SAGE_IMAGE_1D));
    env_define(e, "IMAGE_2D",  8, val_number(SAGE_IMAGE_2D));
    env_define(e, "IMAGE_3D",  8, val_number(SAGE_IMAGE_3D));
    env_define(e, "IMAGE_CUBE",10, val_number(SAGE_IMAGE_CUBE));

    // Filter
    env_define(e, "FILTER_NEAREST", 14, val_number(SAGE_FILTER_NEAREST));
    env_define(e, "FILTER_LINEAR",  13, val_number(SAGE_FILTER_LINEAR));

    // Address modes
    env_define(e, "ADDRESS_REPEAT",          14, val_number(SAGE_ADDRESS_REPEAT));
    env_define(e, "ADDRESS_MIRRORED_REPEAT", 23, val_number(SAGE_ADDRESS_MIRRORED_REPEAT));
    env_define(e, "ADDRESS_CLAMP_EDGE",      18, val_number(SAGE_ADDRESS_CLAMP_EDGE));
    env_define(e, "ADDRESS_CLAMP_BORDER",    20, val_number(SAGE_ADDRESS_CLAMP_BORDER));

    // Descriptor types
    env_define(e, "DESC_STORAGE_BUFFER",  19, val_number(SAGE_DESC_STORAGE_BUFFER));
    env_define(e, "DESC_UNIFORM_BUFFER",  19, val_number(SAGE_DESC_UNIFORM_BUFFER));
    env_define(e, "DESC_SAMPLED_IMAGE",   18, val_number(SAGE_DESC_SAMPLED_IMAGE));
    env_define(e, "DESC_STORAGE_IMAGE",   18, val_number(SAGE_DESC_STORAGE_IMAGE));
    env_define(e, "DESC_SAMPLER",         12, val_number(SAGE_DESC_SAMPLER));
    env_define(e, "DESC_COMBINED_SAMPLER",21, val_number(SAGE_DESC_COMBINED_SAMPLER));

    // Shader stages
    env_define(e, "STAGE_VERTEX",   12, val_number(SAGE_STAGE_VERTEX));
    env_define(e, "STAGE_FRAGMENT", 14, val_number(SAGE_STAGE_FRAGMENT));
    env_define(e, "STAGE_COMPUTE",  13, val_number(SAGE_STAGE_COMPUTE));
    env_define(e, "STAGE_GEOMETRY", 14, val_number(SAGE_STAGE_GEOMETRY));
    env_define(e, "STAGE_ALL",      9,  val_number(SAGE_STAGE_ALL));

    // Topology
    env_define(e, "TOPO_POINT_LIST",     15, val_number(SAGE_TOPO_POINT_LIST));
    env_define(e, "TOPO_LINE_LIST",      14, val_number(SAGE_TOPO_LINE_LIST));
    env_define(e, "TOPO_LINE_STRIP",     15, val_number(SAGE_TOPO_LINE_STRIP));
    env_define(e, "TOPO_TRIANGLE_LIST",  18, val_number(SAGE_TOPO_TRIANGLE_LIST));
    env_define(e, "TOPO_TRIANGLE_STRIP", 19, val_number(SAGE_TOPO_TRIANGLE_STRIP));
    env_define(e, "TOPO_TRIANGLE_FAN",   17, val_number(SAGE_TOPO_TRIANGLE_FAN));

    // Polygon modes
    env_define(e, "POLY_FILL",  9,  val_number(SAGE_POLY_FILL));
    env_define(e, "POLY_LINE",  9,  val_number(SAGE_POLY_LINE));
    env_define(e, "POLY_POINT", 10, val_number(SAGE_POLY_POINT));

    // Cull modes
    env_define(e, "CULL_NONE",  9,  val_number(SAGE_CULL_NONE));
    env_define(e, "CULL_FRONT", 10, val_number(SAGE_CULL_FRONT));
    env_define(e, "CULL_BACK",  9,  val_number(SAGE_CULL_BACK));

    // Front face
    env_define(e, "FRONT_CCW", 9, val_number(SAGE_FRONT_CCW));
    env_define(e, "FRONT_CW",  8, val_number(SAGE_FRONT_CW));

    // Blend factors
    env_define(e, "BLEND_ZERO", 10,  val_number(SAGE_BLEND_ZERO));
    env_define(e, "BLEND_ONE", 9,  val_number(SAGE_BLEND_ONE));
    env_define(e, "BLEND_SRC_ALPHA",          15, val_number(SAGE_BLEND_SRC_ALPHA));
    env_define(e, "BLEND_ONE_MINUS_SRC_ALPHA",25, val_number(SAGE_BLEND_ONE_MINUS_SRC_ALPHA));

    // Blend ops
    env_define(e, "BLEND_OP_ADD",      12, val_number(SAGE_BLEND_OP_ADD));
    env_define(e, "BLEND_OP_SUBTRACT", 17, val_number(SAGE_BLEND_OP_SUBTRACT));
    env_define(e, "BLEND_OP_MIN",      12, val_number(SAGE_BLEND_OP_MIN));
    env_define(e, "BLEND_OP_MAX",      12, val_number(SAGE_BLEND_OP_MAX));

    // Compare ops
    env_define(e, "COMPARE_NEVER",   13, val_number(SAGE_COMPARE_NEVER));
    env_define(e, "COMPARE_LESS",    12, val_number(SAGE_COMPARE_LESS));
    env_define(e, "COMPARE_LEQUAL",  14, val_number(SAGE_COMPARE_LEQUAL));
    env_define(e, "COMPARE_GREATER", 15, val_number(SAGE_COMPARE_GREATER));
    env_define(e, "COMPARE_ALWAYS",  14, val_number(SAGE_COMPARE_ALWAYS));

    // Layouts
    env_define(e, "LAYOUT_UNDEFINED",    16, val_number(SAGE_LAYOUT_UNDEFINED));
    env_define(e, "LAYOUT_GENERAL",      14, val_number(SAGE_LAYOUT_GENERAL));
    env_define(e, "LAYOUT_COLOR_ATTACH", 19, val_number(SAGE_LAYOUT_COLOR_ATTACH));
    env_define(e, "LAYOUT_DEPTH_ATTACH", 19, val_number(SAGE_LAYOUT_DEPTH_ATTACH));
    env_define(e, "LAYOUT_SHADER_READ",  18, val_number(SAGE_LAYOUT_SHADER_READ));
    env_define(e, "LAYOUT_TRANSFER_SRC", 19, val_number(SAGE_LAYOUT_TRANSFER_SRC));
    env_define(e, "LAYOUT_TRANSFER_DST", 19, val_number(SAGE_LAYOUT_TRANSFER_DST));
    env_define(e, "LAYOUT_PRESENT",      14, val_number(SAGE_LAYOUT_PRESENT));

    // Pipeline stages
    env_define(e, "PIPE_TOP",          8,  val_number(SAGE_PIPE_TOP));
    env_define(e, "PIPE_COMPUTE",      12, val_number(SAGE_PIPE_COMPUTE));
    env_define(e, "PIPE_TRANSFER",     13, val_number(SAGE_PIPE_TRANSFER));
    env_define(e, "PIPE_BOTTOM",       11, val_number(SAGE_PIPE_BOTTOM));
    env_define(e, "PIPE_VERTEX_SHADER",18, val_number(SAGE_PIPE_VERTEX_SHADER));
    env_define(e, "PIPE_FRAGMENT",     13, val_number(SAGE_PIPE_FRAGMENT));
    env_define(e, "PIPE_COLOR_OUTPUT", 17, val_number(SAGE_PIPE_COLOR_OUTPUT));
    env_define(e, "PIPE_ALL_COMMANDS", 17, val_number(SAGE_PIPE_ALL_COMMANDS));

    // Access flags
    env_define(e, "ACCESS_NONE",          11, val_number(SAGE_ACCESS_NONE));
    env_define(e, "ACCESS_SHADER_READ",   18, val_number(SAGE_ACCESS_SHADER_READ));
    env_define(e, "ACCESS_SHADER_WRITE",  19, val_number(SAGE_ACCESS_SHADER_WRITE));
    env_define(e, "ACCESS_TRANSFER_READ", 20, val_number(SAGE_ACCESS_TRANSFER_READ));
    env_define(e, "ACCESS_TRANSFER_WRITE",21, val_number(SAGE_ACCESS_TRANSFER_WRITE));
    env_define(e, "ACCESS_HOST_READ",     16, val_number(SAGE_ACCESS_HOST_READ));
    env_define(e, "ACCESS_HOST_WRITE",    17, val_number(SAGE_ACCESS_HOST_WRITE));
    env_define(e, "ACCESS_MEMORY_READ",   18, val_number(SAGE_ACCESS_MEMORY_READ));
    env_define(e, "ACCESS_MEMORY_WRITE",  19, val_number(SAGE_ACCESS_MEMORY_WRITE));

    // Load/store ops
    env_define(e, "LOAD_CLEAR",    10, val_number(SAGE_LOAD_CLEAR));
    env_define(e, "LOAD_LOAD",     9,  val_number(SAGE_LOAD_LOAD));
    env_define(e, "LOAD_DONTCARE", 13, val_number(SAGE_LOAD_DONTCARE));
    env_define(e, "STORE_STORE",   11, val_number(SAGE_STORE_STORE));
    env_define(e, "STORE_DONTCARE",14, val_number(SAGE_STORE_DONTCARE));

    // Vertex input
    env_define(e, "INPUT_RATE_VERTEX",   17, val_number(SAGE_INPUT_RATE_VERTEX));
    env_define(e, "INPUT_RATE_INSTANCE", 19, val_number(SAGE_INPUT_RATE_INSTANCE));

    // Attribute formats
    env_define(e, "ATTR_FLOAT", 10, val_number(SAGE_ATTR_FLOAT));
    env_define(e, "ATTR_VEC2",  9,  val_number(SAGE_ATTR_VEC2));
    env_define(e, "ATTR_VEC3",  9,  val_number(SAGE_ATTR_VEC3));
    env_define(e, "ATTR_VEC4",  9,  val_number(SAGE_ATTR_VEC4));
    env_define(e, "ATTR_INT",   8,  val_number(SAGE_ATTR_INT));
    env_define(e, "ATTR_UINT",  9,  val_number(SAGE_ATTR_UINT));

    return m;
}

#else // SAGE_HAS_VULKAN is defined — full implementation below

// ============================================================================
// Global GPU Context
// ============================================================================

SageGPUContext g_gpu_ctx = {0};

// ============================================================================
// Handle Table Helpers
// ============================================================================

#define DEFINE_HANDLE_TABLE_GROW(Type, field, cap_field) \
    static int grow_##field(void) { \
        if (g_gpu_ctx.field == NULL) { \
            g_gpu_ctx.cap_field = SAGE_GPU_INITIAL_CAPACITY; \
            g_gpu_ctx.field = calloc(g_gpu_ctx.cap_field, sizeof(Type)); \
            if (!g_gpu_ctx.field) return -1; \
            return 0; \
        } \
        int new_cap = g_gpu_ctx.cap_field * 2; \
        Type* new_arr = calloc(new_cap, sizeof(Type)); \
        if (!new_arr) return -1; \
        memcpy(new_arr, g_gpu_ctx.field, g_gpu_ctx.cap_field * sizeof(Type)); \
        free(g_gpu_ctx.field); \
        g_gpu_ctx.field = new_arr; \
        g_gpu_ctx.cap_field = new_cap; \
        return 0; \
    }

#define DEFINE_HANDLE_ALLOC(Type, field, count_field, cap_field) \
    static int alloc_##field(void) { \
        /* Find a dead slot first */ \
        for (int i = 0; i < g_gpu_ctx.count_field; i++) { \
            if (!g_gpu_ctx.field[i].alive) { \
                return i; \
            } \
        } \
        /* Need a new slot */ \
        if (g_gpu_ctx.count_field >= g_gpu_ctx.cap_field) { \
            if (grow_##field() != 0) return -1; \
        } \
        int idx = g_gpu_ctx.count_field++; \
        memset(&g_gpu_ctx.field[idx], 0, sizeof(Type)); \
        return idx; \
    }

DEFINE_HANDLE_TABLE_GROW(SageGPUBuffer, buffers, buffer_cap)
DEFINE_HANDLE_ALLOC(SageGPUBuffer, buffers, buffer_count, buffer_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUImage, images, image_cap)
DEFINE_HANDLE_ALLOC(SageGPUImage, images, image_count, image_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUSampler, samplers, sampler_cap)
DEFINE_HANDLE_ALLOC(SageGPUSampler, samplers, sampler_count, sampler_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUShader, shaders, shader_cap)
DEFINE_HANDLE_ALLOC(SageGPUShader, shaders, shader_count, shader_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUDescriptorLayout, desc_layouts, desc_layout_cap)
DEFINE_HANDLE_ALLOC(SageGPUDescriptorLayout, desc_layouts, desc_layout_count, desc_layout_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUDescriptorPool, desc_pools, desc_pool_cap)
DEFINE_HANDLE_ALLOC(SageGPUDescriptorPool, desc_pools, desc_pool_count, desc_pool_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUDescriptorSet, desc_sets, desc_set_cap)
DEFINE_HANDLE_ALLOC(SageGPUDescriptorSet, desc_sets, desc_set_count, desc_set_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUPipelineLayout, pipe_layouts, pipe_layout_cap)
DEFINE_HANDLE_ALLOC(SageGPUPipelineLayout, pipe_layouts, pipe_layout_count, pipe_layout_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUPipeline, pipelines, pipeline_cap)
DEFINE_HANDLE_ALLOC(SageGPUPipeline, pipelines, pipeline_count, pipeline_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPURenderPass, render_passes, render_pass_cap)
DEFINE_HANDLE_ALLOC(SageGPURenderPass, render_passes, render_pass_count, render_pass_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUFramebuffer, framebuffers, framebuffer_cap)
DEFINE_HANDLE_ALLOC(SageGPUFramebuffer, framebuffers, framebuffer_count, framebuffer_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUCommandPool, cmd_pools, cmd_pool_cap)
DEFINE_HANDLE_ALLOC(SageGPUCommandPool, cmd_pools, cmd_pool_count, cmd_pool_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUCommandBuffer, cmd_buffers, cmd_buffer_cap)
DEFINE_HANDLE_ALLOC(SageGPUCommandBuffer, cmd_buffers, cmd_buffer_count, cmd_buffer_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUFence, fences, fence_cap)
DEFINE_HANDLE_ALLOC(SageGPUFence, fences, fence_count, fence_cap)

DEFINE_HANDLE_TABLE_GROW(SageGPUSemaphore, semaphores, semaphore_cap)
DEFINE_HANDLE_ALLOC(SageGPUSemaphore, semaphores, semaphore_count, semaphore_cap)

// ============================================================================
// Translation Helpers
// ============================================================================

VkFormat sage_gpu_translate_format(int sage_format) {
    switch (sage_format) {
        case SAGE_FORMAT_RGBA8:      return VK_FORMAT_R8G8B8A8_UNORM;
        case SAGE_FORMAT_RGBA16F:    return VK_FORMAT_R16G16B16A16_SFLOAT;
        case SAGE_FORMAT_RGBA32F:    return VK_FORMAT_R32G32B32A32_SFLOAT;
        case SAGE_FORMAT_R32F:       return VK_FORMAT_R32_SFLOAT;
        case SAGE_FORMAT_RG32F:      return VK_FORMAT_R32G32_SFLOAT;
        case SAGE_FORMAT_DEPTH32F:   return VK_FORMAT_D32_SFLOAT;
        case SAGE_FORMAT_DEPTH24_S8: return VK_FORMAT_D24_UNORM_S8_UINT;
        case SAGE_FORMAT_R8:         return VK_FORMAT_R8_UNORM;
        case SAGE_FORMAT_RG8:        return VK_FORMAT_R8G8_UNORM;
        case SAGE_FORMAT_BGRA8:      return VK_FORMAT_B8G8R8A8_UNORM;
        case SAGE_FORMAT_R32U:       return VK_FORMAT_R32_UINT;
        case SAGE_FORMAT_RG16F:      return VK_FORMAT_R16G16_SFLOAT;
        case SAGE_FORMAT_R16F:       return VK_FORMAT_R16_SFLOAT;
        default: return VK_FORMAT_R8G8B8A8_UNORM;
    }
}

int sage_gpu_format_size(int sage_format) {
    switch (sage_format) {
        case SAGE_FORMAT_RGBA8:      return 4;
        case SAGE_FORMAT_RGBA16F:    return 8;
        case SAGE_FORMAT_RGBA32F:    return 16;
        case SAGE_FORMAT_R32F:       return 4;
        case SAGE_FORMAT_RG32F:      return 8;
        case SAGE_FORMAT_DEPTH32F:   return 4;
        case SAGE_FORMAT_DEPTH24_S8: return 4;
        case SAGE_FORMAT_R8:         return 1;
        case SAGE_FORMAT_RG8:        return 2;
        case SAGE_FORMAT_BGRA8:      return 4;
        case SAGE_FORMAT_R32U:       return 4;
        case SAGE_FORMAT_RG16F:      return 4;
        case SAGE_FORMAT_R16F:       return 2;
        default: return 4;
    }
}

VkShaderStageFlagBits sage_gpu_translate_stage(int sage_stage) {
    VkShaderStageFlagBits flags = 0;
    if (sage_stage & SAGE_STAGE_VERTEX)    flags |= VK_SHADER_STAGE_VERTEX_BIT;
    if (sage_stage & SAGE_STAGE_FRAGMENT)  flags |= VK_SHADER_STAGE_FRAGMENT_BIT;
    if (sage_stage & SAGE_STAGE_COMPUTE)   flags |= VK_SHADER_STAGE_COMPUTE_BIT;
    if (sage_stage & SAGE_STAGE_GEOMETRY)  flags |= VK_SHADER_STAGE_GEOMETRY_BIT;
    if (sage_stage & SAGE_STAGE_TESS_CTRL) flags |= VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
    if (sage_stage & SAGE_STAGE_TESS_EVAL) flags |= VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
    return flags;
}

VkDescriptorType sage_gpu_translate_desc_type(int sage_desc_type) {
    switch (sage_desc_type) {
        case SAGE_DESC_STORAGE_BUFFER:  return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        case SAGE_DESC_UNIFORM_BUFFER:  return VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        case SAGE_DESC_SAMPLED_IMAGE:   return VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
        case SAGE_DESC_STORAGE_IMAGE:   return VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
        case SAGE_DESC_SAMPLER:         return VK_DESCRIPTOR_TYPE_SAMPLER;
        case SAGE_DESC_COMBINED_SAMPLER:return VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        case SAGE_DESC_INPUT_ATTACHMENT:return VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
        default: return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    }
}

static VkBufferUsageFlags translate_buffer_usage(int usage) {
    VkBufferUsageFlags flags = 0;
    if (usage & SAGE_BUFFER_STORAGE)      flags |= VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if (usage & SAGE_BUFFER_UNIFORM)      flags |= VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if (usage & SAGE_BUFFER_VERTEX)       flags |= VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if (usage & SAGE_BUFFER_INDEX)        flags |= VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (usage & SAGE_BUFFER_INDIRECT)     flags |= VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
    if (usage & SAGE_BUFFER_TRANSFER_SRC) flags |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (usage & SAGE_BUFFER_TRANSFER_DST) flags |= VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    if (usage & SAGE_BUFFER_STAGING)      flags |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    return flags;
}

static VkMemoryPropertyFlags translate_mem_props(int props) {
    VkMemoryPropertyFlags flags = 0;
    if (props & SAGE_MEMORY_DEVICE_LOCAL)  flags |= VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    if (props & SAGE_MEMORY_HOST_VISIBLE)  flags |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
    if (props & SAGE_MEMORY_HOST_COHERENT) flags |= VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    return flags;
}

static VkImageUsageFlags translate_image_usage(int usage) {
    VkImageUsageFlags flags = 0;
    if (usage & SAGE_IMAGE_SAMPLED)      flags |= VK_IMAGE_USAGE_SAMPLED_BIT;
    if (usage & SAGE_IMAGE_STORAGE)      flags |= VK_IMAGE_USAGE_STORAGE_BIT;
    if (usage & SAGE_IMAGE_COLOR_ATTACH) flags |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if (usage & SAGE_IMAGE_DEPTH_ATTACH) flags |= VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    if (usage & SAGE_IMAGE_TRANSFER_SRC) flags |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (usage & SAGE_IMAGE_TRANSFER_DST) flags |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (usage & SAGE_IMAGE_INPUT_ATTACH) flags |= VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT;
    return flags;
}

static VkFilter translate_filter(int filter) {
    return (filter == SAGE_FILTER_LINEAR) ? VK_FILTER_LINEAR : VK_FILTER_NEAREST;
}

static VkSamplerAddressMode translate_address_mode(int mode) {
    switch (mode) {
        case SAGE_ADDRESS_MIRRORED_REPEAT: return VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT;
        case SAGE_ADDRESS_CLAMP_EDGE:      return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        case SAGE_ADDRESS_CLAMP_BORDER:    return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
        default: return VK_SAMPLER_ADDRESS_MODE_REPEAT;
    }
}

static VkImageLayout translate_layout(int layout) {
    switch (layout) {
        case SAGE_LAYOUT_UNDEFINED:    return VK_IMAGE_LAYOUT_UNDEFINED;
        case SAGE_LAYOUT_GENERAL:      return VK_IMAGE_LAYOUT_GENERAL;
        case SAGE_LAYOUT_COLOR_ATTACH: return VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        case SAGE_LAYOUT_DEPTH_ATTACH: return VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        case SAGE_LAYOUT_SHADER_READ:  return VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        case SAGE_LAYOUT_TRANSFER_SRC: return VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        case SAGE_LAYOUT_TRANSFER_DST: return VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        case SAGE_LAYOUT_PRESENT:      return VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        default: return VK_IMAGE_LAYOUT_UNDEFINED;
    }
}

static VkAttachmentLoadOp translate_load_op(int op) {
    switch (op) {
        case SAGE_LOAD_CLEAR:    return VK_ATTACHMENT_LOAD_OP_CLEAR;
        case SAGE_LOAD_LOAD:     return VK_ATTACHMENT_LOAD_OP_LOAD;
        case SAGE_LOAD_DONTCARE: return VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        default: return VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    }
}

static VkAttachmentStoreOp translate_store_op(int op) {
    switch (op) {
        case SAGE_STORE_STORE:    return VK_ATTACHMENT_STORE_OP_STORE;
        case SAGE_STORE_DONTCARE: return VK_ATTACHMENT_STORE_OP_DONT_CARE;
        default: return VK_ATTACHMENT_STORE_OP_DONT_CARE;
    }
}

static VkCompareOp translate_compare_op(int op) {
    switch (op) {
        case SAGE_COMPARE_NEVER:   return VK_COMPARE_OP_NEVER;
        case SAGE_COMPARE_LESS:    return VK_COMPARE_OP_LESS;
        case SAGE_COMPARE_EQUAL:   return VK_COMPARE_OP_EQUAL;
        case SAGE_COMPARE_LEQUAL:  return VK_COMPARE_OP_LESS_OR_EQUAL;
        case SAGE_COMPARE_GREATER: return VK_COMPARE_OP_GREATER;
        case SAGE_COMPARE_NEQUAL:  return VK_COMPARE_OP_NOT_EQUAL;
        case SAGE_COMPARE_GEQUAL:  return VK_COMPARE_OP_GREATER_OR_EQUAL;
        case SAGE_COMPARE_ALWAYS:  return VK_COMPARE_OP_ALWAYS;
        default: return VK_COMPARE_OP_LESS;
    }
}

static VkPipelineStageFlags translate_pipeline_stage(int stage) {
    VkPipelineStageFlags flags = 0;
    if (stage & SAGE_PIPE_TOP)           flags |= VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    if (stage & SAGE_PIPE_DRAW_INDIRECT) flags |= VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT;
    if (stage & SAGE_PIPE_VERTEX_INPUT)  flags |= VK_PIPELINE_STAGE_VERTEX_INPUT_BIT;
    if (stage & SAGE_PIPE_VERTEX_SHADER) flags |= VK_PIPELINE_STAGE_VERTEX_SHADER_BIT;
    if (stage & SAGE_PIPE_FRAGMENT)      flags |= VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    if (stage & SAGE_PIPE_EARLY_DEPTH)   flags |= VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    if (stage & SAGE_PIPE_LATE_DEPTH)    flags |= VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
    if (stage & SAGE_PIPE_COLOR_OUTPUT)  flags |= VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    if (stage & SAGE_PIPE_COMPUTE)       flags |= VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
    if (stage & SAGE_PIPE_TRANSFER)      flags |= VK_PIPELINE_STAGE_TRANSFER_BIT;
    if (stage & SAGE_PIPE_BOTTOM)        flags |= VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    if (stage & SAGE_PIPE_HOST)          flags |= VK_PIPELINE_STAGE_HOST_BIT;
    if (stage & SAGE_PIPE_ALL_GRAPHICS)  flags |= VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT;
    if (stage & SAGE_PIPE_ALL_COMMANDS)  flags |= VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    return flags;
}

static VkAccessFlags translate_access(int access) {
    VkAccessFlags flags = 0;
    if (access & SAGE_ACCESS_SHADER_READ)    flags |= VK_ACCESS_SHADER_READ_BIT;
    if (access & SAGE_ACCESS_SHADER_WRITE)   flags |= VK_ACCESS_SHADER_WRITE_BIT;
    if (access & SAGE_ACCESS_COLOR_READ)     flags |= VK_ACCESS_COLOR_ATTACHMENT_READ_BIT;
    if (access & SAGE_ACCESS_COLOR_WRITE)    flags |= VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    if (access & SAGE_ACCESS_DEPTH_READ)     flags |= VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT;
    if (access & SAGE_ACCESS_DEPTH_WRITE)    flags |= VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    if (access & SAGE_ACCESS_TRANSFER_READ)  flags |= VK_ACCESS_TRANSFER_READ_BIT;
    if (access & SAGE_ACCESS_TRANSFER_WRITE) flags |= VK_ACCESS_TRANSFER_WRITE_BIT;
    if (access & SAGE_ACCESS_HOST_READ)      flags |= VK_ACCESS_HOST_READ_BIT;
    if (access & SAGE_ACCESS_HOST_WRITE)     flags |= VK_ACCESS_HOST_WRITE_BIT;
    if (access & SAGE_ACCESS_MEMORY_READ)    flags |= VK_ACCESS_MEMORY_READ_BIT;
    if (access & SAGE_ACCESS_MEMORY_WRITE)   flags |= VK_ACCESS_MEMORY_WRITE_BIT;
    if (access & SAGE_ACCESS_INDIRECT_READ)  flags |= VK_ACCESS_INDIRECT_COMMAND_READ_BIT;
    if (access & SAGE_ACCESS_INDEX_READ)     flags |= VK_ACCESS_INDEX_READ_BIT;
    if (access & SAGE_ACCESS_VERTEX_READ)    flags |= VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT;
    if (access & SAGE_ACCESS_UNIFORM_READ)   flags |= VK_ACCESS_UNIFORM_READ_BIT;
    return flags;
}

static VkFormat translate_attr_format(int attr_fmt) {
    switch (attr_fmt) {
        case SAGE_ATTR_FLOAT: return VK_FORMAT_R32_SFLOAT;
        case SAGE_ATTR_VEC2:  return VK_FORMAT_R32G32_SFLOAT;
        case SAGE_ATTR_VEC3:  return VK_FORMAT_R32G32B32_SFLOAT;
        case SAGE_ATTR_VEC4:  return VK_FORMAT_R32G32B32A32_SFLOAT;
        case SAGE_ATTR_INT:   return VK_FORMAT_R32_SINT;
        case SAGE_ATTR_IVEC2: return VK_FORMAT_R32G32_SINT;
        case SAGE_ATTR_IVEC3: return VK_FORMAT_R32G32B32_SINT;
        case SAGE_ATTR_IVEC4: return VK_FORMAT_R32G32B32A32_SINT;
        case SAGE_ATTR_UINT:  return VK_FORMAT_R32_UINT;
        default: return VK_FORMAT_R32G32B32A32_SFLOAT;
    }
}

static int attr_format_size(int attr_fmt) {
    switch (attr_fmt) {
        case SAGE_ATTR_FLOAT: return 4;
        case SAGE_ATTR_VEC2:  return 8;
        case SAGE_ATTR_VEC3:  return 12;
        case SAGE_ATTR_VEC4:  return 16;
        case SAGE_ATTR_INT:   return 4;
        case SAGE_ATTR_IVEC2: return 8;
        case SAGE_ATTR_IVEC3: return 12;
        case SAGE_ATTR_IVEC4: return 16;
        case SAGE_ATTR_UINT:  return 4;
        default: return 16;
    }
}

uint32_t sage_gpu_find_memory_type(uint32_t type_filter, VkMemoryPropertyFlags properties) {
    for (uint32_t i = 0; i < g_gpu_ctx.mem_props.memoryTypeCount; i++) {
        if ((type_filter & (1 << i)) &&
            (g_gpu_ctx.mem_props.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    fprintf(stderr, "gpu: failed to find suitable memory type\n");
    return 0;
}

// ============================================================================
// Validation Layer Debug Callback
// ============================================================================

static VKAPI_ATTR VkBool32 VKAPI_CALL debug_callback(
    VkDebugUtilsMessageSeverityFlagBitsEXT severity,
    VkDebugUtilsMessageTypeFlagsEXT type,
    const VkDebugUtilsMessengerCallbackDataEXT* data,
    void* user_data)
{
    (void)type; (void)user_data;
    if (severity >= VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        fprintf(stderr, "[Vulkan] %s\n", data->pMessage);
    }
    return VK_FALSE;
}

// ============================================================================
// Context Lifecycle
// ============================================================================

// gpu.has_vulkan() -> true
static Value gpu_has_vulkan(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_bool(1);
}

// gpu.init(app_name?, validation?) -> bool
static Value gpu_init(int argCount, Value* args) {
    if (g_gpu_ctx.initialized) {
        fprintf(stderr, "gpu: already initialized\n");
        return val_bool(1);
    }

    const char* app_name = "SageLang GPU";
    int validation = 0;

    if (argCount >= 1 && IS_STRING(args[0])) {
        app_name = AS_STRING(args[0]);
    }
    if (argCount >= 2 && IS_BOOL(args[1])) {
        validation = AS_BOOL(args[1]);
    }

    // --- Create instance ---
    VkApplicationInfo app_info = {0};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = app_name;
    app_info.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    app_info.pEngineName = "SageLang";
    app_info.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo create_info = {0};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;

    const char* validation_layers[] = {"VK_LAYER_KHRONOS_validation"};
    const char* debug_ext[] = {VK_EXT_DEBUG_UTILS_EXTENSION_NAME};

    if (validation) {
        create_info.enabledLayerCount = 1;
        create_info.ppEnabledLayerNames = validation_layers;
        create_info.enabledExtensionCount = 1;
        create_info.ppEnabledExtensionNames = debug_ext;
        g_gpu_ctx.validation_enabled = 1;
    }

    VkResult res = vkCreateInstance(&create_info, NULL, &g_gpu_ctx.instance);
    if (res != VK_SUCCESS) {
        fprintf(stderr, "gpu: vkCreateInstance failed (%d)\n", res);
        return val_bool(0);
    }

    // --- Debug messenger ---
    if (validation) {
        PFN_vkCreateDebugUtilsMessengerEXT createDebug =
            (PFN_vkCreateDebugUtilsMessengerEXT)vkGetInstanceProcAddr(
                g_gpu_ctx.instance, "vkCreateDebugUtilsMessengerEXT");
        if (createDebug) {
            VkDebugUtilsMessengerCreateInfoEXT dbg_info = {0};
            dbg_info.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
            dbg_info.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                                       VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
            dbg_info.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                                    VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                                    VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
            dbg_info.pfnUserCallback = debug_callback;
            createDebug(g_gpu_ctx.instance, &dbg_info, NULL, &g_gpu_ctx.debug_messenger);
        }
    }

    // --- Pick physical device ---
    uint32_t dev_count = 0;
    vkEnumeratePhysicalDevices(g_gpu_ctx.instance, &dev_count, NULL);
    if (dev_count == 0) {
        fprintf(stderr, "gpu: no Vulkan-capable GPU found\n");
        return val_bool(0);
    }

    VkPhysicalDevice* devices = calloc(dev_count, sizeof(VkPhysicalDevice));
    vkEnumeratePhysicalDevices(g_gpu_ctx.instance, &dev_count, devices);

    // Prefer discrete GPU
    g_gpu_ctx.physical_device = devices[0];
    for (uint32_t i = 0; i < dev_count; i++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devices[i], &props);
        if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            g_gpu_ctx.physical_device = devices[i];
            break;
        }
    }
    free(devices);

    vkGetPhysicalDeviceProperties(g_gpu_ctx.physical_device, &g_gpu_ctx.device_props);
    vkGetPhysicalDeviceMemoryProperties(g_gpu_ctx.physical_device, &g_gpu_ctx.mem_props);

    // --- Find queue families ---
    uint32_t qf_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(g_gpu_ctx.physical_device, &qf_count, NULL);
    VkQueueFamilyProperties* qf_props = calloc(qf_count, sizeof(VkQueueFamilyProperties));
    vkGetPhysicalDeviceQueueFamilyProperties(g_gpu_ctx.physical_device, &qf_count, qf_props);

    g_gpu_ctx.graphics_family = UINT32_MAX;
    g_gpu_ctx.compute_family  = UINT32_MAX;
    g_gpu_ctx.transfer_family = UINT32_MAX;

    for (uint32_t i = 0; i < qf_count; i++) {
        if ((qf_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && g_gpu_ctx.graphics_family == UINT32_MAX) {
            g_gpu_ctx.graphics_family = i;
        }
        // Prefer dedicated compute queue
        if ((qf_props[i].queueFlags & VK_QUEUE_COMPUTE_BIT) &&
            !(qf_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) &&
            g_gpu_ctx.compute_family == UINT32_MAX) {
            g_gpu_ctx.compute_family = i;
        }
        // Prefer dedicated transfer queue
        if ((qf_props[i].queueFlags & VK_QUEUE_TRANSFER_BIT) &&
            !(qf_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) &&
            !(qf_props[i].queueFlags & VK_QUEUE_COMPUTE_BIT) &&
            g_gpu_ctx.transfer_family == UINT32_MAX) {
            g_gpu_ctx.transfer_family = i;
        }
    }
    free(qf_props);

    // Fallback: use graphics family for compute/transfer
    if (g_gpu_ctx.compute_family == UINT32_MAX)  g_gpu_ctx.compute_family = g_gpu_ctx.graphics_family;
    if (g_gpu_ctx.transfer_family == UINT32_MAX) g_gpu_ctx.transfer_family = g_gpu_ctx.graphics_family;

    if (g_gpu_ctx.graphics_family == UINT32_MAX) {
        fprintf(stderr, "gpu: no graphics queue family found\n");
        return val_bool(0);
    }

    // --- Create logical device ---
    // Collect unique queue families
    uint32_t unique_families[3];
    int unique_count = 0;
    unique_families[unique_count++] = g_gpu_ctx.graphics_family;
    if (g_gpu_ctx.compute_family != g_gpu_ctx.graphics_family) {
        unique_families[unique_count++] = g_gpu_ctx.compute_family;
    }
    if (g_gpu_ctx.transfer_family != g_gpu_ctx.graphics_family &&
        g_gpu_ctx.transfer_family != g_gpu_ctx.compute_family) {
        unique_families[unique_count++] = g_gpu_ctx.transfer_family;
    }

    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_infos[3] = {0};
    for (int i = 0; i < unique_count; i++) {
        queue_infos[i].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_infos[i].queueFamilyIndex = unique_families[i];
        queue_infos[i].queueCount = 1;
        queue_infos[i].pQueuePriorities = &priority;
    }

    VkPhysicalDeviceFeatures features = {0};
    features.fillModeNonSolid = VK_TRUE;  // wireframe support

    VkDeviceCreateInfo dev_info = {0};
    dev_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dev_info.queueCreateInfoCount = (uint32_t)unique_count;
    dev_info.pQueueCreateInfos = queue_infos;
    dev_info.pEnabledFeatures = &features;

    res = vkCreateDevice(g_gpu_ctx.physical_device, &dev_info, NULL, &g_gpu_ctx.device);
    if (res != VK_SUCCESS) {
        fprintf(stderr, "gpu: vkCreateDevice failed (%d)\n", res);
        return val_bool(0);
    }

    vkGetDeviceQueue(g_gpu_ctx.device, g_gpu_ctx.graphics_family, 0, &g_gpu_ctx.graphics_queue);
    vkGetDeviceQueue(g_gpu_ctx.device, g_gpu_ctx.compute_family, 0, &g_gpu_ctx.compute_queue);
    vkGetDeviceQueue(g_gpu_ctx.device, g_gpu_ctx.transfer_family, 0, &g_gpu_ctx.transfer_queue);

    g_gpu_ctx.initialized = 1;
    return val_bool(1);
}

// gpu.shutdown()
static Value gpu_shutdown(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized) return val_nil();

    vkDeviceWaitIdle(g_gpu_ctx.device);

    // Destroy all tracked resources in reverse dependency order
    for (int i = 0; i < g_gpu_ctx.pipeline_count; i++) {
        if (g_gpu_ctx.pipelines[i].alive)
            vkDestroyPipeline(g_gpu_ctx.device, g_gpu_ctx.pipelines[i].pipeline, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.pipe_layout_count; i++) {
        if (g_gpu_ctx.pipe_layouts[i].alive)
            vkDestroyPipelineLayout(g_gpu_ctx.device, g_gpu_ctx.pipe_layouts[i].layout, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.framebuffer_count; i++) {
        if (g_gpu_ctx.framebuffers[i].alive)
            vkDestroyFramebuffer(g_gpu_ctx.device, g_gpu_ctx.framebuffers[i].framebuffer, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.render_pass_count; i++) {
        if (g_gpu_ctx.render_passes[i].alive)
            vkDestroyRenderPass(g_gpu_ctx.device, g_gpu_ctx.render_passes[i].render_pass, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.desc_pool_count; i++) {
        if (g_gpu_ctx.desc_pools[i].alive)
            vkDestroyDescriptorPool(g_gpu_ctx.device, g_gpu_ctx.desc_pools[i].pool, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.desc_layout_count; i++) {
        if (g_gpu_ctx.desc_layouts[i].alive)
            vkDestroyDescriptorSetLayout(g_gpu_ctx.device, g_gpu_ctx.desc_layouts[i].layout, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.sampler_count; i++) {
        if (g_gpu_ctx.samplers[i].alive)
            vkDestroySampler(g_gpu_ctx.device, g_gpu_ctx.samplers[i].sampler, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.image_count; i++) {
        if (g_gpu_ctx.images[i].alive) {
            if (g_gpu_ctx.images[i].view)
                vkDestroyImageView(g_gpu_ctx.device, g_gpu_ctx.images[i].view, NULL);
            vkDestroyImage(g_gpu_ctx.device, g_gpu_ctx.images[i].image, NULL);
            vkFreeMemory(g_gpu_ctx.device, g_gpu_ctx.images[i].memory, NULL);
        }
    }
    for (int i = 0; i < g_gpu_ctx.buffer_count; i++) {
        if (g_gpu_ctx.buffers[i].alive) {
            vkDestroyBuffer(g_gpu_ctx.device, g_gpu_ctx.buffers[i].buffer, NULL);
            vkFreeMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[i].memory, NULL);
        }
    }
    for (int i = 0; i < g_gpu_ctx.shader_count; i++) {
        if (g_gpu_ctx.shaders[i].alive)
            vkDestroyShaderModule(g_gpu_ctx.device, g_gpu_ctx.shaders[i].module, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.cmd_pool_count; i++) {
        if (g_gpu_ctx.cmd_pools[i].alive)
            vkDestroyCommandPool(g_gpu_ctx.device, g_gpu_ctx.cmd_pools[i].pool, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.fence_count; i++) {
        if (g_gpu_ctx.fences[i].alive)
            vkDestroyFence(g_gpu_ctx.device, g_gpu_ctx.fences[i].fence, NULL);
    }
    for (int i = 0; i < g_gpu_ctx.semaphore_count; i++) {
        if (g_gpu_ctx.semaphores[i].alive)
            vkDestroySemaphore(g_gpu_ctx.device, g_gpu_ctx.semaphores[i].semaphore, NULL);
    }

    // Free handle tables
    free(g_gpu_ctx.buffers);
    free(g_gpu_ctx.images);
    free(g_gpu_ctx.samplers);
    free(g_gpu_ctx.shaders);
    free(g_gpu_ctx.desc_layouts);
    free(g_gpu_ctx.desc_pools);
    free(g_gpu_ctx.desc_sets);
    free(g_gpu_ctx.pipe_layouts);
    free(g_gpu_ctx.pipelines);
    free(g_gpu_ctx.render_passes);
    free(g_gpu_ctx.framebuffers);
    free(g_gpu_ctx.cmd_pools);
    free(g_gpu_ctx.cmd_buffers);
    free(g_gpu_ctx.fences);
    free(g_gpu_ctx.semaphores);

    vkDestroyDevice(g_gpu_ctx.device, NULL);

    if (g_gpu_ctx.validation_enabled && g_gpu_ctx.debug_messenger) {
        PFN_vkDestroyDebugUtilsMessengerEXT destroyDebug =
            (PFN_vkDestroyDebugUtilsMessengerEXT)vkGetInstanceProcAddr(
                g_gpu_ctx.instance, "vkDestroyDebugUtilsMessengerEXT");
        if (destroyDebug) destroyDebug(g_gpu_ctx.instance, g_gpu_ctx.debug_messenger, NULL);
    }

    vkDestroyInstance(g_gpu_ctx.instance, NULL);
    memset(&g_gpu_ctx, 0, sizeof(g_gpu_ctx));
    return val_nil();
}

// gpu.device_name() -> string
static Value gpu_device_name(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized) return val_string("<not initialized>");
    return val_string(g_gpu_ctx.device_props.deviceName);
}

// gpu.device_limits() -> dict
static Value gpu_device_limits(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized) return val_nil();

    Value d = val_dict();
    VkPhysicalDeviceLimits* lim = &g_gpu_ctx.device_props.limits;
    dict_set(&d, "maxComputeWorkGroupCount_x", val_number(lim->maxComputeWorkGroupCount[0]));
    dict_set(&d, "maxComputeWorkGroupCount_y", val_number(lim->maxComputeWorkGroupCount[1]));
    dict_set(&d, "maxComputeWorkGroupCount_z", val_number(lim->maxComputeWorkGroupCount[2]));
    dict_set(&d, "maxComputeWorkGroupSize_x", val_number(lim->maxComputeWorkGroupSize[0]));
    dict_set(&d, "maxComputeWorkGroupSize_y", val_number(lim->maxComputeWorkGroupSize[1]));
    dict_set(&d, "maxComputeWorkGroupSize_z", val_number(lim->maxComputeWorkGroupSize[2]));
    dict_set(&d, "maxComputeWorkGroupInvocations", val_number(lim->maxComputeWorkGroupInvocations));
    dict_set(&d, "maxPushConstantsSize", val_number(lim->maxPushConstantsSize));
    dict_set(&d, "maxBoundDescriptorSets", val_number(lim->maxBoundDescriptorSets));
    dict_set(&d, "maxStorageBufferRange", val_number((double)lim->maxStorageBufferRange));
    dict_set(&d, "maxUniformBufferRange", val_number((double)lim->maxUniformBufferRange));
    dict_set(&d, "maxImageDimension2D", val_number(lim->maxImageDimension2D));
    dict_set(&d, "maxImageDimension3D", val_number(lim->maxImageDimension3D));
    dict_set(&d, "maxFramebufferWidth", val_number(lim->maxFramebufferWidth));
    dict_set(&d, "maxFramebufferHeight", val_number(lim->maxFramebufferHeight));
    dict_set(&d, "maxColorAttachments", val_number(lim->maxColorAttachments));
    dict_set(&d, "maxVertexInputAttributes", val_number(lim->maxVertexInputAttributes));
    dict_set(&d, "maxDescriptorSetStorageBuffers", val_number(lim->maxDescriptorSetStorageBuffers));
    return d;
}

// ============================================================================
// Buffers
// ============================================================================

// gpu.create_buffer(size, usage, memory) -> handle
static Value gpu_create_buffer(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 3) return val_number(SAGE_GPU_INVALID_HANDLE);
    if (!IS_NUMBER(args[0]) || !IS_NUMBER(args[1]) || !IS_NUMBER(args[2]))
        return val_number(SAGE_GPU_INVALID_HANDLE);

    VkDeviceSize size = (VkDeviceSize)AS_NUMBER(args[0]);
    int usage = (int)AS_NUMBER(args[1]);
    int mem = (int)AS_NUMBER(args[2]);

    int idx = alloc_buffers();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkBufferCreateInfo buf_info = {0};
    buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buf_info.size = size;
    buf_info.usage = translate_buffer_usage(usage);
    buf_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (vkCreateBuffer(g_gpu_ctx.device, &buf_info, NULL, &g_gpu_ctx.buffers[idx].buffer) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    VkMemoryRequirements mem_req;
    vkGetBufferMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, &mem_req);

    VkMemoryAllocateInfo alloc_info = {0};
    alloc_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_req.size;
    alloc_info.memoryTypeIndex = sage_gpu_find_memory_type(mem_req.memoryTypeBits, translate_mem_props(mem));

    if (vkAllocateMemory(g_gpu_ctx.device, &alloc_info, NULL, &g_gpu_ctx.buffers[idx].memory) != VK_SUCCESS) {
        vkDestroyBuffer(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    vkBindBufferMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, g_gpu_ctx.buffers[idx].memory, 0);

    g_gpu_ctx.buffers[idx].size = size;
    g_gpu_ctx.buffers[idx].usage = usage;
    g_gpu_ctx.buffers[idx].mem_props = mem;
    g_gpu_ctx.buffers[idx].alive = 1;

    // Auto-map host-visible buffers
    if (mem & SAGE_MEMORY_HOST_VISIBLE) {
        vkMapMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory, 0, size, 0,
                     &g_gpu_ctx.buffers[idx].mapped);
    }

    return val_number(idx);
}

// gpu.destroy_buffer(handle)
static Value gpu_destroy_buffer(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[idx].alive) return val_nil();

    if (g_gpu_ctx.buffers[idx].mapped) {
        vkUnmapMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory);
    }
    vkDestroyBuffer(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, NULL);
    vkFreeMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory, NULL);
    g_gpu_ctx.buffers[idx].alive = 0;
    return val_nil();
}

// gpu.buffer_upload(handle, data_array) -> bool
// data_array is array of numbers (floats packed as 4 bytes each)
static Value gpu_buffer_upload(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_bool(0);
    if (!IS_NUMBER(args[0]) || !IS_ARRAY(args[1])) return val_bool(0);

    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[idx].alive) return val_bool(0);

    ArrayValue* arr = args[1].as.array;
    size_t data_size = sizeof(float) * (size_t)arr->count;
    if (data_size > (size_t)g_gpu_ctx.buffers[idx].size) {
        data_size = (size_t)g_gpu_ctx.buffers[idx].size;
    }

    void* mapped = g_gpu_ctx.buffers[idx].mapped;
    if (!mapped) {
        // Temporarily map
        if (vkMapMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory, 0,
                        g_gpu_ctx.buffers[idx].size, 0, &mapped) != VK_SUCCESS) {
            return val_bool(0);
        }
    }

    float* dst = (float*)mapped;
    int count = (int)(data_size / sizeof(float));
    for (int i = 0; i < count && i < arr->count; i++) {
        if (IS_NUMBER(arr->elements[i])) {
            dst[i] = (float)AS_NUMBER(arr->elements[i]);
        } else {
            dst[i] = 0.0f;
        }
    }

    if (!g_gpu_ctx.buffers[idx].mapped) {
        vkUnmapMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory);
    }
    return val_bool(1);
}

// gpu.buffer_download(handle) -> array of numbers
static Value gpu_buffer_download(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_array();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[idx].alive) return val_array();

    void* mapped = g_gpu_ctx.buffers[idx].mapped;
    int need_unmap = 0;
    if (!mapped) {
        if (vkMapMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory, 0,
                        g_gpu_ctx.buffers[idx].size, 0, &mapped) != VK_SUCCESS) {
            return val_array();
        }
        need_unmap = 1;
    }

    Value result = val_array();
    float* src = (float*)mapped;
    int count = (int)(g_gpu_ctx.buffers[idx].size / sizeof(float));
    for (int i = 0; i < count; i++) {
        array_push(&result, val_number((double)src[i]));
    }

    if (need_unmap) {
        vkUnmapMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory);
    }
    return result;
}

// gpu.buffer_size(handle) -> number
static Value gpu_buffer_size(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_number(0);
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[idx].alive) return val_number(0);
    return val_number((double)g_gpu_ctx.buffers[idx].size);
}

// ============================================================================
// Images
// ============================================================================

// gpu.create_image(width, height, depth, format, usage) -> handle
static Value gpu_create_image(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 5) return val_number(SAGE_GPU_INVALID_HANDLE);
    for (int i = 0; i < 5; i++) {
        if (!IS_NUMBER(args[i])) return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    int w = (int)AS_NUMBER(args[0]);
    int h = (int)AS_NUMBER(args[1]);
    int d = (int)AS_NUMBER(args[2]);
    int format = (int)AS_NUMBER(args[3]);
    int usage = (int)AS_NUMBER(args[4]);

    int idx = alloc_images();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkImageType img_type = VK_IMAGE_TYPE_2D;
    VkImageViewType view_type = VK_IMAGE_VIEW_TYPE_2D;
    if (d > 1) {
        img_type = VK_IMAGE_TYPE_3D;
        view_type = VK_IMAGE_VIEW_TYPE_3D;
    } else if (h <= 1 && d <= 1) {
        img_type = VK_IMAGE_TYPE_1D;
        view_type = VK_IMAGE_VIEW_TYPE_1D;
    }

    VkImageCreateInfo img_info = {0};
    img_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    img_info.imageType = img_type;
    img_info.format = sage_gpu_translate_format(format);
    img_info.extent.width = (uint32_t)w;
    img_info.extent.height = (uint32_t)(h > 0 ? h : 1);
    img_info.extent.depth = (uint32_t)(d > 0 ? d : 1);
    img_info.mipLevels = 1;
    img_info.arrayLayers = 1;
    img_info.samples = VK_SAMPLE_COUNT_1_BIT;
    img_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    img_info.usage = translate_image_usage(usage);
    img_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    img_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (vkCreateImage(g_gpu_ctx.device, &img_info, NULL, &g_gpu_ctx.images[idx].image) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    VkMemoryRequirements mem_req;
    vkGetImageMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, &mem_req);

    VkMemoryAllocateInfo alloc_info = {0};
    alloc_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_req.size;
    alloc_info.memoryTypeIndex = sage_gpu_find_memory_type(mem_req.memoryTypeBits,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    if (vkAllocateMemory(g_gpu_ctx.device, &alloc_info, NULL, &g_gpu_ctx.images[idx].memory) != VK_SUCCESS) {
        vkDestroyImage(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    vkBindImageMemory(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, g_gpu_ctx.images[idx].memory, 0);

    // Auto-create image view
    VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == SAGE_FORMAT_DEPTH32F || format == SAGE_FORMAT_DEPTH24_S8) {
        aspect = VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    VkImageViewCreateInfo view_info = {0};
    view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = g_gpu_ctx.images[idx].image;
    view_info.viewType = view_type;
    view_info.format = img_info.format;
    view_info.subresourceRange.aspectMask = aspect;
    view_info.subresourceRange.baseMipLevel = 0;
    view_info.subresourceRange.levelCount = 1;
    view_info.subresourceRange.baseArrayLayer = 0;
    view_info.subresourceRange.layerCount = 1;

    vkCreateImageView(g_gpu_ctx.device, &view_info, NULL, &g_gpu_ctx.images[idx].view);

    g_gpu_ctx.images[idx].format = format;
    g_gpu_ctx.images[idx].width = w;
    g_gpu_ctx.images[idx].height = h;
    g_gpu_ctx.images[idx].depth = d;
    g_gpu_ctx.images[idx].mip_levels = 1;
    g_gpu_ctx.images[idx].array_layers = 1;
    g_gpu_ctx.images[idx].usage = usage;
    g_gpu_ctx.images[idx].alive = 1;

    return val_number(idx);
}

// gpu.destroy_image(handle)
static Value gpu_destroy_image(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.image_count || !g_gpu_ctx.images[idx].alive) return val_nil();

    if (g_gpu_ctx.images[idx].view)
        vkDestroyImageView(g_gpu_ctx.device, g_gpu_ctx.images[idx].view, NULL);
    vkDestroyImage(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, NULL);
    vkFreeMemory(g_gpu_ctx.device, g_gpu_ctx.images[idx].memory, NULL);
    g_gpu_ctx.images[idx].alive = 0;
    return val_nil();
}

// gpu.image_dims(handle) -> dict {width, height, depth}
static Value gpu_image_dims(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.image_count || !g_gpu_ctx.images[idx].alive) return val_nil();

    Value d = val_dict();
    dict_set(&d, "width", val_number(g_gpu_ctx.images[idx].width));
    dict_set(&d, "height", val_number(g_gpu_ctx.images[idx].height));
    dict_set(&d, "depth", val_number(g_gpu_ctx.images[idx].depth));
    return d;
}

// ============================================================================
// Samplers
// ============================================================================

// gpu.create_sampler(mag, min, address) -> handle
static Value gpu_create_sampler(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 3) return val_number(SAGE_GPU_INVALID_HANDLE);

    int mag = IS_NUMBER(args[0]) ? (int)AS_NUMBER(args[0]) : SAGE_FILTER_LINEAR;
    int mn  = IS_NUMBER(args[1]) ? (int)AS_NUMBER(args[1]) : SAGE_FILTER_LINEAR;
    int addr = IS_NUMBER(args[2]) ? (int)AS_NUMBER(args[2]) : SAGE_ADDRESS_REPEAT;

    int idx = alloc_samplers();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkSamplerCreateInfo info = {0};
    info.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    info.magFilter = translate_filter(mag);
    info.minFilter = translate_filter(mn);
    info.addressModeU = translate_address_mode(addr);
    info.addressModeV = translate_address_mode(addr);
    info.addressModeW = translate_address_mode(addr);
    info.maxLod = 1.0f;

    if (vkCreateSampler(g_gpu_ctx.device, &info, NULL, &g_gpu_ctx.samplers[idx].sampler) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.samplers[idx].alive = 1;
    return val_number(idx);
}

static Value gpu_destroy_sampler(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.sampler_count || !g_gpu_ctx.samplers[idx].alive) return val_nil();
    vkDestroySampler(g_gpu_ctx.device, g_gpu_ctx.samplers[idx].sampler, NULL);
    g_gpu_ctx.samplers[idx].alive = 0;
    return val_nil();
}

// ============================================================================
// Shaders
// ============================================================================

// gpu.load_shader(path, stage) -> handle
static Value gpu_load_shader(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_number(SAGE_GPU_INVALID_HANDLE);
    if (!IS_STRING(args[0]) || !IS_NUMBER(args[1])) return val_number(SAGE_GPU_INVALID_HANDLE);

    const char* path = AS_STRING(args[0]);
    int stage = (int)AS_NUMBER(args[1]);

    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "gpu: cannot open shader '%s'\n", path);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint32_t* code = malloc((size_t)file_size);
    if (!code) { fclose(f); return val_number(SAGE_GPU_INVALID_HANDLE); }
    fread(code, 1, (size_t)file_size, f);
    fclose(f);

    int idx = alloc_shaders();
    if (idx < 0) { free(code); return val_number(SAGE_GPU_INVALID_HANDLE); }

    VkShaderModuleCreateInfo mod_info = {0};
    mod_info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    mod_info.codeSize = (size_t)file_size;
    mod_info.pCode = code;

    VkResult res = vkCreateShaderModule(g_gpu_ctx.device, &mod_info, NULL, &g_gpu_ctx.shaders[idx].module);
    free(code);

    if (res != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    g_gpu_ctx.shaders[idx].stage = stage;
    g_gpu_ctx.shaders[idx].alive = 1;
    return val_number(idx);
}

static Value gpu_destroy_shader(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.shader_count || !g_gpu_ctx.shaders[idx].alive) return val_nil();
    vkDestroyShaderModule(g_gpu_ctx.device, g_gpu_ctx.shaders[idx].module, NULL);
    g_gpu_ctx.shaders[idx].alive = 0;
    return val_nil();
}

// ============================================================================
// Descriptor Set Layouts
// ============================================================================

// gpu.create_descriptor_layout(bindings_array) -> handle
// Each binding: {binding: N, type: DESC_*, stage: STAGE_*, count?: N}
static Value gpu_create_descriptor_layout(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_ARRAY(args[0]))
        return val_number(SAGE_GPU_INVALID_HANDLE);

    ArrayValue* arr = args[0].as.array;
    int count = arr->count;
    if (count > SAGE_GPU_MAX_BINDINGS) count = SAGE_GPU_MAX_BINDINGS;

    VkDescriptorSetLayoutBinding bindings[SAGE_GPU_MAX_BINDINGS] = {0};
    for (int i = 0; i < count; i++) {
        if (!IS_DICT(arr->elements[i])) continue;
        Value* d = &arr->elements[i];
        bindings[i].binding = (uint32_t)AS_NUMBER(dict_get(d, "binding"));
        bindings[i].descriptorType = sage_gpu_translate_desc_type((int)AS_NUMBER(dict_get(d, "type")));
        bindings[i].stageFlags = sage_gpu_translate_stage((int)AS_NUMBER(dict_get(d, "stage")));
        Value cnt = dict_get(d, "count");
        bindings[i].descriptorCount = IS_NUMBER(cnt) ? (uint32_t)AS_NUMBER(cnt) : 1;
    }

    int idx = alloc_desc_layouts();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkDescriptorSetLayoutCreateInfo layout_info = {0};
    layout_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layout_info.bindingCount = (uint32_t)count;
    layout_info.pBindings = bindings;

    if (vkCreateDescriptorSetLayout(g_gpu_ctx.device, &layout_info, NULL,
                                     &g_gpu_ctx.desc_layouts[idx].layout) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    g_gpu_ctx.desc_layouts[idx].binding_count = count;
    g_gpu_ctx.desc_layouts[idx].alive = 1;
    return val_number(idx);
}

// gpu.create_descriptor_pool(max_sets, pool_sizes_array) -> handle
// Each pool_size: {type: DESC_*, count: N}
static Value gpu_create_descriptor_pool(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_number(SAGE_GPU_INVALID_HANDLE);
    if (!IS_NUMBER(args[0]) || !IS_ARRAY(args[1])) return val_number(SAGE_GPU_INVALID_HANDLE);

    int max_sets = (int)AS_NUMBER(args[0]);
    ArrayValue* arr = args[1].as.array;
    int count = arr->count;
    if (count > 16) count = 16;

    VkDescriptorPoolSize sizes[16] = {0};
    for (int i = 0; i < count; i++) {
        if (!IS_DICT(arr->elements[i])) continue;
        Value* d = &arr->elements[i];
        sizes[i].type = sage_gpu_translate_desc_type((int)AS_NUMBER(dict_get(d, "type")));
        sizes[i].descriptorCount = (uint32_t)AS_NUMBER(dict_get(d, "count"));
    }

    int idx = alloc_desc_pools();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkDescriptorPoolCreateInfo pool_info = {0};
    pool_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pool_info.maxSets = (uint32_t)max_sets;
    pool_info.poolSizeCount = (uint32_t)count;
    pool_info.pPoolSizes = sizes;

    if (vkCreateDescriptorPool(g_gpu_ctx.device, &pool_info, NULL,
                                &g_gpu_ctx.desc_pools[idx].pool) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.desc_pools[idx].alive = 1;
    return val_number(idx);
}

// gpu.allocate_descriptor_set(pool, layout) -> handle
static Value gpu_allocate_descriptor_set(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_number(SAGE_GPU_INVALID_HANDLE);
    int pool_idx = (int)AS_NUMBER(args[0]);
    int layout_idx = (int)AS_NUMBER(args[1]);

    if (pool_idx < 0 || pool_idx >= g_gpu_ctx.desc_pool_count || !g_gpu_ctx.desc_pools[pool_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);
    if (layout_idx < 0 || layout_idx >= g_gpu_ctx.desc_layout_count || !g_gpu_ctx.desc_layouts[layout_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    int idx = alloc_desc_sets();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkDescriptorSetAllocateInfo alloc_info = {0};
    alloc_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    alloc_info.descriptorPool = g_gpu_ctx.desc_pools[pool_idx].pool;
    alloc_info.descriptorSetCount = 1;
    alloc_info.pSetLayouts = &g_gpu_ctx.desc_layouts[layout_idx].layout;

    if (vkAllocateDescriptorSets(g_gpu_ctx.device, &alloc_info, &g_gpu_ctx.desc_sets[idx].set) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.desc_sets[idx].alive = 1;
    return val_number(idx);
}

// gpu.update_descriptor(set, binding, type, buffer_handle) -> nil
static Value gpu_update_descriptor(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 4) return val_nil();
    int set_idx = (int)AS_NUMBER(args[0]);
    int binding = (int)AS_NUMBER(args[1]);
    int desc_type = (int)AS_NUMBER(args[2]);
    int res_idx = (int)AS_NUMBER(args[3]);

    if (set_idx < 0 || set_idx >= g_gpu_ctx.desc_set_count || !g_gpu_ctx.desc_sets[set_idx].alive)
        return val_nil();

    VkWriteDescriptorSet write = {0};
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = g_gpu_ctx.desc_sets[set_idx].set;
    write.dstBinding = (uint32_t)binding;
    write.descriptorCount = 1;
    write.descriptorType = sage_gpu_translate_desc_type(desc_type);

    VkDescriptorBufferInfo buf_info = {0};
    VkDescriptorImageInfo img_info = {0};

    if (desc_type == SAGE_DESC_STORAGE_BUFFER || desc_type == SAGE_DESC_UNIFORM_BUFFER) {
        if (res_idx < 0 || res_idx >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[res_idx].alive)
            return val_nil();
        buf_info.buffer = g_gpu_ctx.buffers[res_idx].buffer;
        buf_info.offset = 0;
        buf_info.range = VK_WHOLE_SIZE;
        write.pBufferInfo = &buf_info;
    } else if (desc_type == SAGE_DESC_STORAGE_IMAGE) {
        if (res_idx < 0 || res_idx >= g_gpu_ctx.image_count || !g_gpu_ctx.images[res_idx].alive)
            return val_nil();
        img_info.imageView = g_gpu_ctx.images[res_idx].view;
        img_info.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
        write.pImageInfo = &img_info;
    } else if (desc_type == SAGE_DESC_SAMPLED_IMAGE) {
        if (res_idx < 0 || res_idx >= g_gpu_ctx.image_count || !g_gpu_ctx.images[res_idx].alive)
            return val_nil();
        img_info.imageView = g_gpu_ctx.images[res_idx].view;
        img_info.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        write.pImageInfo = &img_info;
    }

    vkUpdateDescriptorSets(g_gpu_ctx.device, 1, &write, 0, NULL);
    return val_nil();
}

// gpu.update_descriptor_image(set, binding, image, sampler) -> nil
static Value gpu_update_descriptor_image(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 4) return val_nil();
    int set_idx = (int)AS_NUMBER(args[0]);
    int binding = (int)AS_NUMBER(args[1]);
    int img_idx = (int)AS_NUMBER(args[2]);
    int smp_idx = (int)AS_NUMBER(args[3]);

    if (set_idx < 0 || set_idx >= g_gpu_ctx.desc_set_count || !g_gpu_ctx.desc_sets[set_idx].alive)
        return val_nil();
    if (img_idx < 0 || img_idx >= g_gpu_ctx.image_count || !g_gpu_ctx.images[img_idx].alive)
        return val_nil();
    if (smp_idx < 0 || smp_idx >= g_gpu_ctx.sampler_count || !g_gpu_ctx.samplers[smp_idx].alive)
        return val_nil();

    VkDescriptorImageInfo img_info = {0};
    img_info.sampler = g_gpu_ctx.samplers[smp_idx].sampler;
    img_info.imageView = g_gpu_ctx.images[img_idx].view;
    img_info.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkWriteDescriptorSet write = {0};
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = g_gpu_ctx.desc_sets[set_idx].set;
    write.dstBinding = (uint32_t)binding;
    write.descriptorCount = 1;
    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = &img_info;

    vkUpdateDescriptorSets(g_gpu_ctx.device, 1, &write, 0, NULL);
    return val_nil();
}

// ============================================================================
// Pipeline Layouts
// ============================================================================

// gpu.create_pipeline_layout(desc_layouts_array, push_size?, push_stages?) -> handle
static Value gpu_create_pipeline_layout(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkDescriptorSetLayout layouts[8] = {0};
    int layout_count = 0;

    if (IS_ARRAY(args[0])) {
        ArrayValue* arr = args[0].as.array;
        layout_count = arr->count;
        if (layout_count > 8) layout_count = 8;
        for (int i = 0; i < layout_count; i++) {
            int li = (int)AS_NUMBER(arr->elements[i]);
            if (li >= 0 && li < g_gpu_ctx.desc_layout_count && g_gpu_ctx.desc_layouts[li].alive) {
                layouts[i] = g_gpu_ctx.desc_layouts[li].layout;
            }
        }
    }

    VkPushConstantRange push_range = {0};
    int has_push = 0;
    if (argCount >= 2 && IS_NUMBER(args[1])) {
        int push_size = (int)AS_NUMBER(args[1]);
        if (push_size > 0) {
            push_range.size = (uint32_t)push_size;
            push_range.stageFlags = VK_SHADER_STAGE_ALL;
            if (argCount >= 3 && IS_NUMBER(args[2])) {
                push_range.stageFlags = sage_gpu_translate_stage((int)AS_NUMBER(args[2]));
            }
            has_push = 1;
        }
    }

    int idx = alloc_pipe_layouts();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkPipelineLayoutCreateInfo layout_info = {0};
    layout_info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    layout_info.setLayoutCount = (uint32_t)layout_count;
    layout_info.pSetLayouts = layouts;
    if (has_push) {
        layout_info.pushConstantRangeCount = 1;
        layout_info.pPushConstantRanges = &push_range;
    }

    if (vkCreatePipelineLayout(g_gpu_ctx.device, &layout_info, NULL,
                                &g_gpu_ctx.pipe_layouts[idx].layout) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.pipe_layouts[idx].alive = 1;
    return val_number(idx);
}

// ============================================================================
// Compute Pipelines
// ============================================================================

// gpu.create_compute_pipeline(layout_handle, shader_handle) -> handle
static Value gpu_create_compute_pipeline(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_number(SAGE_GPU_INVALID_HANDLE);
    int layout_idx = (int)AS_NUMBER(args[0]);
    int shader_idx = (int)AS_NUMBER(args[1]);

    if (layout_idx < 0 || layout_idx >= g_gpu_ctx.pipe_layout_count || !g_gpu_ctx.pipe_layouts[layout_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);
    if (shader_idx < 0 || shader_idx >= g_gpu_ctx.shader_count || !g_gpu_ctx.shaders[shader_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    int idx = alloc_pipelines();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkComputePipelineCreateInfo pipe_info = {0};
    pipe_info.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipe_info.layout = g_gpu_ctx.pipe_layouts[layout_idx].layout;
    pipe_info.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipe_info.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipe_info.stage.module = g_gpu_ctx.shaders[shader_idx].module;
    pipe_info.stage.pName = "main";

    if (vkCreateComputePipelines(g_gpu_ctx.device, VK_NULL_HANDLE, 1, &pipe_info, NULL,
                                  &g_gpu_ctx.pipelines[idx].pipeline) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.pipelines[idx].is_compute = 1;
    g_gpu_ctx.pipelines[idx].alive = 1;
    return val_number(idx);
}

// gpu.destroy_pipeline(handle)
static Value gpu_destroy_pipeline(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.pipeline_count || !g_gpu_ctx.pipelines[idx].alive) return val_nil();
    vkDestroyPipeline(g_gpu_ctx.device, g_gpu_ctx.pipelines[idx].pipeline, NULL);
    g_gpu_ctx.pipelines[idx].alive = 0;
    return val_nil();
}

// ============================================================================
// Render Passes
// ============================================================================

// gpu.create_render_pass(attachments_array) -> handle
static Value gpu_create_render_pass(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_ARRAY(args[0]))
        return val_number(SAGE_GPU_INVALID_HANDLE);

    ArrayValue* arr = args[0].as.array;
    int attach_count = arr->count;
    if (attach_count > SAGE_GPU_MAX_COLOR_ATTACHMENTS) attach_count = SAGE_GPU_MAX_COLOR_ATTACHMENTS;

    VkAttachmentDescription attachments[SAGE_GPU_MAX_COLOR_ATTACHMENTS] = {0};
    VkAttachmentReference color_refs[SAGE_GPU_MAX_COLOR_ATTACHMENTS] = {0};
    VkAttachmentReference depth_ref = {0};
    int has_depth = 0;
    int color_count = 0;

    for (int i = 0; i < attach_count; i++) {
        if (!IS_DICT(arr->elements[i])) continue;
        Value* d = &arr->elements[i];

        int fmt = (int)AS_NUMBER(dict_get(d, "format"));
        attachments[i].format = sage_gpu_translate_format(fmt);
        attachments[i].samples = VK_SAMPLE_COUNT_1_BIT;
        attachments[i].loadOp = translate_load_op((int)AS_NUMBER(dict_get(d, "load_op")));
        attachments[i].storeOp = translate_store_op((int)AS_NUMBER(dict_get(d, "store_op")));
        attachments[i].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachments[i].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[i].initialLayout = translate_layout((int)AS_NUMBER(dict_get(d, "initial_layout")));
        attachments[i].finalLayout = translate_layout((int)AS_NUMBER(dict_get(d, "final_layout")));

        if (fmt == SAGE_FORMAT_DEPTH32F || fmt == SAGE_FORMAT_DEPTH24_S8) {
            depth_ref.attachment = (uint32_t)i;
            depth_ref.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
            has_depth = 1;
        } else {
            color_refs[color_count].attachment = (uint32_t)i;
            color_refs[color_count].layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
            color_count++;
        }
    }

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = (uint32_t)color_count;
    subpass.pColorAttachments = color_refs;
    if (has_depth) subpass.pDepthStencilAttachment = &depth_ref;

    int idx = alloc_render_passes();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkRenderPassCreateInfo rp_info = {0};
    rp_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rp_info.attachmentCount = (uint32_t)attach_count;
    rp_info.pAttachments = attachments;
    rp_info.subpassCount = 1;
    rp_info.pSubpasses = &subpass;

    if (vkCreateRenderPass(g_gpu_ctx.device, &rp_info, NULL,
                            &g_gpu_ctx.render_passes[idx].render_pass) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.render_passes[idx].alive = 1;
    return val_number(idx);
}

static Value gpu_destroy_render_pass(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.render_pass_count || !g_gpu_ctx.render_passes[idx].alive) return val_nil();
    vkDestroyRenderPass(g_gpu_ctx.device, g_gpu_ctx.render_passes[idx].render_pass, NULL);
    g_gpu_ctx.render_passes[idx].alive = 0;
    return val_nil();
}

// ============================================================================
// Framebuffers
// ============================================================================

// gpu.create_framebuffer(render_pass, image_handles_array, width, height) -> handle
static Value gpu_create_framebuffer(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 4) return val_number(SAGE_GPU_INVALID_HANDLE);
    int rp_idx = (int)AS_NUMBER(args[0]);
    if (rp_idx < 0 || rp_idx >= g_gpu_ctx.render_pass_count || !g_gpu_ctx.render_passes[rp_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    if (!IS_ARRAY(args[1])) return val_number(SAGE_GPU_INVALID_HANDLE);
    ArrayValue* arr = args[1].as.array;
    int attach_count = arr->count;
    if (attach_count > SAGE_GPU_MAX_COLOR_ATTACHMENTS) attach_count = SAGE_GPU_MAX_COLOR_ATTACHMENTS;

    VkImageView views[SAGE_GPU_MAX_COLOR_ATTACHMENTS] = {0};
    for (int i = 0; i < attach_count; i++) {
        int img_idx = (int)AS_NUMBER(arr->elements[i]);
        if (img_idx >= 0 && img_idx < g_gpu_ctx.image_count && g_gpu_ctx.images[img_idx].alive) {
            views[i] = g_gpu_ctx.images[img_idx].view;
        }
    }

    int w = (int)AS_NUMBER(args[2]);
    int h = (int)AS_NUMBER(args[3]);

    int idx = alloc_framebuffers();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkFramebufferCreateInfo fb_info = {0};
    fb_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    fb_info.renderPass = g_gpu_ctx.render_passes[rp_idx].render_pass;
    fb_info.attachmentCount = (uint32_t)attach_count;
    fb_info.pAttachments = views;
    fb_info.width = (uint32_t)w;
    fb_info.height = (uint32_t)h;
    fb_info.layers = 1;

    if (vkCreateFramebuffer(g_gpu_ctx.device, &fb_info, NULL,
                             &g_gpu_ctx.framebuffers[idx].framebuffer) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.framebuffers[idx].width = w;
    g_gpu_ctx.framebuffers[idx].height = h;
    g_gpu_ctx.framebuffers[idx].alive = 1;
    return val_number(idx);
}

static Value gpu_destroy_framebuffer(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.framebuffer_count || !g_gpu_ctx.framebuffers[idx].alive) return val_nil();
    vkDestroyFramebuffer(g_gpu_ctx.device, g_gpu_ctx.framebuffers[idx].framebuffer, NULL);
    g_gpu_ctx.framebuffers[idx].alive = 0;
    return val_nil();
}

// ============================================================================
// Graphics Pipelines
// ============================================================================

// gpu.create_graphics_pipeline(config_dict) -> handle
static Value gpu_create_graphics_pipeline(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_DICT(args[0]))
        return val_number(SAGE_GPU_INVALID_HANDLE);

    Value* cfg = &args[0];
    int layout_idx = (int)AS_NUMBER(dict_get(cfg, "layout"));
    int rp_idx = (int)AS_NUMBER(dict_get(cfg, "render_pass"));
    int vert_idx = (int)AS_NUMBER(dict_get(cfg, "vertex_shader"));
    int frag_idx = (int)AS_NUMBER(dict_get(cfg, "fragment_shader"));

    if (layout_idx < 0 || layout_idx >= g_gpu_ctx.pipe_layout_count || !g_gpu_ctx.pipe_layouts[layout_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);
    if (rp_idx < 0 || rp_idx >= g_gpu_ctx.render_pass_count || !g_gpu_ctx.render_passes[rp_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);
    if (vert_idx < 0 || vert_idx >= g_gpu_ctx.shader_count || !g_gpu_ctx.shaders[vert_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);
    if (frag_idx < 0 || frag_idx >= g_gpu_ctx.shader_count || !g_gpu_ctx.shaders[frag_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    // Shader stages
    VkPipelineShaderStageCreateInfo stages[2] = {0};
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = g_gpu_ctx.shaders[vert_idx].module;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = g_gpu_ctx.shaders[frag_idx].module;
    stages[1].pName = "main";

    // Vertex input (optional)
    VkVertexInputBindingDescription bind_descs[4] = {0};
    VkVertexInputAttributeDescription attr_descs[SAGE_GPU_MAX_VERTEX_ATTRIBS] = {0};
    int bind_count = 0, attr_count = 0;

    Value vb = dict_get(cfg, "vertex_bindings");
    if (IS_ARRAY(vb)) {
        ArrayValue* vb_arr = vb.as.array;
        bind_count = vb_arr->count > 4 ? 4 : vb_arr->count;
        for (int i = 0; i < bind_count; i++) {
            if (!IS_DICT(vb_arr->elements[i])) continue;
            Value* bd = &vb_arr->elements[i];
            bind_descs[i].binding = (uint32_t)AS_NUMBER(dict_get(bd, "binding"));
            bind_descs[i].stride = (uint32_t)AS_NUMBER(dict_get(bd, "stride"));
            Value rate_v = dict_get(bd, "rate");
            bind_descs[i].inputRate = IS_NUMBER(rate_v) && (int)AS_NUMBER(rate_v) == SAGE_INPUT_RATE_INSTANCE
                ? VK_VERTEX_INPUT_RATE_INSTANCE : VK_VERTEX_INPUT_RATE_VERTEX;
        }
    }

    Value va = dict_get(cfg, "vertex_attribs");
    if (IS_ARRAY(va)) {
        ArrayValue* va_arr = va.as.array;
        attr_count = va_arr->count > SAGE_GPU_MAX_VERTEX_ATTRIBS ? SAGE_GPU_MAX_VERTEX_ATTRIBS : va_arr->count;
        for (int i = 0; i < attr_count; i++) {
            if (!IS_DICT(va_arr->elements[i])) continue;
            Value* ad = &va_arr->elements[i];
            attr_descs[i].location = (uint32_t)AS_NUMBER(dict_get(ad, "location"));
            attr_descs[i].binding = (uint32_t)AS_NUMBER(dict_get(ad, "binding"));
            attr_descs[i].format = translate_attr_format((int)AS_NUMBER(dict_get(ad, "format")));
            attr_descs[i].offset = (uint32_t)AS_NUMBER(dict_get(ad, "offset"));
        }
    }

    VkPipelineVertexInputStateCreateInfo vertex_input = {0};
    vertex_input.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertex_input.vertexBindingDescriptionCount = (uint32_t)bind_count;
    vertex_input.pVertexBindingDescriptions = bind_descs;
    vertex_input.vertexAttributeDescriptionCount = (uint32_t)attr_count;
    vertex_input.pVertexAttributeDescriptions = attr_descs;

    // Input assembly
    Value topo_v = dict_get(cfg, "topology");
    VkPrimitiveTopology topo = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    if (IS_NUMBER(topo_v)) {
        int t = (int)AS_NUMBER(topo_v);
        switch (t) {
            case SAGE_TOPO_POINT_LIST:     topo = VK_PRIMITIVE_TOPOLOGY_POINT_LIST; break;
            case SAGE_TOPO_LINE_LIST:      topo = VK_PRIMITIVE_TOPOLOGY_LINE_LIST; break;
            case SAGE_TOPO_LINE_STRIP:     topo = VK_PRIMITIVE_TOPOLOGY_LINE_STRIP; break;
            case SAGE_TOPO_TRIANGLE_STRIP: topo = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP; break;
            case SAGE_TOPO_TRIANGLE_FAN:   topo = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN; break;
            default: break;
        }
    }

    VkPipelineInputAssemblyStateCreateInfo input_assembly = {0};
    input_assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    input_assembly.topology = topo;

    // Dynamic viewport/scissor
    VkDynamicState dynamic_states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic_state = {0};
    dynamic_state.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamic_state.dynamicStateCount = 2;
    dynamic_state.pDynamicStates = dynamic_states;

    VkPipelineViewportStateCreateInfo viewport_state = {0};
    viewport_state.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport_state.viewportCount = 1;
    viewport_state.scissorCount = 1;

    // Rasterization
    VkPipelineRasterizationStateCreateInfo rasterizer = {0};
    rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.lineWidth = 1.0f;

    Value poly_v = dict_get(cfg, "polygon_mode");
    if (IS_NUMBER(poly_v)) {
        int pm = (int)AS_NUMBER(poly_v);
        if (pm == SAGE_POLY_LINE) rasterizer.polygonMode = VK_POLYGON_MODE_LINE;
        else if (pm == SAGE_POLY_POINT) rasterizer.polygonMode = VK_POLYGON_MODE_POINT;
    }

    Value cull_v = dict_get(cfg, "cull_mode");
    if (IS_NUMBER(cull_v)) {
        int cm = (int)AS_NUMBER(cull_v);
        if (cm == SAGE_CULL_FRONT) rasterizer.cullMode = VK_CULL_MODE_FRONT_BIT;
        else if (cm == SAGE_CULL_BACK) rasterizer.cullMode = VK_CULL_MODE_BACK_BIT;
        else if (cm == SAGE_CULL_BOTH) rasterizer.cullMode = VK_CULL_MODE_FRONT_AND_BACK;
    }

    Value face_v = dict_get(cfg, "front_face");
    if (IS_NUMBER(face_v) && (int)AS_NUMBER(face_v) == SAGE_FRONT_CW) {
        rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;
    }

    // Multisampling (off)
    VkPipelineMultisampleStateCreateInfo multisampling = {0};
    multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    // Depth stencil
    VkPipelineDepthStencilStateCreateInfo depth_stencil = {0};
    depth_stencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    Value dt = dict_get(cfg, "depth_test");
    if (IS_BOOL(dt) && AS_BOOL(dt)) {
        depth_stencil.depthTestEnable = VK_TRUE;
        depth_stencil.depthCompareOp = VK_COMPARE_OP_LESS;
    }
    Value dw = dict_get(cfg, "depth_write");
    if (IS_BOOL(dw) && AS_BOOL(dw)) {
        depth_stencil.depthWriteEnable = VK_TRUE;
    }

    // Color blending
    VkPipelineColorBlendAttachmentState blend_attach = {0};
    blend_attach.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                                   VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

    Value blend_v = dict_get(cfg, "blend");
    if (IS_BOOL(blend_v) && AS_BOOL(blend_v)) {
        blend_attach.blendEnable = VK_TRUE;
        blend_attach.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        blend_attach.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        blend_attach.colorBlendOp = VK_BLEND_OP_ADD;
        blend_attach.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        blend_attach.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
        blend_attach.alphaBlendOp = VK_BLEND_OP_ADD;
    }

    VkPipelineColorBlendStateCreateInfo color_blend = {0};
    color_blend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    color_blend.attachmentCount = 1;
    color_blend.pAttachments = &blend_attach;

    // Create pipeline
    int idx = alloc_pipelines();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkGraphicsPipelineCreateInfo pipe_info = {0};
    pipe_info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipe_info.stageCount = 2;
    pipe_info.pStages = stages;
    pipe_info.pVertexInputState = &vertex_input;
    pipe_info.pInputAssemblyState = &input_assembly;
    pipe_info.pViewportState = &viewport_state;
    pipe_info.pRasterizationState = &rasterizer;
    pipe_info.pMultisampleState = &multisampling;
    pipe_info.pDepthStencilState = &depth_stencil;
    pipe_info.pColorBlendState = &color_blend;
    pipe_info.pDynamicState = &dynamic_state;
    pipe_info.layout = g_gpu_ctx.pipe_layouts[layout_idx].layout;
    pipe_info.renderPass = g_gpu_ctx.render_passes[rp_idx].render_pass;

    Value subpass_v = dict_get(cfg, "subpass");
    if (IS_NUMBER(subpass_v)) pipe_info.subpass = (uint32_t)AS_NUMBER(subpass_v);

    if (vkCreateGraphicsPipelines(g_gpu_ctx.device, VK_NULL_HANDLE, 1, &pipe_info, NULL,
                                   &g_gpu_ctx.pipelines[idx].pipeline) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.pipelines[idx].is_compute = 0;
    g_gpu_ctx.pipelines[idx].alive = 1;
    return val_number(idx);
}

// ============================================================================
// Command Buffers
// ============================================================================

// gpu.create_command_pool() -> handle
static Value gpu_create_command_pool(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized) return val_number(SAGE_GPU_INVALID_HANDLE);

    int idx = alloc_cmd_pools();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkCommandPoolCreateInfo pool_info = {0};
    pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = g_gpu_ctx.graphics_family;

    if (vkCreateCommandPool(g_gpu_ctx.device, &pool_info, NULL, &g_gpu_ctx.cmd_pools[idx].pool) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.cmd_pools[idx].alive = 1;
    return val_number(idx);
}

// gpu.create_command_buffer(pool) -> handle
static Value gpu_create_command_buffer(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0]))
        return val_number(SAGE_GPU_INVALID_HANDLE);
    int pool_idx = (int)AS_NUMBER(args[0]);
    if (pool_idx < 0 || pool_idx >= g_gpu_ctx.cmd_pool_count || !g_gpu_ctx.cmd_pools[pool_idx].alive)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    int idx = alloc_cmd_buffers();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkCommandBufferAllocateInfo alloc_info = {0};
    alloc_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    alloc_info.commandPool = g_gpu_ctx.cmd_pools[pool_idx].pool;
    alloc_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc_info.commandBufferCount = 1;

    if (vkAllocateCommandBuffers(g_gpu_ctx.device, &alloc_info, &g_gpu_ctx.cmd_buffers[idx].cmd) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.cmd_buffers[idx].alive = 1;
    return val_number(idx);
}

// Command buffer recording
static Value gpu_begin_commands(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[idx].alive) return val_nil();

    VkCommandBufferBeginInfo begin_info = {0};
    begin_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin_info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(g_gpu_ctx.cmd_buffers[idx].cmd, &begin_info);
    g_gpu_ctx.cmd_buffers[idx].recording = 1;
    return val_nil();
}

static Value gpu_end_commands(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[idx].alive) return val_nil();
    vkEndCommandBuffer(g_gpu_ctx.cmd_buffers[idx].cmd);
    g_gpu_ctx.cmd_buffers[idx].recording = 0;
    return val_nil();
}

// --- Command recording functions ---

#define GET_CMD(idx) \
    if (!g_gpu_ctx.initialized || idx < 0 || idx >= g_gpu_ctx.cmd_buffer_count || \
        !g_gpu_ctx.cmd_buffers[idx].alive) return val_nil(); \
    VkCommandBuffer cmd = g_gpu_ctx.cmd_buffers[idx].cmd;

static Value gpu_cmd_bind_compute_pipeline(int argCount, Value* args) {
    if (argCount < 2) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int pi = (int)AS_NUMBER(args[1]);
    GET_CMD(ci);
    if (pi < 0 || pi >= g_gpu_ctx.pipeline_count || !g_gpu_ctx.pipelines[pi].alive) return val_nil();
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, g_gpu_ctx.pipelines[pi].pipeline);
    return val_nil();
}

static Value gpu_cmd_bind_graphics_pipeline(int argCount, Value* args) {
    if (argCount < 2) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int pi = (int)AS_NUMBER(args[1]);
    GET_CMD(ci);
    if (pi < 0 || pi >= g_gpu_ctx.pipeline_count || !g_gpu_ctx.pipelines[pi].alive) return val_nil();
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, g_gpu_ctx.pipelines[pi].pipeline);
    return val_nil();
}

static Value gpu_cmd_bind_descriptor_set(int argCount, Value* args) {
    if (argCount < 4) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int li = (int)AS_NUMBER(args[1]);
    int set_index = (int)AS_NUMBER(args[2]);
    int si = (int)AS_NUMBER(args[3]);
    GET_CMD(ci);
    if (li < 0 || li >= g_gpu_ctx.pipe_layout_count || !g_gpu_ctx.pipe_layouts[li].alive) return val_nil();
    if (si < 0 || si >= g_gpu_ctx.desc_set_count || !g_gpu_ctx.desc_sets[si].alive) return val_nil();

    // Determine bind point from optional 5th arg or default to compute
    VkPipelineBindPoint bind_point = VK_PIPELINE_BIND_POINT_COMPUTE;
    if (argCount >= 5 && IS_NUMBER(args[4]) && (int)AS_NUMBER(args[4]) == 0) {
        bind_point = VK_PIPELINE_BIND_POINT_GRAPHICS;
    }

    vkCmdBindDescriptorSets(cmd, bind_point,
        g_gpu_ctx.pipe_layouts[li].layout, (uint32_t)set_index,
        1, &g_gpu_ctx.desc_sets[si].set, 0, NULL);
    return val_nil();
}

static Value gpu_cmd_dispatch(int argCount, Value* args) {
    if (argCount < 4) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    GET_CMD(ci);
    vkCmdDispatch(cmd,
        (uint32_t)AS_NUMBER(args[1]),
        (uint32_t)AS_NUMBER(args[2]),
        (uint32_t)AS_NUMBER(args[3]));
    return val_nil();
}

static Value gpu_cmd_push_constants(int argCount, Value* args) {
    if (argCount < 4) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int li = (int)AS_NUMBER(args[1]);
    int stage = (int)AS_NUMBER(args[2]);
    GET_CMD(ci);
    if (li < 0 || li >= g_gpu_ctx.pipe_layout_count || !g_gpu_ctx.pipe_layouts[li].alive) return val_nil();
    if (!IS_ARRAY(args[3])) return val_nil();

    ArrayValue* arr = args[3].as.array;
    int count = arr->count;
    if (count > SAGE_GPU_MAX_PUSH_CONSTANT_SIZE / 4) count = SAGE_GPU_MAX_PUSH_CONSTANT_SIZE / 4;

    float data[SAGE_GPU_MAX_PUSH_CONSTANT_SIZE / 4];
    for (int i = 0; i < count; i++) {
        data[i] = IS_NUMBER(arr->elements[i]) ? (float)AS_NUMBER(arr->elements[i]) : 0.0f;
    }

    vkCmdPushConstants(cmd, g_gpu_ctx.pipe_layouts[li].layout,
        sage_gpu_translate_stage(stage), 0, (uint32_t)(count * 4), data);
    return val_nil();
}

static Value gpu_cmd_begin_render_pass(int argCount, Value* args) {
    if (argCount < 3) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int rp = (int)AS_NUMBER(args[1]);
    int fb = (int)AS_NUMBER(args[2]);
    GET_CMD(ci);
    if (rp < 0 || rp >= g_gpu_ctx.render_pass_count || !g_gpu_ctx.render_passes[rp].alive) return val_nil();
    if (fb < 0 || fb >= g_gpu_ctx.framebuffer_count || !g_gpu_ctx.framebuffers[fb].alive) return val_nil();

    VkClearValue clear_vals[SAGE_GPU_MAX_COLOR_ATTACHMENTS] = {0};
    int clear_count = 1;
    clear_vals[0].color = (VkClearColorValue){{0.0f, 0.0f, 0.0f, 1.0f}};

    if (argCount >= 4 && IS_ARRAY(args[3])) {
        ArrayValue* arr = args[3].as.array;
        clear_count = arr->count > SAGE_GPU_MAX_COLOR_ATTACHMENTS ? SAGE_GPU_MAX_COLOR_ATTACHMENTS : arr->count;
        for (int i = 0; i < clear_count; i++) {
            if (IS_ARRAY(arr->elements[i])) {
                ArrayValue* cv = arr->elements[i].as.array;
                for (int j = 0; j < 4 && j < cv->count; j++) {
                    if (IS_NUMBER(cv->elements[j]))
                        clear_vals[i].color.float32[j] = (float)AS_NUMBER(cv->elements[j]);
                }
            }
        }
    }

    VkRenderPassBeginInfo rp_info = {0};
    rp_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rp_info.renderPass = g_gpu_ctx.render_passes[rp].render_pass;
    rp_info.framebuffer = g_gpu_ctx.framebuffers[fb].framebuffer;
    rp_info.renderArea.extent.width = (uint32_t)g_gpu_ctx.framebuffers[fb].width;
    rp_info.renderArea.extent.height = (uint32_t)g_gpu_ctx.framebuffers[fb].height;
    rp_info.clearValueCount = (uint32_t)clear_count;
    rp_info.pClearValues = clear_vals;

    vkCmdBeginRenderPass(cmd, &rp_info, VK_SUBPASS_CONTENTS_INLINE);
    return val_nil();
}

static Value gpu_cmd_end_render_pass(int argCount, Value* args) {
    if (argCount < 1) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    GET_CMD(ci);
    vkCmdEndRenderPass(cmd);
    return val_nil();
}

static Value gpu_cmd_draw(int argCount, Value* args) {
    if (argCount < 5) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    GET_CMD(ci);
    vkCmdDraw(cmd,
        (uint32_t)AS_NUMBER(args[1]),
        (uint32_t)AS_NUMBER(args[2]),
        (uint32_t)AS_NUMBER(args[3]),
        (uint32_t)AS_NUMBER(args[4]));
    return val_nil();
}

static Value gpu_cmd_draw_indexed(int argCount, Value* args) {
    if (argCount < 6) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    GET_CMD(ci);
    vkCmdDrawIndexed(cmd,
        (uint32_t)AS_NUMBER(args[1]),
        (uint32_t)AS_NUMBER(args[2]),
        (uint32_t)AS_NUMBER(args[3]),
        (int32_t)AS_NUMBER(args[4]),
        (uint32_t)AS_NUMBER(args[5]));
    return val_nil();
}

static Value gpu_cmd_bind_vertex_buffer(int argCount, Value* args) {
    if (argCount < 2) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int bi = (int)AS_NUMBER(args[1]);
    GET_CMD(ci);
    if (bi < 0 || bi >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[bi].alive) return val_nil();
    VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &g_gpu_ctx.buffers[bi].buffer, &offset);
    return val_nil();
}

static Value gpu_cmd_bind_index_buffer(int argCount, Value* args) {
    if (argCount < 2) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int bi = (int)AS_NUMBER(args[1]);
    GET_CMD(ci);
    if (bi < 0 || bi >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[bi].alive) return val_nil();
    vkCmdBindIndexBuffer(cmd, g_gpu_ctx.buffers[bi].buffer, 0, VK_INDEX_TYPE_UINT32);
    return val_nil();
}

static Value gpu_cmd_set_viewport(int argCount, Value* args) {
    if (argCount < 7) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    GET_CMD(ci);
    VkViewport vp = {0};
    vp.x = (float)AS_NUMBER(args[1]);
    vp.y = (float)AS_NUMBER(args[2]);
    vp.width = (float)AS_NUMBER(args[3]);
    vp.height = (float)AS_NUMBER(args[4]);
    vp.minDepth = (float)AS_NUMBER(args[5]);
    vp.maxDepth = (float)AS_NUMBER(args[6]);
    vkCmdSetViewport(cmd, 0, 1, &vp);
    return val_nil();
}

static Value gpu_cmd_set_scissor(int argCount, Value* args) {
    if (argCount < 5) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    GET_CMD(ci);
    VkRect2D scissor = {0};
    scissor.offset.x = (int32_t)AS_NUMBER(args[1]);
    scissor.offset.y = (int32_t)AS_NUMBER(args[2]);
    scissor.extent.width = (uint32_t)AS_NUMBER(args[3]);
    scissor.extent.height = (uint32_t)AS_NUMBER(args[4]);
    vkCmdSetScissor(cmd, 0, 1, &scissor);
    return val_nil();
}

static Value gpu_cmd_pipeline_barrier(int argCount, Value* args) {
    if (argCount < 5) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    GET_CMD(ci);

    VkMemoryBarrier barrier = {0};
    barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    barrier.srcAccessMask = translate_access((int)AS_NUMBER(args[3]));
    barrier.dstAccessMask = translate_access((int)AS_NUMBER(args[4]));

    vkCmdPipelineBarrier(cmd,
        translate_pipeline_stage((int)AS_NUMBER(args[1])),
        translate_pipeline_stage((int)AS_NUMBER(args[2])),
        0, 1, &barrier, 0, NULL, 0, NULL);
    return val_nil();
}

static Value gpu_cmd_image_barrier(int argCount, Value* args) {
    if (argCount < 8) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int img_i = (int)AS_NUMBER(args[1]);
    GET_CMD(ci);
    if (img_i < 0 || img_i >= g_gpu_ctx.image_count || !g_gpu_ctx.images[img_i].alive) return val_nil();

    int fmt = g_gpu_ctx.images[img_i].format;
    VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT;
    if (fmt == SAGE_FORMAT_DEPTH32F || fmt == SAGE_FORMAT_DEPTH24_S8) {
        aspect = VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    VkImageMemoryBarrier barrier = {0};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = translate_layout((int)AS_NUMBER(args[2]));
    barrier.newLayout = translate_layout((int)AS_NUMBER(args[3]));
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = g_gpu_ctx.images[img_i].image;
    barrier.subresourceRange.aspectMask = aspect;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;
    barrier.srcAccessMask = translate_access((int)AS_NUMBER(args[6]));
    barrier.dstAccessMask = translate_access((int)AS_NUMBER(args[7]));

    vkCmdPipelineBarrier(cmd,
        translate_pipeline_stage((int)AS_NUMBER(args[4])),
        translate_pipeline_stage((int)AS_NUMBER(args[5])),
        0, 0, NULL, 0, NULL, 1, &barrier);
    return val_nil();
}

static Value gpu_cmd_copy_buffer(int argCount, Value* args) {
    if (argCount < 4) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int src_i = (int)AS_NUMBER(args[1]);
    int dst_i = (int)AS_NUMBER(args[2]);
    VkDeviceSize size = (VkDeviceSize)AS_NUMBER(args[3]);
    GET_CMD(ci);
    if (src_i < 0 || src_i >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[src_i].alive) return val_nil();
    if (dst_i < 0 || dst_i >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[dst_i].alive) return val_nil();

    VkBufferCopy region = {0};
    region.size = size;
    vkCmdCopyBuffer(cmd, g_gpu_ctx.buffers[src_i].buffer, g_gpu_ctx.buffers[dst_i].buffer, 1, &region);
    return val_nil();
}

static Value gpu_cmd_copy_buffer_to_image(int argCount, Value* args) {
    if (argCount < 5) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int bi = (int)AS_NUMBER(args[1]);
    int ii = (int)AS_NUMBER(args[2]);
    int w = (int)AS_NUMBER(args[3]);
    int h = (int)AS_NUMBER(args[4]);
    GET_CMD(ci);
    if (bi < 0 || bi >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[bi].alive) return val_nil();
    if (ii < 0 || ii >= g_gpu_ctx.image_count || !g_gpu_ctx.images[ii].alive) return val_nil();

    VkBufferImageCopy region = {0};
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.layerCount = 1;
    region.imageExtent.width = (uint32_t)w;
    region.imageExtent.height = (uint32_t)h;
    region.imageExtent.depth = 1;

    vkCmdCopyBufferToImage(cmd, g_gpu_ctx.buffers[bi].buffer, g_gpu_ctx.images[ii].image,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
    return val_nil();
}

// ============================================================================
// Synchronization
// ============================================================================

static Value gpu_create_fence(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized) return val_number(SAGE_GPU_INVALID_HANDLE);
    int idx = alloc_fences();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkFenceCreateInfo info = {0};
    info.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    if (argCount >= 1 && IS_BOOL(args[0]) && AS_BOOL(args[0])) {
        info.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    }

    if (vkCreateFence(g_gpu_ctx.device, &info, NULL, &g_gpu_ctx.fences[idx].fence) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.fences[idx].alive = 1;
    return val_number(idx);
}

static Value gpu_wait_fence(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.fence_count || !g_gpu_ctx.fences[idx].alive) return val_bool(0);

    uint64_t timeout = UINT64_MAX;
    if (argCount >= 2 && IS_NUMBER(args[1])) timeout = (uint64_t)AS_NUMBER(args[1]);

    VkResult res = vkWaitForFences(g_gpu_ctx.device, 1, &g_gpu_ctx.fences[idx].fence, VK_TRUE, timeout);
    return val_bool(res == VK_SUCCESS);
}

static Value gpu_reset_fence(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.fence_count || !g_gpu_ctx.fences[idx].alive) return val_nil();
    vkResetFences(g_gpu_ctx.device, 1, &g_gpu_ctx.fences[idx].fence);
    return val_nil();
}

static Value gpu_destroy_fence(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.fence_count || !g_gpu_ctx.fences[idx].alive) return val_nil();
    vkDestroyFence(g_gpu_ctx.device, g_gpu_ctx.fences[idx].fence, NULL);
    g_gpu_ctx.fences[idx].alive = 0;
    return val_nil();
}

static Value gpu_create_semaphore(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized) return val_number(SAGE_GPU_INVALID_HANDLE);
    int idx = alloc_semaphores();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkSemaphoreCreateInfo info = {0};
    info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    if (vkCreateSemaphore(g_gpu_ctx.device, &info, NULL, &g_gpu_ctx.semaphores[idx].semaphore) != VK_SUCCESS) {
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    g_gpu_ctx.semaphores[idx].alive = 1;
    return val_number(idx);
}

static Value gpu_destroy_semaphore(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.semaphore_count || !g_gpu_ctx.semaphores[idx].alive) return val_nil();
    vkDestroySemaphore(g_gpu_ctx.device, g_gpu_ctx.semaphores[idx].semaphore, NULL);
    g_gpu_ctx.semaphores[idx].alive = 0;
    return val_nil();
}

// ============================================================================
// Submission
// ============================================================================

// gpu.submit(cmd, wait_sems?, signal_sems?, fence?) -> nil
static Value gpu_submit(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    if (ci < 0 || ci >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[ci].alive) return val_nil();

    VkSubmitInfo submit = {0};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &g_gpu_ctx.cmd_buffers[ci].cmd;

    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    submit.pWaitDstStageMask = &wait_stage;

    VkFence fence = VK_NULL_HANDLE;
    if (argCount >= 4 && IS_NUMBER(args[3])) {
        int fi = (int)AS_NUMBER(args[3]);
        if (fi >= 0 && fi < g_gpu_ctx.fence_count && g_gpu_ctx.fences[fi].alive) {
            fence = g_gpu_ctx.fences[fi].fence;
        }
    }

    vkQueueSubmit(g_gpu_ctx.graphics_queue, 1, &submit, fence);
    return val_nil();
}

// gpu.submit_compute(...) — submits to compute queue
static Value gpu_submit_compute(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    if (ci < 0 || ci >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[ci].alive) return val_nil();

    VkSubmitInfo submit = {0};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &g_gpu_ctx.cmd_buffers[ci].cmd;

    VkFence fence = VK_NULL_HANDLE;
    if (argCount >= 4 && IS_NUMBER(args[3])) {
        int fi = (int)AS_NUMBER(args[3]);
        if (fi >= 0 && fi < g_gpu_ctx.fence_count && g_gpu_ctx.fences[fi].alive) {
            fence = g_gpu_ctx.fences[fi].fence;
        }
    }

    vkQueueSubmit(g_gpu_ctx.compute_queue, 1, &submit, fence);
    return val_nil();
}

static Value gpu_queue_wait_idle(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized) return val_nil();
    vkQueueWaitIdle(g_gpu_ctx.graphics_queue);
    return val_nil();
}

static Value gpu_device_wait_idle(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized) return val_nil();
    vkDeviceWaitIdle(g_gpu_ctx.device);
    return val_nil();
}

// ============================================================================
// Module Registration
// ============================================================================

Module* create_graphics_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "gpu");
    Environment* e = m->env;

    // --- Query ---
    env_define(e, "has_vulkan", 10, val_native(gpu_has_vulkan));

    // --- Context ---
    env_define(e, "initialize", 10, val_native(gpu_init));
    env_define(e, "shutdown", 8, val_native(gpu_shutdown));
    env_define(e, "device_name", 11, val_native(gpu_device_name));
    env_define(e, "device_limits", 13, val_native(gpu_device_limits));

    // --- Buffers ---
    env_define(e, "create_buffer", 13, val_native(gpu_create_buffer));
    env_define(e, "destroy_buffer", 14, val_native(gpu_destroy_buffer));
    env_define(e, "buffer_upload", 13, val_native(gpu_buffer_upload));
    env_define(e, "buffer_download", 15, val_native(gpu_buffer_download));
    env_define(e, "buffer_size", 11, val_native(gpu_buffer_size));

    // --- Images ---
    env_define(e, "create_image", 12, val_native(gpu_create_image));
    env_define(e, "destroy_image", 13, val_native(gpu_destroy_image));
    env_define(e, "image_dims", 10, val_native(gpu_image_dims));

    // --- Samplers ---
    env_define(e, "create_sampler", 14, val_native(gpu_create_sampler));
    env_define(e, "destroy_sampler", 15, val_native(gpu_destroy_sampler));

    // --- Shaders ---
    env_define(e, "load_shader", 11, val_native(gpu_load_shader));
    env_define(e, "destroy_shader", 14, val_native(gpu_destroy_shader));

    // --- Descriptors ---
    env_define(e, "create_descriptor_layout", 24, val_native(gpu_create_descriptor_layout));
    env_define(e, "create_descriptor_pool", 22, val_native(gpu_create_descriptor_pool));
    env_define(e, "allocate_descriptor_set", 23, val_native(gpu_allocate_descriptor_set));
    env_define(e, "update_descriptor", 17, val_native(gpu_update_descriptor));
    env_define(e, "update_descriptor_image", 23, val_native(gpu_update_descriptor_image));

    // --- Pipeline layouts ---
    env_define(e, "create_pipeline_layout", 22, val_native(gpu_create_pipeline_layout));

    // --- Compute pipelines ---
    env_define(e, "create_compute_pipeline", 23, val_native(gpu_create_compute_pipeline));
    env_define(e, "destroy_pipeline", 16, val_native(gpu_destroy_pipeline));

    // --- Graphics pipelines ---
    env_define(e, "create_graphics_pipeline", 24, val_native(gpu_create_graphics_pipeline));

    // --- Render passes ---
    env_define(e, "create_render_pass", 18, val_native(gpu_create_render_pass));
    env_define(e, "destroy_render_pass", 19, val_native(gpu_destroy_render_pass));

    // --- Framebuffers ---
    env_define(e, "create_framebuffer", 18, val_native(gpu_create_framebuffer));
    env_define(e, "destroy_framebuffer", 19, val_native(gpu_destroy_framebuffer));

    // --- Commands ---
    env_define(e, "create_command_pool", 19, val_native(gpu_create_command_pool));
    env_define(e, "create_command_buffer", 21, val_native(gpu_create_command_buffer));
    env_define(e, "begin_commands", 14, val_native(gpu_begin_commands));
    env_define(e, "end_commands", 12, val_native(gpu_end_commands));
    env_define(e, "cmd_bind_compute_pipeline", 25, val_native(gpu_cmd_bind_compute_pipeline));
    env_define(e, "cmd_bind_graphics_pipeline", 26, val_native(gpu_cmd_bind_graphics_pipeline));
    env_define(e, "cmd_bind_descriptor_set", 23, val_native(gpu_cmd_bind_descriptor_set));
    env_define(e, "cmd_dispatch", 12, val_native(gpu_cmd_dispatch));
    env_define(e, "cmd_push_constants", 18, val_native(gpu_cmd_push_constants));
    env_define(e, "cmd_begin_render_pass", 21, val_native(gpu_cmd_begin_render_pass));
    env_define(e, "cmd_end_render_pass", 19, val_native(gpu_cmd_end_render_pass));
    env_define(e, "cmd_draw", 8, val_native(gpu_cmd_draw));
    env_define(e, "cmd_draw_indexed", 16, val_native(gpu_cmd_draw_indexed));
    env_define(e, "cmd_bind_vertex_buffer", 22, val_native(gpu_cmd_bind_vertex_buffer));
    env_define(e, "cmd_bind_index_buffer", 21, val_native(gpu_cmd_bind_index_buffer));
    env_define(e, "cmd_set_viewport", 16, val_native(gpu_cmd_set_viewport));
    env_define(e, "cmd_set_scissor", 15, val_native(gpu_cmd_set_scissor));
    env_define(e, "cmd_copy_buffer", 15, val_native(gpu_cmd_copy_buffer));
    env_define(e, "cmd_copy_buffer_to_image", 24, val_native(gpu_cmd_copy_buffer_to_image));
    env_define(e, "cmd_pipeline_barrier", 20, val_native(gpu_cmd_pipeline_barrier));
    env_define(e, "cmd_image_barrier", 17, val_native(gpu_cmd_image_barrier));

    // --- Synchronization ---
    env_define(e, "create_fence", 12, val_native(gpu_create_fence));
    env_define(e, "wait_fence", 10, val_native(gpu_wait_fence));
    env_define(e, "reset_fence", 11, val_native(gpu_reset_fence));
    env_define(e, "destroy_fence", 13, val_native(gpu_destroy_fence));
    env_define(e, "create_semaphore", 16, val_native(gpu_create_semaphore));
    env_define(e, "destroy_semaphore", 17, val_native(gpu_destroy_semaphore));

    // --- Submission ---
    env_define(e, "submit", 6, val_native(gpu_submit));
    env_define(e, "submit_compute", 14, val_native(gpu_submit_compute));
    env_define(e, "queue_wait_idle", 15, val_native(gpu_queue_wait_idle));
    env_define(e, "device_wait_idle", 16, val_native(gpu_device_wait_idle));

    // --- Constants (same as stub) ---
    env_define(e, "INVALID_HANDLE", 14, val_number(SAGE_GPU_INVALID_HANDLE));

    // Buffer usage
    env_define(e, "BUFFER_STORAGE",      14, val_number(SAGE_BUFFER_STORAGE));
    env_define(e, "BUFFER_UNIFORM",      14, val_number(SAGE_BUFFER_UNIFORM));
    env_define(e, "BUFFER_VERTEX",       13, val_number(SAGE_BUFFER_VERTEX));
    env_define(e, "BUFFER_INDEX",        12, val_number(SAGE_BUFFER_INDEX));
    env_define(e, "BUFFER_STAGING",      14, val_number(SAGE_BUFFER_STAGING));
    env_define(e, "BUFFER_INDIRECT",     15, val_number(SAGE_BUFFER_INDIRECT));
    env_define(e, "BUFFER_TRANSFER_SRC", 19, val_number(SAGE_BUFFER_TRANSFER_SRC));
    env_define(e, "BUFFER_TRANSFER_DST", 19, val_number(SAGE_BUFFER_TRANSFER_DST));
    env_define(e, "MEMORY_DEVICE_LOCAL",  19, val_number(SAGE_MEMORY_DEVICE_LOCAL));
    env_define(e, "MEMORY_HOST_VISIBLE",  19, val_number(SAGE_MEMORY_HOST_VISIBLE));
    env_define(e, "MEMORY_HOST_COHERENT", 20, val_number(SAGE_MEMORY_HOST_COHERENT));
    env_define(e, "FORMAT_RGBA8", 12, val_number(SAGE_FORMAT_RGBA8));
    env_define(e, "FORMAT_RGBA16F", 14, val_number(SAGE_FORMAT_RGBA16F));
    env_define(e, "FORMAT_RGBA32F", 14, val_number(SAGE_FORMAT_RGBA32F));
    env_define(e, "FORMAT_R32F", 11, val_number(SAGE_FORMAT_R32F));
    env_define(e, "FORMAT_RG32F", 12, val_number(SAGE_FORMAT_RG32F));
    env_define(e, "FORMAT_DEPTH32F", 15, val_number(SAGE_FORMAT_DEPTH32F));
    env_define(e, "FORMAT_DEPTH24_S8",17, val_number(SAGE_FORMAT_DEPTH24_S8));
    env_define(e, "FORMAT_R8",        9,  val_number(SAGE_FORMAT_R8));
    env_define(e, "FORMAT_BGRA8",     12, val_number(SAGE_FORMAT_BGRA8));
    env_define(e, "FORMAT_R32U", 11, val_number(SAGE_FORMAT_R32U));
    env_define(e, "IMAGE_SAMPLED",      13, val_number(SAGE_IMAGE_SAMPLED));
    env_define(e, "IMAGE_STORAGE",      13, val_number(SAGE_IMAGE_STORAGE));
    env_define(e, "IMAGE_COLOR_ATTACH", 18, val_number(SAGE_IMAGE_COLOR_ATTACH));
    env_define(e, "IMAGE_DEPTH_ATTACH", 18, val_number(SAGE_IMAGE_DEPTH_ATTACH));
    env_define(e, "IMAGE_TRANSFER_SRC", 18, val_number(SAGE_IMAGE_TRANSFER_SRC));
    env_define(e, "IMAGE_TRANSFER_DST", 18, val_number(SAGE_IMAGE_TRANSFER_DST));
    env_define(e, "IMAGE_2D",  8, val_number(SAGE_IMAGE_2D));
    env_define(e, "IMAGE_3D",  8, val_number(SAGE_IMAGE_3D));
    env_define(e, "FILTER_NEAREST", 14, val_number(SAGE_FILTER_NEAREST));
    env_define(e, "FILTER_LINEAR",  13, val_number(SAGE_FILTER_LINEAR));
    env_define(e, "ADDRESS_REPEAT",          14, val_number(SAGE_ADDRESS_REPEAT));
    env_define(e, "ADDRESS_CLAMP_EDGE",      18, val_number(SAGE_ADDRESS_CLAMP_EDGE));
    env_define(e, "DESC_STORAGE_BUFFER",  19, val_number(SAGE_DESC_STORAGE_BUFFER));
    env_define(e, "DESC_UNIFORM_BUFFER",  19, val_number(SAGE_DESC_UNIFORM_BUFFER));
    env_define(e, "DESC_SAMPLED_IMAGE",   18, val_number(SAGE_DESC_SAMPLED_IMAGE));
    env_define(e, "DESC_STORAGE_IMAGE",   18, val_number(SAGE_DESC_STORAGE_IMAGE));
    env_define(e, "DESC_COMBINED_SAMPLER",21, val_number(SAGE_DESC_COMBINED_SAMPLER));
    env_define(e, "STAGE_VERTEX",   12, val_number(SAGE_STAGE_VERTEX));
    env_define(e, "STAGE_FRAGMENT", 14, val_number(SAGE_STAGE_FRAGMENT));
    env_define(e, "STAGE_COMPUTE",  13, val_number(SAGE_STAGE_COMPUTE));
    env_define(e, "STAGE_GEOMETRY", 14, val_number(SAGE_STAGE_GEOMETRY));
    env_define(e, "STAGE_ALL",      9,  val_number(SAGE_STAGE_ALL));
    env_define(e, "TOPO_TRIANGLE_LIST",  18, val_number(SAGE_TOPO_TRIANGLE_LIST));
    env_define(e, "TOPO_TRIANGLE_STRIP", 19, val_number(SAGE_TOPO_TRIANGLE_STRIP));
    env_define(e, "TOPO_LINE_LIST",      14, val_number(SAGE_TOPO_LINE_LIST));
    env_define(e, "TOPO_POINT_LIST",     15, val_number(SAGE_TOPO_POINT_LIST));
    env_define(e, "POLY_FILL",  9,  val_number(SAGE_POLY_FILL));
    env_define(e, "POLY_LINE",  9,  val_number(SAGE_POLY_LINE));
    env_define(e, "CULL_NONE",  9,  val_number(SAGE_CULL_NONE));
    env_define(e, "CULL_BACK",  9,  val_number(SAGE_CULL_BACK));
    env_define(e, "FRONT_CCW",  9,  val_number(SAGE_FRONT_CCW));
    env_define(e, "FRONT_CW",   8,  val_number(SAGE_FRONT_CW));
    env_define(e, "BLEND_SRC_ALPHA",          15, val_number(SAGE_BLEND_SRC_ALPHA));
    env_define(e, "BLEND_ONE_MINUS_SRC_ALPHA",25, val_number(SAGE_BLEND_ONE_MINUS_SRC_ALPHA));
    env_define(e, "BLEND_ZERO",              10, val_number(SAGE_BLEND_ZERO));
    env_define(e, "BLEND_ONE",               9,  val_number(SAGE_BLEND_ONE));
    env_define(e, "BLEND_OP_ADD",            12, val_number(SAGE_BLEND_OP_ADD));
    env_define(e, "BLEND_OP_SUBTRACT",       17, val_number(SAGE_BLEND_OP_SUBTRACT));
    env_define(e, "BLEND_OP_MIN",            12, val_number(SAGE_BLEND_OP_MIN));
    env_define(e, "BLEND_OP_MAX",            12, val_number(SAGE_BLEND_OP_MAX));
    env_define(e, "COMPARE_LESS",    12, val_number(SAGE_COMPARE_LESS));
    env_define(e, "COMPARE_LEQUAL",  14, val_number(SAGE_COMPARE_LEQUAL));
    env_define(e, "COMPARE_ALWAYS",  14, val_number(SAGE_COMPARE_ALWAYS));
    env_define(e, "LAYOUT_UNDEFINED",    16, val_number(SAGE_LAYOUT_UNDEFINED));
    env_define(e, "LAYOUT_GENERAL",      14, val_number(SAGE_LAYOUT_GENERAL));
    env_define(e, "LAYOUT_COLOR_ATTACH", 19, val_number(SAGE_LAYOUT_COLOR_ATTACH));
    env_define(e, "LAYOUT_DEPTH_ATTACH", 19, val_number(SAGE_LAYOUT_DEPTH_ATTACH));
    env_define(e, "LAYOUT_SHADER_READ",  18, val_number(SAGE_LAYOUT_SHADER_READ));
    env_define(e, "LAYOUT_TRANSFER_SRC", 19, val_number(SAGE_LAYOUT_TRANSFER_SRC));
    env_define(e, "LAYOUT_TRANSFER_DST", 19, val_number(SAGE_LAYOUT_TRANSFER_DST));
    env_define(e, "LAYOUT_PRESENT",      14, val_number(SAGE_LAYOUT_PRESENT));
    env_define(e, "PIPE_TOP",          8,  val_number(SAGE_PIPE_TOP));
    env_define(e, "PIPE_COMPUTE",      12, val_number(SAGE_PIPE_COMPUTE));
    env_define(e, "PIPE_TRANSFER",     13, val_number(SAGE_PIPE_TRANSFER));
    env_define(e, "PIPE_BOTTOM",       11, val_number(SAGE_PIPE_BOTTOM));
    env_define(e, "PIPE_FRAGMENT",     13, val_number(SAGE_PIPE_FRAGMENT));
    env_define(e, "PIPE_COLOR_OUTPUT", 17, val_number(SAGE_PIPE_COLOR_OUTPUT));
    env_define(e, "PIPE_ALL_COMMANDS", 17, val_number(SAGE_PIPE_ALL_COMMANDS));
    env_define(e, "ACCESS_NONE",          11, val_number(SAGE_ACCESS_NONE));
    env_define(e, "ACCESS_SHADER_READ",   18, val_number(SAGE_ACCESS_SHADER_READ));
    env_define(e, "ACCESS_SHADER_WRITE",  19, val_number(SAGE_ACCESS_SHADER_WRITE));
    env_define(e, "ACCESS_TRANSFER_READ", 20, val_number(SAGE_ACCESS_TRANSFER_READ));
    env_define(e, "ACCESS_TRANSFER_WRITE",21, val_number(SAGE_ACCESS_TRANSFER_WRITE));
    env_define(e, "ACCESS_HOST_READ",     16, val_number(SAGE_ACCESS_HOST_READ));
    env_define(e, "ACCESS_HOST_WRITE",    17, val_number(SAGE_ACCESS_HOST_WRITE));
    env_define(e, "LOAD_CLEAR",    10, val_number(SAGE_LOAD_CLEAR));
    env_define(e, "LOAD_LOAD",     9,  val_number(SAGE_LOAD_LOAD));
    env_define(e, "LOAD_DONTCARE", 13, val_number(SAGE_LOAD_DONTCARE));
    env_define(e, "STORE_STORE",   11, val_number(SAGE_STORE_STORE));
    env_define(e, "STORE_DONTCARE",14, val_number(SAGE_STORE_DONTCARE));
    env_define(e, "INPUT_RATE_VERTEX",   17, val_number(SAGE_INPUT_RATE_VERTEX));
    env_define(e, "INPUT_RATE_INSTANCE", 19, val_number(SAGE_INPUT_RATE_INSTANCE));
    env_define(e, "ATTR_FLOAT", 10, val_number(SAGE_ATTR_FLOAT));
    env_define(e, "ATTR_VEC2",  9,  val_number(SAGE_ATTR_VEC2));
    env_define(e, "ATTR_VEC3",  9,  val_number(SAGE_ATTR_VEC3));
    env_define(e, "ATTR_VEC4",  9,  val_number(SAGE_ATTR_VEC4));
    env_define(e, "ATTR_INT",   8,  val_number(SAGE_ATTR_INT));
    env_define(e, "ATTR_UINT",  9,  val_number(SAGE_ATTR_UINT));

    return m;
}

#endif // SAGE_HAS_VULKAN
