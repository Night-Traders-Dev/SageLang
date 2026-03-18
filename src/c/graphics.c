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

#ifdef SAGE_HAS_GLFW
#define GLFW_INCLUDE_VULKAN
#include <GLFW/glfw3.h>
#endif

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

// Swapchain format (set by init_windowed, used by FORMAT_SWAPCHAIN)
static VkFormat g_active_swapchain_format = VK_FORMAT_B8G8R8A8_UNORM;

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
        case SAGE_FORMAT_SWAPCHAIN:  return g_active_swapchain_format;
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
// One-shot command helper (internal)
// ============================================================================

static VkCommandBuffer sage_gpu_begin_one_shot(void) {
    VkCommandPoolCreateInfo pool_info = {0};
    pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
    pool_info.queueFamilyIndex = g_gpu_ctx.graphics_family;

    VkCommandPool tmp_pool;
    if (vkCreateCommandPool(g_gpu_ctx.device, &pool_info, NULL, &tmp_pool) != VK_SUCCESS)
        return VK_NULL_HANDLE;

    VkCommandBufferAllocateInfo alloc_info = {0};
    alloc_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    alloc_info.commandPool = tmp_pool;
    alloc_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc_info.commandBufferCount = 1;

    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(g_gpu_ctx.device, &alloc_info, &cmd);

    VkCommandBufferBeginInfo begin = {0};
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &begin);

    // Store pool handle in a thread-local-ish way (we only support one at a time)
    return cmd;
}

static VkCommandPool g_oneshot_pool = VK_NULL_HANDLE;

static VkCommandBuffer sage_gpu_begin_one_shot_v2(void) {
    VkCommandPoolCreateInfo pool_info = {0};
    pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
    pool_info.queueFamilyIndex = g_gpu_ctx.graphics_family;
    if (vkCreateCommandPool(g_gpu_ctx.device, &pool_info, NULL, &g_oneshot_pool) != VK_SUCCESS)
        return VK_NULL_HANDLE;

    VkCommandBufferAllocateInfo a = {0};
    a.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    a.commandPool = g_oneshot_pool;
    a.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    a.commandBufferCount = 1;

    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(g_gpu_ctx.device, &a, &cmd);

    VkCommandBufferBeginInfo b = {0};
    b.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    b.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &b);
    return cmd;
}

static void sage_gpu_end_one_shot(VkCommandBuffer cmd) {
    vkEndCommandBuffer(cmd);

    VkSubmitInfo submit = {0};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &cmd;

    vkQueueSubmit(g_gpu_ctx.graphics_queue, 1, &submit, VK_NULL_HANDLE);
    vkQueueWaitIdle(g_gpu_ctx.graphics_queue);

    vkDestroyCommandPool(g_gpu_ctx.device, g_oneshot_pool, NULL);
    g_oneshot_pool = VK_NULL_HANDLE;
}

// ============================================================================
// Depth Buffer Helper
// ============================================================================

static VkFormat sage_gpu_find_depth_format(void) {
    VkFormat candidates[] = {VK_FORMAT_D32_SFLOAT, VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_D24_UNORM_S8_UINT};
    for (int i = 0; i < 3; i++) {
        VkFormatProperties props;
        vkGetPhysicalDeviceFormatProperties(g_gpu_ctx.physical_device, candidates[i], &props);
        if (props.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
            return candidates[i];
        }
    }
    return VK_FORMAT_D32_SFLOAT;
}

// gpu.create_depth_buffer(width, height) -> image handle
static Value gpu_create_depth_buffer(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_number(SAGE_GPU_INVALID_HANDLE);
    int w = (int)AS_NUMBER(args[0]);
    int h = (int)AS_NUMBER(args[1]);

    VkFormat depth_fmt = sage_gpu_find_depth_format();

    int idx = alloc_images();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkImageCreateInfo img_info = {0};
    img_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    img_info.imageType = VK_IMAGE_TYPE_2D;
    img_info.format = depth_fmt;
    img_info.extent.width = (uint32_t)w;
    img_info.extent.height = (uint32_t)h;
    img_info.extent.depth = 1;
    img_info.mipLevels = 1;
    img_info.arrayLayers = 1;
    img_info.samples = VK_SAMPLE_COUNT_1_BIT;
    img_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    img_info.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;

    if (vkCreateImage(g_gpu_ctx.device, &img_info, NULL, &g_gpu_ctx.images[idx].image) != VK_SUCCESS)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    VkMemoryRequirements mem_req;
    vkGetImageMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, &mem_req);
    VkMemoryAllocateInfo alloc = {0};
    alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc.allocationSize = mem_req.size;
    alloc.memoryTypeIndex = sage_gpu_find_memory_type(mem_req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(g_gpu_ctx.device, &alloc, NULL, &g_gpu_ctx.images[idx].memory) != VK_SUCCESS) {
        vkDestroyImage(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    vkBindImageMemory(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, g_gpu_ctx.images[idx].memory, 0);

    VkImageViewCreateInfo view_info = {0};
    view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = g_gpu_ctx.images[idx].image;
    view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view_info.format = depth_fmt;
    view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
    view_info.subresourceRange.levelCount = 1;
    view_info.subresourceRange.layerCount = 1;
    vkCreateImageView(g_gpu_ctx.device, &view_info, NULL, &g_gpu_ctx.images[idx].view);

    // Transition to depth attachment layout
    VkCommandBuffer cmd = sage_gpu_begin_one_shot_v2();
    if (cmd) {
        VkImageMemoryBarrier barrier = {0};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = g_gpu_ctx.images[idx].image;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);
        sage_gpu_end_one_shot(cmd);
    }

    g_gpu_ctx.images[idx].format = SAGE_FORMAT_DEPTH32F;
    g_gpu_ctx.images[idx].width = w;
    g_gpu_ctx.images[idx].height = h;
    g_gpu_ctx.images[idx].depth = 1;
    g_gpu_ctx.images[idx].mip_levels = 1;
    g_gpu_ctx.images[idx].array_layers = 1;
    g_gpu_ctx.images[idx].alive = 1;
    return val_number(idx);
}

// gpu.create_swapchain_framebuffers_depth: defined in Window & Swapchain section below

// ============================================================================
// Staging Upload (device-local buffer via staging)
// ============================================================================

// gpu.upload_device_local(data_array, usage_flags) -> device-local buffer handle
static Value gpu_upload_device_local(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_number(SAGE_GPU_INVALID_HANDLE);
    if (!IS_ARRAY(args[0]) || !IS_NUMBER(args[1])) return val_number(SAGE_GPU_INVALID_HANDLE);

    ArrayValue* arr = args[0].as.array;
    VkDeviceSize size = sizeof(float) * (size_t)arr->count;
    int usage = (int)AS_NUMBER(args[1]);

    // Create staging buffer
    VkBuffer staging_buf;
    VkDeviceMemory staging_mem;
    {
        VkBufferCreateInfo buf_info = {0};
        buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        buf_info.size = size;
        buf_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        if (vkCreateBuffer(g_gpu_ctx.device, &buf_info, NULL, &staging_buf) != VK_SUCCESS)
            return val_number(SAGE_GPU_INVALID_HANDLE);

        VkMemoryRequirements req;
        vkGetBufferMemoryRequirements(g_gpu_ctx.device, staging_buf, &req);
        VkMemoryAllocateInfo a = {0};
        a.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        a.allocationSize = req.size;
        a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        if (vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &staging_mem) != VK_SUCCESS) {
            vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
            return val_number(SAGE_GPU_INVALID_HANDLE);
        }
        vkBindBufferMemory(g_gpu_ctx.device, staging_buf, staging_mem, 0);

        void* mapped;
        vkMapMemory(g_gpu_ctx.device, staging_mem, 0, size, 0, &mapped);
        float* dst = (float*)mapped;
        for (int i = 0; i < arr->count; i++) {
            dst[i] = IS_NUMBER(arr->elements[i]) ? (float)AS_NUMBER(arr->elements[i]) : 0.0f;
        }
        vkUnmapMemory(g_gpu_ctx.device, staging_mem);
    }

    // Create device-local buffer
    int idx = alloc_buffers();
    if (idx < 0) {
        vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
        vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    VkBufferCreateInfo buf_info = {0};
    buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buf_info.size = size;
    buf_info.usage = translate_buffer_usage(usage) | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    if (vkCreateBuffer(g_gpu_ctx.device, &buf_info, NULL, &g_gpu_ctx.buffers[idx].buffer) != VK_SUCCESS) {
        vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
        vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, &req);
    VkMemoryAllocateInfo a = {0};
    a.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    a.allocationSize = req.size;
    a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &g_gpu_ctx.buffers[idx].memory) != VK_SUCCESS) {
        vkDestroyBuffer(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, NULL);
        vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
        vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    vkBindBufferMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, g_gpu_ctx.buffers[idx].memory, 0);

    // Copy staging -> device-local
    VkCommandBuffer cmd = sage_gpu_begin_one_shot_v2();
    if (cmd) {
        VkBufferCopy region = {0};
        region.size = size;
        vkCmdCopyBuffer(cmd, staging_buf, g_gpu_ctx.buffers[idx].buffer, 1, &region);
        sage_gpu_end_one_shot(cmd);
    }

    vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
    vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);

    g_gpu_ctx.buffers[idx].size = size;
    g_gpu_ctx.buffers[idx].usage = usage;
    g_gpu_ctx.buffers[idx].mem_props = SAGE_MEMORY_DEVICE_LOCAL;
    g_gpu_ctx.buffers[idx].alive = 1;
    return val_number(idx);
}

// ============================================================================
// Texture Loading (stb_image)
// ============================================================================

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_THREAD_LOCALS
#include "stb_image.h"

// gpu.load_texture(path) -> image handle
static Value gpu_load_texture(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_STRING(args[0]))
        return val_number(SAGE_GPU_INVALID_HANDLE);

    int w, h, channels;
    unsigned char* pixels = stbi_load(AS_STRING(args[0]), &w, &h, &channels, 4); // Force RGBA
    if (!pixels) {
        fprintf(stderr, "gpu: failed to load texture '%s': %s\n", AS_STRING(args[0]), stbi_failure_reason());
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    VkDeviceSize img_size = (VkDeviceSize)w * (VkDeviceSize)h * 4;

    // Create staging buffer
    VkBuffer staging_buf;
    VkDeviceMemory staging_mem;
    {
        VkBufferCreateInfo buf_info = {0};
        buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        buf_info.size = img_size;
        buf_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        vkCreateBuffer(g_gpu_ctx.device, &buf_info, NULL, &staging_buf);

        VkMemoryRequirements req;
        vkGetBufferMemoryRequirements(g_gpu_ctx.device, staging_buf, &req);
        VkMemoryAllocateInfo a = {0};
        a.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        a.allocationSize = req.size;
        a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &staging_mem);
        vkBindBufferMemory(g_gpu_ctx.device, staging_buf, staging_mem, 0);

        void* mapped;
        vkMapMemory(g_gpu_ctx.device, staging_mem, 0, img_size, 0, &mapped);
        memcpy(mapped, pixels, (size_t)img_size);
        vkUnmapMemory(g_gpu_ctx.device, staging_mem);
    }
    stbi_image_free(pixels);

    // Create device-local image
    int idx = alloc_images();
    if (idx < 0) {
        vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
        vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }

    VkImageCreateInfo img_info = {0};
    img_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    img_info.imageType = VK_IMAGE_TYPE_2D;
    img_info.format = VK_FORMAT_R8G8B8A8_SRGB;
    img_info.extent.width = (uint32_t)w;
    img_info.extent.height = (uint32_t)h;
    img_info.extent.depth = 1;
    img_info.mipLevels = 1;
    img_info.arrayLayers = 1;
    img_info.samples = VK_SAMPLE_COUNT_1_BIT;
    img_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    img_info.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    img_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    vkCreateImage(g_gpu_ctx.device, &img_info, NULL, &g_gpu_ctx.images[idx].image);

    VkMemoryRequirements req;
    vkGetImageMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, &req);
    VkMemoryAllocateInfo alloc_i = {0};
    alloc_i.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_i.allocationSize = req.size;
    alloc_i.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(g_gpu_ctx.device, &alloc_i, NULL, &g_gpu_ctx.images[idx].memory);
    vkBindImageMemory(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, g_gpu_ctx.images[idx].memory, 0);

    // Transition + copy + transition
    VkCommandBuffer cmd = sage_gpu_begin_one_shot_v2();
    if (cmd) {
        // Transition to TRANSFER_DST
        VkImageMemoryBarrier barrier = {0};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = g_gpu_ctx.images[idx].image;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        // Copy
        VkBufferImageCopy region = {0};
        region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent.width = (uint32_t)w;
        region.imageExtent.height = (uint32_t)h;
        region.imageExtent.depth = 1;
        vkCmdCopyBufferToImage(cmd, staging_buf, g_gpu_ctx.images[idx].image,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        // Transition to SHADER_READ
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        sage_gpu_end_one_shot(cmd);
    }

    vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
    vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);

    // Create image view
    VkImageViewCreateInfo view_info = {0};
    view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = g_gpu_ctx.images[idx].image;
    view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view_info.format = VK_FORMAT_R8G8B8A8_SRGB;
    view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    view_info.subresourceRange.levelCount = 1;
    view_info.subresourceRange.layerCount = 1;
    vkCreateImageView(g_gpu_ctx.device, &view_info, NULL, &g_gpu_ctx.images[idx].view);

    g_gpu_ctx.images[idx].format = SAGE_FORMAT_RGBA8;
    g_gpu_ctx.images[idx].width = w;
    g_gpu_ctx.images[idx].height = h;
    g_gpu_ctx.images[idx].depth = 1;
    g_gpu_ctx.images[idx].mip_levels = 1;
    g_gpu_ctx.images[idx].array_layers = 1;
    g_gpu_ctx.images[idx].alive = 1;
    return val_number(idx);
}

// gpu.texture_dims(handle) -> dict {width, height}
static Value gpu_texture_dims(int argCount, Value* args) {
    return gpu_image_dims(argCount, args); // Reuse existing image_dims
}

// ============================================================================
// P2: Uniform Buffer Objects
// ============================================================================

// gpu.create_uniform_buffer(size) -> handle (host-visible, coherent)
static Value gpu_create_uniform_buffer(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_NUMBER(args[0]))
        return val_number(SAGE_GPU_INVALID_HANDLE);
    VkDeviceSize size = (VkDeviceSize)AS_NUMBER(args[0]);

    int idx = alloc_buffers();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkBufferCreateInfo buf_info = {0};
    buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buf_info.size = size;
    buf_info.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if (vkCreateBuffer(g_gpu_ctx.device, &buf_info, NULL, &g_gpu_ctx.buffers[idx].buffer) != VK_SUCCESS)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, &req);
    VkMemoryAllocateInfo a = {0};
    a.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    a.allocationSize = req.size;
    a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &g_gpu_ctx.buffers[idx].memory) != VK_SUCCESS) {
        vkDestroyBuffer(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, NULL);
        return val_number(SAGE_GPU_INVALID_HANDLE);
    }
    vkBindBufferMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, g_gpu_ctx.buffers[idx].memory, 0);
    vkMapMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].memory, 0, size, 0, &g_gpu_ctx.buffers[idx].mapped);

    g_gpu_ctx.buffers[idx].size = size;
    g_gpu_ctx.buffers[idx].usage = SAGE_BUFFER_UNIFORM;
    g_gpu_ctx.buffers[idx].mem_props = SAGE_MEMORY_HOST_VISIBLE | SAGE_MEMORY_HOST_COHERENT;
    g_gpu_ctx.buffers[idx].alive = 1;
    return val_number(idx);
}

// gpu.update_uniform(handle, data_array) -> nil  (fast mapped write)
static Value gpu_update_uniform(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_nil();
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[idx].alive) return val_nil();
    if (!g_gpu_ctx.buffers[idx].mapped || !IS_ARRAY(args[1])) return val_nil();

    ArrayValue* arr = args[1].as.array;
    float* dst = (float*)g_gpu_ctx.buffers[idx].mapped;
    int count = arr->count;
    if ((size_t)count * sizeof(float) > (size_t)g_gpu_ctx.buffers[idx].size)
        count = (int)(g_gpu_ctx.buffers[idx].size / sizeof(float));
    for (int i = 0; i < count; i++) {
        dst[i] = IS_NUMBER(arr->elements[i]) ? (float)AS_NUMBER(arr->elements[i]) : 0.0f;
    }
    return val_nil();
}

// ============================================================================
// P3: Render-to-texture (offscreen pass)
// ============================================================================

// gpu.create_offscreen_target(width, height, format, depth?) -> dict {image, framebuffer, render_pass}
static Value gpu_create_offscreen_target(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 3) return val_nil();
    int w = (int)AS_NUMBER(args[0]);
    int h = (int)AS_NUMBER(args[1]);
    int fmt = (int)AS_NUMBER(args[2]);
    int with_depth = (argCount >= 4 && IS_BOOL(args[3])) ? AS_BOOL(args[3]) : 0;

    // Create color image
    Value color_args[5];
    color_args[0] = val_number(w); color_args[1] = val_number(h); color_args[2] = val_number(1);
    color_args[3] = val_number(fmt);
    color_args[4] = val_number(SAGE_IMAGE_COLOR_ATTACH | SAGE_IMAGE_SAMPLED);
    Value color_h = gpu_create_image(5, color_args);
    if ((int)AS_NUMBER(color_h) < 0) return val_nil();

    // Create depth if requested
    Value depth_h = val_number(-1);
    if (with_depth) {
        Value depth_args[2] = {val_number(w), val_number(h)};
        depth_h = gpu_create_depth_buffer(2, depth_args);
    }

    // Create render pass
    int attach_count = with_depth ? 2 : 1;
    Value attach_arr = val_array();

    Value ca = val_dict();
    dict_set(&ca, "format", val_number(fmt));
    dict_set(&ca, "load_op", val_number(SAGE_LOAD_CLEAR));
    dict_set(&ca, "store_op", val_number(SAGE_STORE_STORE));
    dict_set(&ca, "initial_layout", val_number(SAGE_LAYOUT_UNDEFINED));
    dict_set(&ca, "final_layout", val_number(SAGE_LAYOUT_SHADER_READ));
    array_push(&attach_arr, ca);

    if (with_depth) {
        Value da = val_dict();
        dict_set(&da, "format", val_number(SAGE_FORMAT_DEPTH32F));
        dict_set(&da, "load_op", val_number(SAGE_LOAD_CLEAR));
        dict_set(&da, "store_op", val_number(SAGE_STORE_DONTCARE));
        dict_set(&da, "initial_layout", val_number(SAGE_LAYOUT_UNDEFINED));
        dict_set(&da, "final_layout", val_number(SAGE_LAYOUT_DEPTH_ATTACH));
        array_push(&attach_arr, da);
    }

    Value rp_args[1] = {attach_arr};
    Value rp_h = gpu_create_render_pass(1, rp_args);

    // Create framebuffer
    int rp_idx = (int)AS_NUMBER(rp_h);
    int color_idx = (int)AS_NUMBER(color_h);
    int fb_idx = alloc_framebuffers();
    if (fb_idx >= 0 && rp_idx >= 0) {
        VkImageView views[2];
        views[0] = g_gpu_ctx.images[color_idx].view;
        int view_count = 1;
        if (with_depth && (int)AS_NUMBER(depth_h) >= 0) {
            views[1] = g_gpu_ctx.images[(int)AS_NUMBER(depth_h)].view;
            view_count = 2;
        }

        VkFramebufferCreateInfo fb_info = {0};
        fb_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fb_info.renderPass = g_gpu_ctx.render_passes[rp_idx].render_pass;
        fb_info.attachmentCount = (uint32_t)view_count;
        fb_info.pAttachments = views;
        fb_info.width = (uint32_t)w;
        fb_info.height = (uint32_t)h;
        fb_info.layers = 1;
        vkCreateFramebuffer(g_gpu_ctx.device, &fb_info, NULL, &g_gpu_ctx.framebuffers[fb_idx].framebuffer);
        g_gpu_ctx.framebuffers[fb_idx].width = w;
        g_gpu_ctx.framebuffers[fb_idx].height = h;
        g_gpu_ctx.framebuffers[fb_idx].alive = 1;
    }

    Value result = val_dict();
    dict_set(&result, "image", color_h);
    dict_set(&result, "depth", depth_h);
    dict_set(&result, "render_pass", rp_h);
    dict_set(&result, "framebuffer", val_number(fb_idx));
    dict_set(&result, "width", val_number(w));
    dict_set(&result, "height", val_number(h));
    return result;
}

// ============================================================================
// P6: Mipmaps + Anisotropic filtering
// ============================================================================

// gpu.generate_mipmaps(image, width, height) -> nil
static Value gpu_generate_mipmaps(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 3) return val_nil();
    int img_idx = (int)AS_NUMBER(args[0]);
    int w = (int)AS_NUMBER(args[1]);
    int h = (int)AS_NUMBER(args[2]);
    if (img_idx < 0 || img_idx >= g_gpu_ctx.image_count || !g_gpu_ctx.images[img_idx].alive) return val_nil();

    int mip_levels = 1;
    int tw = w, th = h;
    while (tw > 1 || th > 1) { mip_levels++; tw /= 2; th /= 2; }

    VkCommandBuffer cmd = sage_gpu_begin_one_shot_v2();
    if (!cmd) return val_nil();

    int mip_w = w, mip_h = h;
    for (int i = 1; i < mip_levels; i++) {
        // Transition src level to TRANSFER_SRC
        VkImageMemoryBarrier barrier = {0};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.image = g_gpu_ctx.images[img_idx].image;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.baseMipLevel = (uint32_t)(i - 1);
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        if (i == 1) {
            barrier.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            barrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        }
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        // Transition dst level to TRANSFER_DST
        barrier.subresourceRange.baseMipLevel = (uint32_t)i;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        // Blit
        int dst_w = mip_w > 1 ? mip_w / 2 : 1;
        int dst_h = mip_h > 1 ? mip_h / 2 : 1;
        VkImageBlit blit = {0};
        blit.srcOffsets[1].x = mip_w; blit.srcOffsets[1].y = mip_h; blit.srcOffsets[1].z = 1;
        blit.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.srcSubresource.mipLevel = (uint32_t)(i - 1);
        blit.srcSubresource.layerCount = 1;
        blit.dstOffsets[1].x = dst_w; blit.dstOffsets[1].y = dst_h; blit.dstOffsets[1].z = 1;
        blit.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.dstSubresource.mipLevel = (uint32_t)i;
        blit.dstSubresource.layerCount = 1;
        vkCmdBlitImage(cmd, g_gpu_ctx.images[img_idx].image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            g_gpu_ctx.images[img_idx].image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);

        mip_w = dst_w; mip_h = dst_h;
    }

    // Transition all levels to SHADER_READ
    VkImageMemoryBarrier final_barrier = {0};
    final_barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    final_barrier.image = g_gpu_ctx.images[img_idx].image;
    final_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    final_barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    final_barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    final_barrier.subresourceRange.levelCount = (uint32_t)mip_levels;
    final_barrier.subresourceRange.layerCount = 1;
    final_barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    final_barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    final_barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    final_barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0, 0, NULL, 0, NULL, 1, &final_barrier);

    sage_gpu_end_one_shot(cmd);
    g_gpu_ctx.images[img_idx].mip_levels = mip_levels;
    return val_nil();
}

// gpu.create_sampler_advanced(mag, min, address, anisotropy, mip_levels) -> handle
static Value gpu_create_sampler_advanced(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 5) return val_number(SAGE_GPU_INVALID_HANDLE);
    int idx = alloc_samplers();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkSamplerCreateInfo info = {0};
    info.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    info.magFilter = translate_filter((int)AS_NUMBER(args[0]));
    info.minFilter = translate_filter((int)AS_NUMBER(args[1]));
    info.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    info.addressModeU = translate_address_mode((int)AS_NUMBER(args[2]));
    info.addressModeV = info.addressModeU;
    info.addressModeW = info.addressModeU;
    float aniso = (float)AS_NUMBER(args[3]);
    if (aniso > 1.0f) {
        info.anisotropyEnable = VK_TRUE;
        info.maxAnisotropy = aniso;
        if (info.maxAnisotropy > g_gpu_ctx.device_props.limits.maxSamplerAnisotropy)
            info.maxAnisotropy = g_gpu_ctx.device_props.limits.maxSamplerAnisotropy;
    }
    info.maxLod = (float)AS_NUMBER(args[4]);

    if (vkCreateSampler(g_gpu_ctx.device, &info, NULL, &g_gpu_ctx.samplers[idx].sampler) != VK_SUCCESS)
        return val_number(SAGE_GPU_INVALID_HANDLE);
    g_gpu_ctx.samplers[idx].alive = 1;
    return val_number(idx);
}

// ============================================================================
// P8: Indirect draw/dispatch
// ============================================================================

// gpu.cmd_draw_indirect(cmd, buffer, offset, draw_count, stride) -> nil
static Value gpu_cmd_draw_indirect(int argCount, Value* args) {
    if (argCount < 5) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int bi = (int)AS_NUMBER(args[1]);
    if (ci < 0 || ci >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[ci].alive) return val_nil();
    if (bi < 0 || bi >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[bi].alive) return val_nil();
    VkDeviceSize offset = (VkDeviceSize)AS_NUMBER(args[2]);
    uint32_t draw_count = (uint32_t)AS_NUMBER(args[3]);
    uint32_t stride = (uint32_t)AS_NUMBER(args[4]);
    vkCmdDrawIndirect(g_gpu_ctx.cmd_buffers[ci].cmd, g_gpu_ctx.buffers[bi].buffer, offset, draw_count, stride);
    return val_nil();
}

// gpu.cmd_draw_indexed_indirect(cmd, buffer, offset, draw_count, stride) -> nil
static Value gpu_cmd_draw_indexed_indirect(int argCount, Value* args) {
    if (argCount < 5) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int bi = (int)AS_NUMBER(args[1]);
    if (ci < 0 || ci >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[ci].alive) return val_nil();
    if (bi < 0 || bi >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[bi].alive) return val_nil();
    VkDeviceSize offset = (VkDeviceSize)AS_NUMBER(args[2]);
    uint32_t draw_count = (uint32_t)AS_NUMBER(args[3]);
    uint32_t stride = (uint32_t)AS_NUMBER(args[4]);
    vkCmdDrawIndexedIndirect(g_gpu_ctx.cmd_buffers[ci].cmd, g_gpu_ctx.buffers[bi].buffer, offset, draw_count, stride);
    return val_nil();
}

// gpu.cmd_dispatch_indirect(cmd, buffer, offset) -> nil
static Value gpu_cmd_dispatch_indirect(int argCount, Value* args) {
    if (argCount < 3) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    int bi = (int)AS_NUMBER(args[1]);
    if (ci < 0 || ci >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[ci].alive) return val_nil();
    if (bi < 0 || bi >= g_gpu_ctx.buffer_count || !g_gpu_ctx.buffers[bi].alive) return val_nil();
    VkDeviceSize offset = (VkDeviceSize)AS_NUMBER(args[2]);
    vkCmdDispatchIndirect(g_gpu_ctx.cmd_buffers[ci].cmd, g_gpu_ctx.buffers[bi].buffer, offset);
    return val_nil();
}

// ============================================================================
// P9: 3D Textures
// ============================================================================

// gpu.create_image_3d(w, h, d, format, usage) -> handle  (with 3D view)
static Value gpu_create_image_3d(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 5) return val_number(SAGE_GPU_INVALID_HANDLE);
    int w = (int)AS_NUMBER(args[0]), h = (int)AS_NUMBER(args[1]), d = (int)AS_NUMBER(args[2]);
    int fmt = (int)AS_NUMBER(args[3]), usage = (int)AS_NUMBER(args[4]);

    int idx = alloc_images();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkImageCreateInfo img_info = {0};
    img_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    img_info.imageType = VK_IMAGE_TYPE_3D;
    img_info.format = sage_gpu_translate_format(fmt);
    img_info.extent = (VkExtent3D){(uint32_t)w, (uint32_t)h, (uint32_t)d};
    img_info.mipLevels = 1;
    img_info.arrayLayers = 1;
    img_info.samples = VK_SAMPLE_COUNT_1_BIT;
    img_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    img_info.usage = translate_image_usage(usage);

    if (vkCreateImage(g_gpu_ctx.device, &img_info, NULL, &g_gpu_ctx.images[idx].image) != VK_SUCCESS)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    VkMemoryRequirements req;
    vkGetImageMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, &req);
    VkMemoryAllocateInfo a = {0};
    a.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    a.allocationSize = req.size;
    a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &g_gpu_ctx.images[idx].memory);
    vkBindImageMemory(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, g_gpu_ctx.images[idx].memory, 0);

    VkImageViewCreateInfo view_info = {0};
    view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = g_gpu_ctx.images[idx].image;
    view_info.viewType = VK_IMAGE_VIEW_TYPE_3D;
    view_info.format = img_info.format;
    view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    view_info.subresourceRange.levelCount = 1;
    view_info.subresourceRange.layerCount = 1;
    vkCreateImageView(g_gpu_ctx.device, &view_info, NULL, &g_gpu_ctx.images[idx].view);

    g_gpu_ctx.images[idx].format = fmt;
    g_gpu_ctx.images[idx].img_type = SAGE_IMAGE_3D;
    g_gpu_ctx.images[idx].width = w; g_gpu_ctx.images[idx].height = h; g_gpu_ctx.images[idx].depth = d;
    g_gpu_ctx.images[idx].mip_levels = 1; g_gpu_ctx.images[idx].array_layers = 1;
    g_gpu_ctx.images[idx].usage = usage; g_gpu_ctx.images[idx].alive = 1;
    return val_number(idx);
}

// ============================================================================
// P10: Multi-binding vertex buffers for instanced rendering
// ============================================================================

// gpu.cmd_bind_vertex_buffers(cmd, buffer_handles_array) -> nil
static Value gpu_cmd_bind_vertex_buffers(int argCount, Value* args) {
    if (argCount < 2) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    if (ci < 0 || ci >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[ci].alive) return val_nil();
    if (!IS_ARRAY(args[1])) return val_nil();

    ArrayValue* arr = args[1].as.array;
    int count = arr->count;
    if (count > 8) count = 8;

    VkBuffer bufs[8] = {0};
    VkDeviceSize offsets[8] = {0};
    for (int i = 0; i < count; i++) {
        int bi = (int)AS_NUMBER(arr->elements[i]);
        if (bi >= 0 && bi < g_gpu_ctx.buffer_count && g_gpu_ctx.buffers[bi].alive)
            bufs[i] = g_gpu_ctx.buffers[bi].buffer;
    }

    vkCmdBindVertexBuffers(g_gpu_ctx.cmd_buffers[ci].cmd, 0, (uint32_t)count, bufs, offsets);
    return val_nil();
}

// ============================================================================
// P11: Multiple render targets (MRT) for deferred rendering
// ============================================================================

// gpu.create_render_pass_mrt(color_formats_array, has_depth?) -> handle
static Value gpu_create_render_pass_mrt(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !IS_ARRAY(args[0]))
        return val_number(SAGE_GPU_INVALID_HANDLE);

    ArrayValue* fmt_arr = args[0].as.array;
    int color_count = fmt_arr->count;
    if (color_count > SAGE_GPU_MAX_COLOR_ATTACHMENTS) color_count = SAGE_GPU_MAX_COLOR_ATTACHMENTS;
    int with_depth = (argCount >= 2 && IS_BOOL(args[1])) ? AS_BOOL(args[1]) : 0;
    int total = color_count + (with_depth ? 1 : 0);

    VkAttachmentDescription attachments[SAGE_GPU_MAX_COLOR_ATTACHMENTS + 1] = {0};
    VkAttachmentReference color_refs[SAGE_GPU_MAX_COLOR_ATTACHMENTS] = {0};
    VkAttachmentReference depth_ref = {0};

    for (int i = 0; i < color_count; i++) {
        int fmt = IS_NUMBER(fmt_arr->elements[i]) ? (int)AS_NUMBER(fmt_arr->elements[i]) : SAGE_FORMAT_RGBA16F;
        attachments[i].format = sage_gpu_translate_format(fmt);
        attachments[i].samples = VK_SAMPLE_COUNT_1_BIT;
        attachments[i].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[i].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        attachments[i].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachments[i].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[i].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[i].finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        color_refs[i].attachment = (uint32_t)i;
        color_refs[i].layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    }

    if (with_depth) {
        VkFormat depth_fmt = sage_gpu_find_depth_format();
        attachments[color_count].format = depth_fmt;
        attachments[color_count].samples = VK_SAMPLE_COUNT_1_BIT;
        attachments[color_count].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[color_count].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[color_count].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachments[color_count].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[color_count].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[color_count].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        depth_ref.attachment = (uint32_t)color_count;
        depth_ref.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    }

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = (uint32_t)color_count;
    subpass.pColorAttachments = color_refs;
    if (with_depth) subpass.pDepthStencilAttachment = &depth_ref;

    int idx = alloc_render_passes();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkRenderPassCreateInfo rp_info = {0};
    rp_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rp_info.attachmentCount = (uint32_t)total;
    rp_info.pAttachments = attachments;
    rp_info.subpassCount = 1;
    rp_info.pSubpasses = &subpass;

    if (vkCreateRenderPass(g_gpu_ctx.device, &rp_info, NULL,
                            &g_gpu_ctx.render_passes[idx].render_pass) != VK_SUCCESS)
        return val_number(SAGE_GPU_INVALID_HANDLE);
    g_gpu_ctx.render_passes[idx].alive = 1;
    return val_number(idx);
}

// ============================================================================
// P13: glTF loading helpers (binary buffer upload)
// ============================================================================

// gpu.upload_bytes(byte_array, usage) -> buffer handle
// Like upload_device_local but treats array values as raw uint8 bytes packed into 4-byte words
static Value gpu_upload_bytes(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_number(SAGE_GPU_INVALID_HANDLE);
    if (!IS_ARRAY(args[0]) || !IS_NUMBER(args[1])) return val_number(SAGE_GPU_INVALID_HANDLE);

    ArrayValue* arr = args[0].as.array;
    VkDeviceSize size = (VkDeviceSize)arr->count;
    int usage = (int)AS_NUMBER(args[1]);

    // Create staging
    VkBuffer staging_buf; VkDeviceMemory staging_mem;
    VkBufferCreateInfo buf_info = {0};
    buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buf_info.size = size;
    buf_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (vkCreateBuffer(g_gpu_ctx.device, &buf_info, NULL, &staging_buf) != VK_SUCCESS)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(g_gpu_ctx.device, staging_buf, &req);
    VkMemoryAllocateInfo a = {0};
    a.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    a.allocationSize = req.size;
    a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &staging_mem);
    vkBindBufferMemory(g_gpu_ctx.device, staging_buf, staging_mem, 0);

    void* mapped;
    vkMapMemory(g_gpu_ctx.device, staging_mem, 0, size, 0, &mapped);
    unsigned char* dst = (unsigned char*)mapped;
    for (int i = 0; i < arr->count; i++) {
        dst[i] = IS_NUMBER(arr->elements[i]) ? (unsigned char)(int)AS_NUMBER(arr->elements[i]) : 0;
    }
    vkUnmapMemory(g_gpu_ctx.device, staging_mem);

    // Device-local
    int idx = alloc_buffers();
    if (idx < 0) { vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL); vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL); return val_number(SAGE_GPU_INVALID_HANDLE); }

    buf_info.size = size;
    buf_info.usage = translate_buffer_usage(usage) | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    vkCreateBuffer(g_gpu_ctx.device, &buf_info, NULL, &g_gpu_ctx.buffers[idx].buffer);
    vkGetBufferMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, &req);
    a.allocationSize = req.size;
    a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &g_gpu_ctx.buffers[idx].memory);
    vkBindBufferMemory(g_gpu_ctx.device, g_gpu_ctx.buffers[idx].buffer, g_gpu_ctx.buffers[idx].memory, 0);

    VkCommandBuffer cmd = sage_gpu_begin_one_shot_v2();
    if (cmd) {
        VkBufferCopy region = {0}; region.size = size;
        vkCmdCopyBuffer(cmd, staging_buf, g_gpu_ctx.buffers[idx].buffer, 1, &region);
        sage_gpu_end_one_shot(cmd);
    }

    vkDestroyBuffer(g_gpu_ctx.device, staging_buf, NULL);
    vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);
    g_gpu_ctx.buffers[idx].size = size;
    g_gpu_ctx.buffers[idx].usage = usage;
    g_gpu_ctx.buffers[idx].alive = 1;
    return val_number(idx);
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
// Window & Swapchain (requires GLFW)
// ============================================================================

#ifdef SAGE_HAS_GLFW

static GLFWwindow* g_window = NULL;

// Forward declarations for callbacks
static void framebuffer_resize_cb(GLFWwindow* window, int w, int h);
static void scroll_callback(GLFWwindow* window, double xoff, double yoff);
static void glfw_error_callback(int error, const char* description);

// ============================================================================
// Platform detection and selection
// ============================================================================
// Platform constants
#define SAGE_PLATFORM_AUTO    0
#define SAGE_PLATFORM_X11     1
#define SAGE_PLATFORM_WAYLAND 2
#define SAGE_PLATFORM_ANY     3  // Let GLFW decide (no hint)

static int g_platform_preference = SAGE_PLATFORM_AUTO;
static int g_active_platform = SAGE_PLATFORM_AUTO;

static int detect_display_server(void) {
    const char* wayland = getenv("WAYLAND_DISPLAY");
    const char* x11 = getenv("DISPLAY");
    const char* session = getenv("XDG_SESSION_TYPE");
    const char* sage_platform = getenv("SAGE_GPU_PLATFORM");

    // Honor environment override first
    if (sage_platform) {
        if (strcmp(sage_platform, "x11") == 0) return SAGE_PLATFORM_X11;
        if (strcmp(sage_platform, "wayland") == 0) return SAGE_PLATFORM_WAYLAND;
    }

    // On Wayland compositors: DISPLAY is usually set too (XWayland).
    // Prefer X11/XWayland for stability (avoids libdecor crashes).
    // Pure Wayland only when DISPLAY is absent.
    if (x11 && x11[0] != '\0') return SAGE_PLATFORM_X11;  // X11 or XWayland
    if (wayland && wayland[0] != '\0') return SAGE_PLATFORM_WAYLAND;  // Pure Wayland

    // Explicit session type as last resort
    if (session) {
        if (strcmp(session, "wayland") == 0) return SAGE_PLATFORM_WAYLAND;
        if (strcmp(session, "x11") == 0) return SAGE_PLATFORM_X11;
    }

    return SAGE_PLATFORM_X11; // Default fallback
}

static void apply_platform_hint(void) {
    int target = g_platform_preference;
    if (target == SAGE_PLATFORM_AUTO) {
        target = detect_display_server();
    }

#if defined(GLFW_PLATFORM_WAYLAND) && defined(GLFW_PLATFORM_X11)
    if (target == SAGE_PLATFORM_WAYLAND) {
        glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_WAYLAND);
#ifdef GLFW_WAYLAND_LIBDECOR
        // Disable libdecor completely to avoid GTK plugin crashes.
        // Server-side decorations work without it. Users with working
        // libdecor can set SAGE_WAYLAND_LIBDECOR=1 to re-enable.
        const char* use_libdecor = getenv("SAGE_WAYLAND_LIBDECOR");
        if (use_libdecor && strcmp(use_libdecor, "1") == 0) {
            glfwInitHint(GLFW_WAYLAND_LIBDECOR, GLFW_WAYLAND_PREFER_LIBDECOR);
        } else {
            glfwInitHint(GLFW_WAYLAND_LIBDECOR, GLFW_WAYLAND_DISABLE_LIBDECOR);
        }
#endif
        g_active_platform = SAGE_PLATFORM_WAYLAND;
    } else if (target == SAGE_PLATFORM_X11) {
        glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_X11);
        g_active_platform = SAGE_PLATFORM_X11;
    } else {
        // SAGE_PLATFORM_ANY: no hint, let GLFW decide
        g_active_platform = detect_display_server();
    }
#elif defined(GLFW_PLATFORM_X11)
    glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_X11);
    g_active_platform = SAGE_PLATFORM_X11;
#elif defined(GLFW_PLATFORM_WAYLAND)
    glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_WAYLAND);
    g_active_platform = SAGE_PLATFORM_WAYLAND;
#else
    // GLFW < 3.4: no platform hints available
    g_active_platform = SAGE_PLATFORM_X11;
#endif
}

static int try_init_glfw_with_fallback(void) {
    glfwSetErrorCallback(glfw_error_callback);
    apply_platform_hint();

    if (glfwInit()) {
        return 1;
    }

    // If Wayland failed, try X11 fallback (XWayland)
    if (g_active_platform == SAGE_PLATFORM_WAYLAND) {
        fprintf(stderr, "gpu: Wayland init failed, trying X11/XWayland fallback\n");
#ifdef GLFW_PLATFORM_X11
        glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_X11);
        g_active_platform = SAGE_PLATFORM_X11;
        if (glfwInit()) {
            return 1;
        }
#endif
    }

    // If X11 failed, try Wayland fallback
    if (g_active_platform == SAGE_PLATFORM_X11) {
        fprintf(stderr, "gpu: X11 init failed, trying Wayland fallback\n");
#ifdef GLFW_PLATFORM_WAYLAND
        glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_WAYLAND);
#ifdef GLFW_WAYLAND_LIBDECOR
        glfwInitHint(GLFW_WAYLAND_LIBDECOR, GLFW_WAYLAND_DISABLE_LIBDECOR);
#endif
        g_active_platform = SAGE_PLATFORM_WAYLAND;
        if (glfwInit()) {
            return 1;
        }
#endif
    }

    fprintf(stderr, "gpu: all platform init attempts failed\n");
    return 0;
}

// gpu.set_platform(platform_str) -> nil
// Call BEFORE init_windowed. "auto", "x11", "wayland", "any"
static Value gpu_set_platform(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    const char* p = AS_STRING(args[0]);
    if (strcmp(p, "x11") == 0 || strcmp(p, "X11") == 0 || strcmp(p, "xorg") == 0) {
        g_platform_preference = SAGE_PLATFORM_X11;
    } else if (strcmp(p, "wayland") == 0 || strcmp(p, "Wayland") == 0) {
        g_platform_preference = SAGE_PLATFORM_WAYLAND;
    } else if (strcmp(p, "any") == 0) {
        g_platform_preference = SAGE_PLATFORM_ANY;
    } else {
        g_platform_preference = SAGE_PLATFORM_AUTO;
    }
    return val_nil();
}

// gpu.get_platform() -> string
static Value gpu_get_platform(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (g_active_platform == SAGE_PLATFORM_WAYLAND) return val_string("wayland");
    if (g_active_platform == SAGE_PLATFORM_X11) return val_string("x11");
    return val_string("unknown");
}

// gpu.detected_platform() -> string  (what the OS is running)
static Value gpu_detected_platform(int argCount, Value* args) {
    (void)argCount; (void)args;
    int detected = detect_display_server();
    if (detected == SAGE_PLATFORM_WAYLAND) return val_string("wayland");
    if (detected == SAGE_PLATFORM_X11) return val_string("x11");
    return val_string("unknown");
}
static VkSurfaceKHR g_surface = VK_NULL_HANDLE;
static VkSwapchainKHR g_swapchain = VK_NULL_HANDLE;
static VkImage* g_swapchain_images = NULL;
static VkImageView* g_swapchain_views = NULL;
static uint32_t g_swapchain_image_count = 0;
static VkFormat g_swapchain_format = VK_FORMAT_B8G8R8A8_UNORM;
static uint32_t g_swapchain_width = 0;
static uint32_t g_swapchain_height = 0;

static void glfw_error_callback(int error, const char* description) {
    fprintf(stderr, "GLFW error %d: %s\n", error, description);
}

// gpu.create_window(width, height, title) -> bool
static Value gpu_create_window(int argCount, Value* args) {
    if (argCount < 3) return val_bool(0);
    int w = IS_NUMBER(args[0]) ? (int)AS_NUMBER(args[0]) : 800;
    int h = IS_NUMBER(args[1]) ? (int)AS_NUMBER(args[1]) : 600;
    const char* title = IS_STRING(args[2]) ? AS_STRING(args[2]) : "Sage GPU";

    if (!try_init_glfw_with_fallback()) {
        return val_bool(0);
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
    g_window = glfwCreateWindow(w, h, title, NULL, NULL);
    if (!g_window) {
        fprintf(stderr, "gpu: window creation failed\n");
        glfwTerminate();
        return val_bool(0);
    }
    return val_bool(1);
}

// gpu.destroy_window() -> nil
static Value gpu_destroy_window(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (g_window) {
        glfwDestroyWindow(g_window);
        g_window = NULL;
    }
    glfwTerminate();
    return val_nil();
}

// gpu.window_should_close() -> bool
static Value gpu_window_should_close(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_window) return val_bool(1);
    return val_bool(glfwWindowShouldClose(g_window));
}

// gpu.poll_events() -> nil
static Value gpu_poll_events(int argCount, Value* args) {
    (void)argCount; (void)args;
    glfwPollEvents();
    return val_nil();
}

// gpu.init_windowed(app_name, width, height, title, validation?) -> bool
// Combines window creation + Vulkan init with surface support
static Value gpu_init_windowed(int argCount, Value* args) {
    if (argCount < 4) return val_bool(0);
    const char* app_name = IS_STRING(args[0]) ? AS_STRING(args[0]) : "SageLang GPU";
    int w = IS_NUMBER(args[1]) ? (int)AS_NUMBER(args[1]) : 800;
    int h = IS_NUMBER(args[2]) ? (int)AS_NUMBER(args[2]) : 600;
    const char* title = IS_STRING(args[3]) ? AS_STRING(args[3]) : "Sage GPU";
    int validation = (argCount >= 5 && IS_BOOL(args[4])) ? AS_BOOL(args[4]) : 0;

    if (g_gpu_ctx.initialized) return val_bool(1);

    // Init GLFW with platform auto-detection and fallback
    if (!try_init_glfw_with_fallback()) {
        return val_bool(0);
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
    g_window = glfwCreateWindow(w, h, title, NULL, NULL);
    if (!g_window) {
        // Window creation failed on chosen platform — try fallback
        glfwTerminate();
        if (g_active_platform == SAGE_PLATFORM_WAYLAND) {
            fprintf(stderr, "gpu: Wayland window failed, falling back to X11/XWayland\n");
            g_platform_preference = SAGE_PLATFORM_X11;
            if (!try_init_glfw_with_fallback()) return val_bool(0);
            glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
            glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
            g_window = glfwCreateWindow(w, h, title, NULL, NULL);
        }
        if (!g_window) {
            fprintf(stderr, "gpu: window creation failed on all platforms\n");
            glfwTerminate();
            return val_bool(0);
        }
    }

    // Set up callbacks
    glfwSetFramebufferSizeCallback(g_window, framebuffer_resize_cb);
    glfwSetScrollCallback(g_window, scroll_callback);

    // Get required extensions from GLFW
    uint32_t glfw_ext_count = 0;
    const char** glfw_exts = glfwGetRequiredInstanceExtensions(&glfw_ext_count);

    // Build extension list (GLFW + debug if validation)
    uint32_t total_ext_count = glfw_ext_count + (validation ? 1 : 0);
    const char** all_exts = calloc(total_ext_count, sizeof(const char*));
    for (uint32_t i = 0; i < glfw_ext_count; i++) all_exts[i] = glfw_exts[i];
    if (validation) all_exts[glfw_ext_count] = VK_EXT_DEBUG_UTILS_EXTENSION_NAME;

    // Create instance
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
    create_info.enabledExtensionCount = total_ext_count;
    create_info.ppEnabledExtensionNames = all_exts;

    const char* validation_layers[] = {"VK_LAYER_KHRONOS_validation"};
    if (validation) {
        create_info.enabledLayerCount = 1;
        create_info.ppEnabledLayerNames = validation_layers;
        g_gpu_ctx.validation_enabled = 1;
    }

    VkResult res = vkCreateInstance(&create_info, NULL, &g_gpu_ctx.instance);
    free(all_exts);
    if (res != VK_SUCCESS) {
        fprintf(stderr, "gpu: vkCreateInstance failed (%d)\n", res);
        return val_bool(0);
    }

    // Create surface
    res = glfwCreateWindowSurface(g_gpu_ctx.instance, g_window, NULL, &g_surface);
    if (res != VK_SUCCESS) {
        fprintf(stderr, "gpu: surface creation failed (%d)\n", res);
        return val_bool(0);
    }

    // Pick physical device (prefer discrete, must support present)
    uint32_t dev_count = 0;
    vkEnumeratePhysicalDevices(g_gpu_ctx.instance, &dev_count, NULL);
    if (dev_count == 0) { fprintf(stderr, "gpu: no GPU found\n"); return val_bool(0); }
    VkPhysicalDevice* devices = calloc(dev_count, sizeof(VkPhysicalDevice));
    vkEnumeratePhysicalDevices(g_gpu_ctx.instance, &dev_count, devices);
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

    // Find queue families (graphics + present)
    uint32_t qf_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(g_gpu_ctx.physical_device, &qf_count, NULL);
    VkQueueFamilyProperties* qf_props = calloc(qf_count, sizeof(VkQueueFamilyProperties));
    vkGetPhysicalDeviceQueueFamilyProperties(g_gpu_ctx.physical_device, &qf_count, qf_props);

    g_gpu_ctx.graphics_family = UINT32_MAX;
    uint32_t present_family = UINT32_MAX;
    for (uint32_t i = 0; i < qf_count; i++) {
        if (qf_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) g_gpu_ctx.graphics_family = i;
        VkBool32 present_support = VK_FALSE;
        vkGetPhysicalDeviceSurfaceSupportKHR(g_gpu_ctx.physical_device, i, g_surface, &present_support);
        if (present_support) present_family = i;
    }
    free(qf_props);
    g_gpu_ctx.compute_family = g_gpu_ctx.graphics_family;
    g_gpu_ctx.transfer_family = g_gpu_ctx.graphics_family;

    if (g_gpu_ctx.graphics_family == UINT32_MAX || present_family == UINT32_MAX) {
        fprintf(stderr, "gpu: no suitable queue families\n");
        return val_bool(0);
    }

    // Create logical device with swapchain extension
    float priority = 1.0f;
    uint32_t unique_families[2] = {g_gpu_ctx.graphics_family, present_family};
    int unique_count = (g_gpu_ctx.graphics_family == present_family) ? 1 : 2;
    VkDeviceQueueCreateInfo queue_infos[2] = {0};
    for (int i = 0; i < unique_count; i++) {
        queue_infos[i].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_infos[i].queueFamilyIndex = unique_families[i];
        queue_infos[i].queueCount = 1;
        queue_infos[i].pQueuePriorities = &priority;
    }

    const char* dev_exts[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkPhysicalDeviceFeatures features = {0};
    features.fillModeNonSolid = VK_TRUE;

    VkDeviceCreateInfo dev_info = {0};
    dev_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dev_info.queueCreateInfoCount = (uint32_t)unique_count;
    dev_info.pQueueCreateInfos = queue_infos;
    dev_info.enabledExtensionCount = 1;
    dev_info.ppEnabledExtensionNames = dev_exts;
    dev_info.pEnabledFeatures = &features;

    res = vkCreateDevice(g_gpu_ctx.physical_device, &dev_info, NULL, &g_gpu_ctx.device);
    if (res != VK_SUCCESS) { fprintf(stderr, "gpu: device creation failed\n"); return val_bool(0); }

    vkGetDeviceQueue(g_gpu_ctx.device, g_gpu_ctx.graphics_family, 0, &g_gpu_ctx.graphics_queue);
    g_gpu_ctx.compute_queue = g_gpu_ctx.graphics_queue;
    g_gpu_ctx.transfer_queue = g_gpu_ctx.graphics_queue;

    // Create swapchain
    VkSurfaceCapabilitiesKHR surf_caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(g_gpu_ctx.physical_device, g_surface, &surf_caps);

    VkExtent2D extent = surf_caps.currentExtent;
    if (extent.width == UINT32_MAX) {
        extent.width = (uint32_t)w;
        extent.height = (uint32_t)h;
    }
    g_swapchain_width = extent.width;
    g_swapchain_height = extent.height;

    uint32_t img_count = surf_caps.minImageCount + 1;
    if (surf_caps.maxImageCount > 0 && img_count > surf_caps.maxImageCount)
        img_count = surf_caps.maxImageCount;

    // Pick format (prefer B8G8R8A8_SRGB)
    uint32_t fmt_count = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(g_gpu_ctx.physical_device, g_surface, &fmt_count, NULL);
    VkSurfaceFormatKHR* formats = calloc(fmt_count, sizeof(VkSurfaceFormatKHR));
    vkGetPhysicalDeviceSurfaceFormatsKHR(g_gpu_ctx.physical_device, g_surface, &fmt_count, formats);
    g_swapchain_format = formats[0].format;
    g_active_swapchain_format = formats[0].format;
    VkColorSpaceKHR color_space = formats[0].colorSpace;
    for (uint32_t i = 0; i < fmt_count; i++) {
        if (formats[i].format == VK_FORMAT_B8G8R8A8_SRGB &&
            formats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            g_swapchain_format = formats[i].format;
            g_active_swapchain_format = formats[i].format;
            color_space = formats[i].colorSpace;
            break;
        }
    }
    free(formats);

    // Pick present mode (prefer mailbox, fallback FIFO)
    uint32_t pm_count = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR(g_gpu_ctx.physical_device, g_surface, &pm_count, NULL);
    VkPresentModeKHR* present_modes = calloc(pm_count, sizeof(VkPresentModeKHR));
    vkGetPhysicalDeviceSurfacePresentModesKHR(g_gpu_ctx.physical_device, g_surface, &pm_count, present_modes);
    VkPresentModeKHR present_mode = VK_PRESENT_MODE_FIFO_KHR;
    for (uint32_t i = 0; i < pm_count; i++) {
        if (present_modes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
            present_mode = VK_PRESENT_MODE_MAILBOX_KHR;
            break;
        }
    }
    free(present_modes);

    VkSwapchainCreateInfoKHR sc_info = {0};
    sc_info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    sc_info.surface = g_surface;
    sc_info.minImageCount = img_count;
    sc_info.imageFormat = g_swapchain_format;
    sc_info.imageColorSpace = color_space;
    sc_info.imageExtent = extent;
    sc_info.imageArrayLayers = 1;
    sc_info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    sc_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    sc_info.preTransform = surf_caps.currentTransform;
    sc_info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    sc_info.presentMode = present_mode;
    sc_info.clipped = VK_TRUE;

    res = vkCreateSwapchainKHR(g_gpu_ctx.device, &sc_info, NULL, &g_swapchain);
    if (res != VK_SUCCESS) { fprintf(stderr, "gpu: swapchain creation failed\n"); return val_bool(0); }

    // Get swapchain images and create views
    vkGetSwapchainImagesKHR(g_gpu_ctx.device, g_swapchain, &g_swapchain_image_count, NULL);
    g_swapchain_images = calloc(g_swapchain_image_count, sizeof(VkImage));
    g_swapchain_views = calloc(g_swapchain_image_count, sizeof(VkImageView));
    vkGetSwapchainImagesKHR(g_gpu_ctx.device, g_swapchain, &g_swapchain_image_count, g_swapchain_images);

    for (uint32_t i = 0; i < g_swapchain_image_count; i++) {
        VkImageViewCreateInfo view_info = {0};
        view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        view_info.image = g_swapchain_images[i];
        view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
        view_info.format = g_swapchain_format;
        view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        view_info.subresourceRange.levelCount = 1;
        view_info.subresourceRange.layerCount = 1;
        vkCreateImageView(g_gpu_ctx.device, &view_info, NULL, &g_swapchain_views[i]);
    }

    g_gpu_ctx.initialized = 1;
    return val_bool(1);
}

// gpu.swapchain_image_count() -> number
static Value gpu_swapchain_image_count(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_number(g_swapchain_image_count);
}

// gpu.swapchain_format() -> number
static Value gpu_swapchain_format_fn(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_number(SAGE_FORMAT_BGRA8); // Approximation for Sage constants
}

// gpu.swapchain_extent() -> dict {width, height}
static Value gpu_swapchain_extent(int argCount, Value* args) {
    (void)argCount; (void)args;
    Value d = val_dict();
    dict_set(&d, "width", val_number(g_swapchain_width));
    dict_set(&d, "height", val_number(g_swapchain_height));
    return d;
}

// gpu.acquire_next_image(semaphore) -> number (image index, -1 on error)
static Value gpu_acquire_next_image(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || !g_swapchain) return val_number(-1);
    VkSemaphore sem = VK_NULL_HANDLE;
    if (argCount >= 1 && IS_NUMBER(args[0])) {
        int si = (int)AS_NUMBER(args[0]);
        if (si >= 0 && si < g_gpu_ctx.semaphore_count && g_gpu_ctx.semaphores[si].alive)
            sem = g_gpu_ctx.semaphores[si].semaphore;
    }
    uint32_t image_index = 0;
    VkResult res = vkAcquireNextImageKHR(g_gpu_ctx.device, g_swapchain, UINT64_MAX, sem, VK_NULL_HANDLE, &image_index);
    if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR) return val_number(-1);
    return val_number(image_index);
}

// gpu.present(image_index, wait_semaphore?) -> bool
static Value gpu_present(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !g_swapchain) return val_bool(0);
    uint32_t image_index = (uint32_t)AS_NUMBER(args[0]);

    VkSemaphore wait_sem = VK_NULL_HANDLE;
    uint32_t wait_count = 0;
    if (argCount >= 2 && IS_NUMBER(args[1])) {
        int si = (int)AS_NUMBER(args[1]);
        if (si >= 0 && si < g_gpu_ctx.semaphore_count && g_gpu_ctx.semaphores[si].alive) {
            wait_sem = g_gpu_ctx.semaphores[si].semaphore;
            wait_count = 1;
        }
    }

    VkPresentInfoKHR present_info = {0};
    present_info.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present_info.waitSemaphoreCount = wait_count;
    present_info.pWaitSemaphores = &wait_sem;
    present_info.swapchainCount = 1;
    present_info.pSwapchains = &g_swapchain;
    present_info.pImageIndices = &image_index;

    VkResult res = vkQueuePresentKHR(g_gpu_ctx.graphics_queue, &present_info);
    return val_bool(res == VK_SUCCESS || res == VK_SUBOPTIMAL_KHR);
}

// gpu.submit_with_sync(cmd, wait_sem, signal_sem, fence) -> nil
// Full synchronization submit for render loops
static Value gpu_submit_with_sync(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 4) return val_nil();
    int ci = (int)AS_NUMBER(args[0]);
    if (ci < 0 || ci >= g_gpu_ctx.cmd_buffer_count || !g_gpu_ctx.cmd_buffers[ci].alive) return val_nil();

    VkSemaphore wait_sem = VK_NULL_HANDLE;
    VkSemaphore signal_sem = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;

    int wi = (int)AS_NUMBER(args[1]);
    if (wi >= 0 && wi < g_gpu_ctx.semaphore_count && g_gpu_ctx.semaphores[wi].alive)
        wait_sem = g_gpu_ctx.semaphores[wi].semaphore;
    int si = (int)AS_NUMBER(args[2]);
    if (si >= 0 && si < g_gpu_ctx.semaphore_count && g_gpu_ctx.semaphores[si].alive)
        signal_sem = g_gpu_ctx.semaphores[si].semaphore;
    int fi = (int)AS_NUMBER(args[3]);
    if (fi >= 0 && fi < g_gpu_ctx.fence_count && g_gpu_ctx.fences[fi].alive)
        fence = g_gpu_ctx.fences[fi].fence;

    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit = {0};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.waitSemaphoreCount = (wait_sem != VK_NULL_HANDLE) ? 1 : 0;
    submit.pWaitSemaphores = &wait_sem;
    submit.pWaitDstStageMask = &wait_stage;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &g_gpu_ctx.cmd_buffers[ci].cmd;
    submit.signalSemaphoreCount = (signal_sem != VK_NULL_HANDLE) ? 1 : 0;
    submit.pSignalSemaphores = &signal_sem;

    vkQueueSubmit(g_gpu_ctx.graphics_queue, 1, &submit, fence);
    return val_nil();
}

// gpu.create_swapchain_framebuffers(render_pass) -> array of handles
static Value gpu_create_swapchain_framebuffers(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 1 || !g_swapchain) return val_array();
    int rp_idx = (int)AS_NUMBER(args[0]);
    if (rp_idx < 0 || rp_idx >= g_gpu_ctx.render_pass_count || !g_gpu_ctx.render_passes[rp_idx].alive)
        return val_array();

    Value result = val_array();
    for (uint32_t i = 0; i < g_swapchain_image_count; i++) {
        int idx = alloc_framebuffers();
        if (idx < 0) break;

        VkFramebufferCreateInfo fb_info = {0};
        fb_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fb_info.renderPass = g_gpu_ctx.render_passes[rp_idx].render_pass;
        fb_info.attachmentCount = 1;
        fb_info.pAttachments = &g_swapchain_views[i];
        fb_info.width = g_swapchain_width;
        fb_info.height = g_swapchain_height;
        fb_info.layers = 1;

        if (vkCreateFramebuffer(g_gpu_ctx.device, &fb_info, NULL,
                                 &g_gpu_ctx.framebuffers[idx].framebuffer) == VK_SUCCESS) {
            g_gpu_ctx.framebuffers[idx].width = (int)g_swapchain_width;
            g_gpu_ctx.framebuffers[idx].height = (int)g_swapchain_height;
            g_gpu_ctx.framebuffers[idx].alive = 1;
            array_push(&result, val_number(idx));
        }
    }
    return result;
}

// gpu.create_swapchain_framebuffers_depth(render_pass, depth_image) -> array of handles
static Value gpu_create_swapchain_fbs_depth(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2 || !g_swapchain) return val_array();
    int rp_idx = (int)AS_NUMBER(args[0]);
    int depth_idx = (int)AS_NUMBER(args[1]);
    if (rp_idx < 0 || rp_idx >= g_gpu_ctx.render_pass_count || !g_gpu_ctx.render_passes[rp_idx].alive)
        return val_array();
    if (depth_idx < 0 || depth_idx >= g_gpu_ctx.image_count || !g_gpu_ctx.images[depth_idx].alive)
        return val_array();

    Value result = val_array();
    for (uint32_t i = 0; i < g_swapchain_image_count; i++) {
        int idx = alloc_framebuffers();
        if (idx < 0) break;

        VkImageView views[2] = {g_swapchain_views[i], g_gpu_ctx.images[depth_idx].view};
        VkFramebufferCreateInfo fb_info = {0};
        fb_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fb_info.renderPass = g_gpu_ctx.render_passes[rp_idx].render_pass;
        fb_info.attachmentCount = 2;
        fb_info.pAttachments = views;
        fb_info.width = g_swapchain_width;
        fb_info.height = g_swapchain_height;
        fb_info.layers = 1;

        if (vkCreateFramebuffer(g_gpu_ctx.device, &fb_info, NULL,
                                 &g_gpu_ctx.framebuffers[idx].framebuffer) == VK_SUCCESS) {
            g_gpu_ctx.framebuffers[idx].width = (int)g_swapchain_width;
            g_gpu_ctx.framebuffers[idx].height = (int)g_swapchain_height;
            g_gpu_ctx.framebuffers[idx].alive = 1;
            array_push(&result, val_number(idx));
        }
    }
    return result;
}

// ============================================================================
// P1: Input Handling (keyboard + mouse)
// ============================================================================

// gpu.key_pressed(key_code) -> bool
static Value gpu_key_pressed(int argCount, Value* args) {
    if (!g_window || argCount < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    int key = (int)AS_NUMBER(args[0]);
    return val_bool(glfwGetKey(g_window, key) == GLFW_PRESS);
}

// gpu.key_down(key_code) -> bool (alias)
static Value gpu_key_down(int argCount, Value* args) {
    return gpu_key_pressed(argCount, args);
}

// gpu.mouse_pos() -> dict {x, y}
static Value gpu_mouse_pos(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_window) return val_nil();
    double mx, my;
    glfwGetCursorPos(g_window, &mx, &my);
    Value d = val_dict();
    dict_set(&d, "x", val_number(mx));
    dict_set(&d, "y", val_number(my));
    return d;
}

// gpu.mouse_button(button) -> bool
static Value gpu_mouse_button(int argCount, Value* args) {
    if (!g_window || argCount < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    int btn = (int)AS_NUMBER(args[0]);
    return val_bool(glfwGetMouseButton(g_window, btn) == GLFW_PRESS);
}

// gpu.set_cursor_mode(mode) -> nil  (0=normal, 1=hidden, 2=disabled/captured)
static Value gpu_set_cursor_mode(int argCount, Value* args) {
    if (!g_window || argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int mode = (int)AS_NUMBER(args[0]);
    int glfw_mode = GLFW_CURSOR_NORMAL;
    if (mode == 1) glfw_mode = GLFW_CURSOR_HIDDEN;
    if (mode == 2) glfw_mode = GLFW_CURSOR_DISABLED;
    glfwSetInputMode(g_window, GLFW_CURSOR, glfw_mode);
    return val_nil();
}

// gpu.get_time() -> number (GLFW high-resolution timer)
static Value gpu_get_time(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_number(glfwGetTime());
}

// gpu.window_size() -> dict {width, height} (framebuffer size)
static Value gpu_window_size(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_window) return val_nil();
    int w, h;
    glfwGetFramebufferSize(g_window, &w, &h);
    Value d = val_dict();
    dict_set(&d, "width", val_number(w));
    dict_set(&d, "height", val_number(h));
    return d;
}

// gpu.set_title(title) -> nil
static Value gpu_set_title(int argCount, Value* args) {
    if (!g_window || argCount < 1 || !IS_STRING(args[0])) return val_nil();
    glfwSetWindowTitle(g_window, AS_STRING(args[0]));
    return val_nil();
}

// ============================================================================
// P5/P10: Swapchain recreation for resize
// ============================================================================

static int g_framebuffer_resized = 0;

static void framebuffer_resize_cb(GLFWwindow* window, int w, int h) {
    (void)window; (void)w; (void)h;
    g_framebuffer_resized = 1;
}

// gpu.window_resized() -> bool (check and clear flag)
static Value gpu_window_resized(int argCount, Value* args) {
    (void)argCount; (void)args;
    int r = g_framebuffer_resized;
    g_framebuffer_resized = 0;
    return val_bool(r);
}

// ============================================================================
// Feature 1: Swapchain Recreation (window resize)
// ============================================================================

static int recreate_swapchain_internal(void) {
    int w = 0, h = 0;
    glfwGetFramebufferSize(g_window, &w, &h);
    while (w == 0 || h == 0) {
        glfwGetFramebufferSize(g_window, &w, &h);
        glfwWaitEvents();
    }
    vkDeviceWaitIdle(g_gpu_ctx.device);

    // Destroy old views
    for (uint32_t i = 0; i < g_swapchain_image_count; i++) {
        if (g_swapchain_views[i]) vkDestroyImageView(g_gpu_ctx.device, g_swapchain_views[i], NULL);
    }

    // Get new surface caps
    VkSurfaceCapabilitiesKHR surf_caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(g_gpu_ctx.physical_device, g_surface, &surf_caps);
    VkExtent2D extent = surf_caps.currentExtent;
    if (extent.width == UINT32_MAX) { extent.width = (uint32_t)w; extent.height = (uint32_t)h; }

    uint32_t img_count = surf_caps.minImageCount + 1;
    if (surf_caps.maxImageCount > 0 && img_count > surf_caps.maxImageCount) img_count = surf_caps.maxImageCount;

    VkSwapchainKHR old_swapchain = g_swapchain;
    VkSwapchainCreateInfoKHR sc_info = {0};
    sc_info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    sc_info.surface = g_surface;
    sc_info.minImageCount = img_count;
    sc_info.imageFormat = g_swapchain_format;
    sc_info.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    sc_info.imageExtent = extent;
    sc_info.imageArrayLayers = 1;
    sc_info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    sc_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    sc_info.preTransform = surf_caps.currentTransform;
    sc_info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    sc_info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    sc_info.clipped = VK_TRUE;
    sc_info.oldSwapchain = old_swapchain;

    if (vkCreateSwapchainKHR(g_gpu_ctx.device, &sc_info, NULL, &g_swapchain) != VK_SUCCESS) return 0;
    vkDestroySwapchainKHR(g_gpu_ctx.device, old_swapchain, NULL);

    vkGetSwapchainImagesKHR(g_gpu_ctx.device, g_swapchain, &g_swapchain_image_count, NULL);
    free(g_swapchain_images); free(g_swapchain_views);
    g_swapchain_images = calloc(g_swapchain_image_count, sizeof(VkImage));
    g_swapchain_views = calloc(g_swapchain_image_count, sizeof(VkImageView));
    vkGetSwapchainImagesKHR(g_gpu_ctx.device, g_swapchain, &g_swapchain_image_count, g_swapchain_images);

    for (uint32_t i = 0; i < g_swapchain_image_count; i++) {
        VkImageViewCreateInfo vi = {0};
        vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        vi.image = g_swapchain_images[i];
        vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
        vi.format = g_swapchain_format;
        vi.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        vi.subresourceRange.levelCount = 1;
        vi.subresourceRange.layerCount = 1;
        vkCreateImageView(g_gpu_ctx.device, &vi, NULL, &g_swapchain_views[i]);
    }
    g_swapchain_width = extent.width;
    g_swapchain_height = extent.height;
    return 1;
}

// gpu.recreate_swapchain() -> bool
static Value gpu_recreate_swapchain(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized || !g_window) return val_bool(0);
    return val_bool(recreate_swapchain_internal());
}

// ============================================================================
// Feature 2: Scroll wheel input
// ============================================================================

static double g_scroll_x = 0.0, g_scroll_y = 0.0;
static void scroll_callback(GLFWwindow* window, double xoff, double yoff) {
    (void)window;
    g_scroll_x += xoff;
    g_scroll_y += yoff;
}

// gpu.scroll_delta() -> dict {x, y} (consumed on read)
static Value gpu_scroll_delta(int argCount, Value* args) {
    (void)argCount; (void)args;
    Value d = val_dict();
    dict_set(&d, "x", val_number(g_scroll_x));
    dict_set(&d, "y", val_number(g_scroll_y));
    g_scroll_x = 0.0;
    g_scroll_y = 0.0;
    return d;
}

// ============================================================================
// Feature 3: Key state tracking (just pressed / just released)
// ============================================================================

static int g_key_states[512] = {0};
static int g_key_prev[512] = {0};

// gpu.update_input() -> nil  (call once per frame before key queries)
static Value gpu_update_input(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_window) return val_nil();
    for (int i = 32; i < 349; i++) {  // GLFW valid key range
        g_key_prev[i] = g_key_states[i];
        g_key_states[i] = (glfwGetKey(g_window, i) == GLFW_PRESS) ? 1 : 0;
    }
    return val_nil();
}

// gpu.key_just_pressed(key) -> bool (true on frame key first goes down)
static Value gpu_key_just_pressed(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    int k = (int)AS_NUMBER(args[0]);
    if (k < 0 || k >= 512) return val_bool(0);
    return val_bool(g_key_states[k] && !g_key_prev[k]);
}

// gpu.key_just_released(key) -> bool
static Value gpu_key_just_released(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    int k = (int)AS_NUMBER(args[0]);
    if (k < 0 || k >= 512) return val_bool(0);
    return val_bool(!g_key_states[k] && g_key_prev[k]);
}

// ============================================================================
// Feature 7: Cubemap / Skybox
// ============================================================================

// gpu.create_cubemap(size, format, usage) -> handle
static Value gpu_create_cubemap(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 3) return val_number(SAGE_GPU_INVALID_HANDLE);
    int size = (int)AS_NUMBER(args[0]);
    int fmt = (int)AS_NUMBER(args[1]);
    int usage = (int)AS_NUMBER(args[2]);

    int idx = alloc_images();
    if (idx < 0) return val_number(SAGE_GPU_INVALID_HANDLE);

    VkImageCreateInfo img_info = {0};
    img_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    img_info.flags = VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
    img_info.imageType = VK_IMAGE_TYPE_2D;
    img_info.format = sage_gpu_translate_format(fmt);
    img_info.extent = (VkExtent3D){(uint32_t)size, (uint32_t)size, 1};
    img_info.mipLevels = 1;
    img_info.arrayLayers = 6;
    img_info.samples = VK_SAMPLE_COUNT_1_BIT;
    img_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    img_info.usage = translate_image_usage(usage);

    if (vkCreateImage(g_gpu_ctx.device, &img_info, NULL, &g_gpu_ctx.images[idx].image) != VK_SUCCESS)
        return val_number(SAGE_GPU_INVALID_HANDLE);

    VkMemoryRequirements req;
    vkGetImageMemoryRequirements(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, &req);
    VkMemoryAllocateInfo a = {0};
    a.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    a.allocationSize = req.size;
    a.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(g_gpu_ctx.device, &a, NULL, &g_gpu_ctx.images[idx].memory);
    vkBindImageMemory(g_gpu_ctx.device, g_gpu_ctx.images[idx].image, g_gpu_ctx.images[idx].memory, 0);

    VkImageViewCreateInfo vi = {0};
    vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    vi.image = g_gpu_ctx.images[idx].image;
    vi.viewType = VK_IMAGE_VIEW_TYPE_CUBE;
    vi.format = img_info.format;
    vi.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    vi.subresourceRange.levelCount = 1;
    vi.subresourceRange.layerCount = 6;
    vkCreateImageView(g_gpu_ctx.device, &vi, NULL, &g_gpu_ctx.images[idx].view);

    g_gpu_ctx.images[idx].format = fmt;
    g_gpu_ctx.images[idx].img_type = SAGE_IMAGE_CUBE;
    g_gpu_ctx.images[idx].width = size;
    g_gpu_ctx.images[idx].height = size;
    g_gpu_ctx.images[idx].depth = 1;
    g_gpu_ctx.images[idx].array_layers = 6;
    g_gpu_ctx.images[idx].mip_levels = 1;
    g_gpu_ctx.images[idx].alive = 1;
    return val_number(idx);
}

// ============================================================================
// Feature 17: Shader hot-reload
// ============================================================================

// gpu.reload_shader(handle, path) -> bool
static Value gpu_reload_shader(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || argCount < 2) return val_bool(0);
    if (!IS_NUMBER(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    int idx = (int)AS_NUMBER(args[0]);
    if (idx < 0 || idx >= g_gpu_ctx.shader_count || !g_gpu_ctx.shaders[idx].alive) return val_bool(0);

    const char* path = AS_STRING(args[1]);
    FILE* f = fopen(path, "rb");
    if (!f) return val_bool(0);
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint32_t* code = malloc((size_t)sz);
    if (!code) { fclose(f); return val_bool(0); }
    fread(code, 1, (size_t)sz, f);
    fclose(f);

    VkShaderModuleCreateInfo mi = {0};
    mi.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    mi.codeSize = (size_t)sz;
    mi.pCode = code;

    VkShaderModule new_mod;
    VkResult res = vkCreateShaderModule(g_gpu_ctx.device, &mi, NULL, &new_mod);
    free(code);
    if (res != VK_SUCCESS) return val_bool(0);

    // Destroy old, replace
    vkDestroyShaderModule(g_gpu_ctx.device, g_gpu_ctx.shaders[idx].module, NULL);
    g_gpu_ctx.shaders[idx].module = new_mod;
    return val_bool(1);
}

// ============================================================================
// Feature 18: Screenshot capture (readback swapchain to pixel array)
// ============================================================================

// gpu.screenshot() -> dict {width, height, pixels} (RGBA8 byte array)
static Value gpu_screenshot(int argCount, Value* args) {
    (void)argCount; (void)args;
    if (!g_gpu_ctx.initialized || !g_swapchain) return val_nil();

    uint32_t w = g_swapchain_width, h = g_swapchain_height;
    VkDeviceSize size = (VkDeviceSize)w * h * 4;

    // Create staging buffer for readback
    VkBuffer staging; VkDeviceMemory staging_mem;
    VkBufferCreateInfo bi = {0};
    bi.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bi.size = size;
    bi.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    vkCreateBuffer(g_gpu_ctx.device, &bi, NULL, &staging);

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(g_gpu_ctx.device, staging, &req);
    VkMemoryAllocateInfo ai = {0};
    ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(g_gpu_ctx.device, &ai, NULL, &staging_mem);
    vkBindBufferMemory(g_gpu_ctx.device, staging, staging_mem, 0);

    // Copy current swapchain image 0 to staging
    VkCommandBuffer cmd = sage_gpu_begin_one_shot_v2();
    if (cmd && g_swapchain_images) {
        VkImage src = g_swapchain_images[0];

        // Transition to TRANSFER_SRC
        VkImageMemoryBarrier barrier = {0};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.image = src;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        VkBufferImageCopy region = {0};
        region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent = (VkExtent3D){w, h, 1};
        vkCmdCopyImageToBuffer(cmd, src, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, staging, 1, &region);

        // Transition back
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        sage_gpu_end_one_shot(cmd);
    }

    // Read pixels
    void* mapped;
    vkMapMemory(g_gpu_ctx.device, staging_mem, 0, size, 0, &mapped);
    Value pixels = val_array();
    unsigned char* src = (unsigned char*)mapped;
    // Only return first 64K pixels max to avoid huge arrays
    int pixel_count = (int)(w * h);
    if (pixel_count > 65536) pixel_count = 65536;
    for (int i = 0; i < pixel_count * 4; i++) {
        array_push(&pixels, val_number(src[i]));
    }
    vkUnmapMemory(g_gpu_ctx.device, staging_mem);
    vkDestroyBuffer(g_gpu_ctx.device, staging, NULL);
    vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);

    Value result = val_dict();
    dict_set(&result, "width", val_number(w));
    dict_set(&result, "height", val_number(h));
    dict_set(&result, "pixels", pixels);
    return result;
}

// ============================================================================
// Feature 14: Save screenshot to PNG
// ============================================================================

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

// gpu.save_screenshot(path) -> bool
static Value gpu_save_screenshot(int argCount, Value* args) {
    if (!g_gpu_ctx.initialized || !g_swapchain || argCount < 1 || !IS_STRING(args[0]))
        return val_bool(0);

    const char* path = AS_STRING(args[0]);
    uint32_t w = g_swapchain_width, h = g_swapchain_height;
    VkDeviceSize size = (VkDeviceSize)w * h * 4;

    VkBuffer staging; VkDeviceMemory staging_mem;
    VkBufferCreateInfo bi = {0};
    bi.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bi.size = size;
    bi.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    vkCreateBuffer(g_gpu_ctx.device, &bi, NULL, &staging);

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(g_gpu_ctx.device, staging, &req);
    VkMemoryAllocateInfo ai = {0};
    ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = sage_gpu_find_memory_type(req.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(g_gpu_ctx.device, &ai, NULL, &staging_mem);
    vkBindBufferMemory(g_gpu_ctx.device, staging, staging_mem, 0);

    VkCommandBuffer cmd = sage_gpu_begin_one_shot_v2();
    if (cmd && g_swapchain_images) {
        VkImage src_img = g_swapchain_images[0];
        VkImageMemoryBarrier barrier = {0};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = src_img;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        VkBufferImageCopy region = {0};
        region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent = (VkExtent3D){w, h, 1};
        vkCmdCopyImageToBuffer(cmd, src_img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, staging, 1, &region);

        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);
        sage_gpu_end_one_shot(cmd);
    }

    void* mapped;
    vkMapMemory(g_gpu_ctx.device, staging_mem, 0, size, 0, &mapped);

    // Swapchain is BGRA, PNG expects RGBA — swap R and B
    unsigned char* pixels = (unsigned char*)mapped;
    for (uint32_t i = 0; i < w * h; i++) {
        unsigned char tmp = pixels[i * 4 + 0];
        pixels[i * 4 + 0] = pixels[i * 4 + 2];
        pixels[i * 4 + 2] = tmp;
        pixels[i * 4 + 3] = 255; // force opaque
    }

    int ok = stbi_write_png(path, (int)w, (int)h, 4, pixels, (int)(w * 4));
    vkUnmapMemory(g_gpu_ctx.device, staging_mem);
    vkDestroyBuffer(g_gpu_ctx.device, staging, NULL);
    vkFreeMemory(g_gpu_ctx.device, staging_mem, NULL);

    if (ok) fprintf(stderr, "Screenshot saved: %s (%dx%d)\n", path, w, h);
    return val_bool(ok != 0);
}

// gpu.shutdown_windowed() -> nil  (cleanup window + vulkan)
static Value gpu_shutdown_windowed(int argCount, Value* args) {
    // First do normal gpu shutdown
    gpu_shutdown(argCount, args);

    // Destroy swapchain resources
    if (g_swapchain_views) {
        // Already freed by gpu_shutdown's device destruction
        free(g_swapchain_views);
        g_swapchain_views = NULL;
    }
    if (g_swapchain_images) {
        free(g_swapchain_images);
        g_swapchain_images = NULL;
    }
    g_swapchain = VK_NULL_HANDLE;
    g_surface = VK_NULL_HANDLE;
    g_swapchain_image_count = 0;

    if (g_window) {
        glfwDestroyWindow(g_window);
        g_window = NULL;
    }
    glfwTerminate();
    return val_nil();
}

#endif // SAGE_HAS_GLFW

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

    // --- Depth buffer ---
    env_define(e, "create_depth_buffer", 19, val_native(gpu_create_depth_buffer));

    // --- Staging upload ---
    env_define(e, "upload_device_local", 19, val_native(gpu_upload_device_local));
    env_define(e, "upload_bytes", 12, val_native(gpu_upload_bytes));

    // --- Texture loading ---
    env_define(e, "load_texture", 12, val_native(gpu_load_texture));
    env_define(e, "texture_dims", 12, val_native(gpu_texture_dims));

    // --- P2: Uniform buffers ---
    env_define(e, "create_uniform_buffer", 21, val_native(gpu_create_uniform_buffer));
    env_define(e, "update_uniform", 14, val_native(gpu_update_uniform));

    // --- P3: Offscreen rendering ---
    env_define(e, "create_offscreen_target", 23, val_native(gpu_create_offscreen_target));

    // --- P6: Mipmaps + anisotropic ---
    env_define(e, "generate_mipmaps", 16, val_native(gpu_generate_mipmaps));
    env_define(e, "create_sampler_advanced", 23, val_native(gpu_create_sampler_advanced));

    // --- P8: Indirect draw/dispatch ---
    env_define(e, "cmd_draw_indirect", 17, val_native(gpu_cmd_draw_indirect));
    env_define(e, "cmd_draw_indexed_indirect", 25, val_native(gpu_cmd_draw_indexed_indirect));
    env_define(e, "cmd_dispatch_indirect", 21, val_native(gpu_cmd_dispatch_indirect));

    // --- P9: 3D textures ---
    env_define(e, "create_image_3d", 15, val_native(gpu_create_image_3d));

    // --- P10: Multi-buffer vertex binding ---
    env_define(e, "cmd_bind_vertex_buffers", 23, val_native(gpu_cmd_bind_vertex_buffers));

    // --- P11: MRT render pass ---
    env_define(e, "create_render_pass_mrt", 22, val_native(gpu_create_render_pass_mrt));

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

#ifdef SAGE_HAS_GLFW
    // --- Window & Swapchain ---
    env_define(e, "create_window", 13, val_native(gpu_create_window));
    env_define(e, "destroy_window", 14, val_native(gpu_destroy_window));
    env_define(e, "window_should_close", 19, val_native(gpu_window_should_close));
    env_define(e, "poll_events", 11, val_native(gpu_poll_events));
    env_define(e, "init_windowed", 13, val_native(gpu_init_windowed));
    env_define(e, "shutdown_windowed", 17, val_native(gpu_shutdown_windowed));
    env_define(e, "swapchain_image_count", 21, val_native(gpu_swapchain_image_count));
    env_define(e, "swapchain_format", 16, val_native(gpu_swapchain_format_fn));
    env_define(e, "swapchain_extent", 16, val_native(gpu_swapchain_extent));
    env_define(e, "acquire_next_image", 18, val_native(gpu_acquire_next_image));
    env_define(e, "present", 7, val_native(gpu_present));
    env_define(e, "submit_with_sync", 16, val_native(gpu_submit_with_sync));
    env_define(e, "create_swapchain_framebuffers", 29, val_native(gpu_create_swapchain_framebuffers));
    env_define(e, "create_swapchain_framebuffers_depth", 35, val_native(gpu_create_swapchain_fbs_depth));

    // --- P1: Input handling ---
    env_define(e, "key_pressed", 11, val_native(gpu_key_pressed));
    env_define(e, "key_down", 8, val_native(gpu_key_down));
    env_define(e, "mouse_pos", 9, val_native(gpu_mouse_pos));
    env_define(e, "mouse_button", 12, val_native(gpu_mouse_button));
    env_define(e, "set_cursor_mode", 15, val_native(gpu_set_cursor_mode));
    env_define(e, "get_time", 8, val_native(gpu_get_time));
    env_define(e, "window_size", 11, val_native(gpu_window_size));
    env_define(e, "set_title", 9, val_native(gpu_set_title));
    env_define(e, "window_resized", 14, val_native(gpu_window_resized));

    // Platform selection
    env_define(e, "set_platform", 12, val_native(gpu_set_platform));
    env_define(e, "get_platform", 12, val_native(gpu_get_platform));
    env_define(e, "detected_platform", 17, val_native(gpu_detected_platform));
    env_define(e, "PLATFORM_AUTO", 13, val_number(SAGE_PLATFORM_AUTO));
    env_define(e, "PLATFORM_X11", 12, val_number(SAGE_PLATFORM_X11));
    env_define(e, "PLATFORM_WAYLAND", 16, val_number(SAGE_PLATFORM_WAYLAND));
    env_define(e, "PLATFORM_ANY", 12, val_number(SAGE_PLATFORM_ANY));

    // Feature 1: Swapchain recreation
    env_define(e, "recreate_swapchain", 18, val_native(gpu_recreate_swapchain));

    // Feature 2: Scroll wheel
    env_define(e, "scroll_delta", 12, val_native(gpu_scroll_delta));

    // Feature 3: Key state tracking
    env_define(e, "update_input", 12, val_native(gpu_update_input));
    env_define(e, "key_just_pressed", 16, val_native(gpu_key_just_pressed));
    env_define(e, "key_just_released", 17, val_native(gpu_key_just_released));

    // Feature 7: Cubemap
    env_define(e, "create_cubemap", 14, val_native(gpu_create_cubemap));

    // Feature 17: Shader hot-reload
    env_define(e, "reload_shader", 13, val_native(gpu_reload_shader));

    // Feature 18: Screenshot
    env_define(e, "screenshot", 10, val_native(gpu_screenshot));
    env_define(e, "save_screenshot", 15, val_native(gpu_save_screenshot));

    // Key constants (GLFW key codes)
    env_define(e, "KEY_W", 5, val_number(GLFW_KEY_W));
    env_define(e, "KEY_A", 5, val_number(GLFW_KEY_A));
    env_define(e, "KEY_S", 5, val_number(GLFW_KEY_S));
    env_define(e, "KEY_D", 5, val_number(GLFW_KEY_D));
    env_define(e, "KEY_Q", 5, val_number(GLFW_KEY_Q));
    env_define(e, "KEY_E", 5, val_number(GLFW_KEY_E));
    env_define(e, "KEY_R", 5, val_number(GLFW_KEY_R));
    env_define(e, "KEY_F", 5, val_number(GLFW_KEY_F));
    env_define(e, "KEY_SPACE", 9, val_number(GLFW_KEY_SPACE));
    env_define(e, "KEY_ESCAPE", 10, val_number(GLFW_KEY_ESCAPE));
    env_define(e, "KEY_ENTER", 9, val_number(GLFW_KEY_ENTER));
    env_define(e, "KEY_TAB", 7, val_number(GLFW_KEY_TAB));
    env_define(e, "KEY_SHIFT", 9, val_number(GLFW_KEY_LEFT_SHIFT));
    env_define(e, "KEY_CTRL", 8, val_number(GLFW_KEY_LEFT_CONTROL));
    env_define(e, "KEY_UP", 6, val_number(GLFW_KEY_UP));
    env_define(e, "KEY_DOWN", 8, val_number(GLFW_KEY_DOWN));
    env_define(e, "KEY_LEFT", 8, val_number(GLFW_KEY_LEFT));
    env_define(e, "KEY_RIGHT", 9, val_number(GLFW_KEY_RIGHT));
    env_define(e, "KEY_1", 5, val_number(GLFW_KEY_1));
    env_define(e, "KEY_2", 5, val_number(GLFW_KEY_2));
    env_define(e, "KEY_3", 5, val_number(GLFW_KEY_3));
    env_define(e, "KEY_4", 5, val_number(GLFW_KEY_4));
    env_define(e, "KEY_5", 5, val_number(GLFW_KEY_5));
    env_define(e, "MOUSE_LEFT", 10, val_number(GLFW_MOUSE_BUTTON_LEFT));
    env_define(e, "MOUSE_RIGHT", 11, val_number(GLFW_MOUSE_BUTTON_RIGHT));
    env_define(e, "MOUSE_MIDDLE", 12, val_number(GLFW_MOUSE_BUTTON_MIDDLE));
    env_define(e, "CURSOR_NORMAL", 13, val_number(0));
    env_define(e, "CURSOR_HIDDEN", 13, val_number(1));
    env_define(e, "CURSOR_DISABLED", 15, val_number(2));

    env_define(e, "has_window", 10, val_bool(1));
#else
    env_define(e, "has_window", 10, val_bool(0));
#endif

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
    env_define(e, "FORMAT_SWAPCHAIN",  16, val_number(SAGE_FORMAT_SWAPCHAIN));
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
    env_define(e, "PIPE_VERTEX_SHADER",18, val_number(SAGE_PIPE_VERTEX_SHADER));
    env_define(e, "PIPE_VERTEX_INPUT", 17, val_number(SAGE_PIPE_VERTEX_INPUT));
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
