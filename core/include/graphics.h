// include/graphics.h - SageLang Vulkan Graphics Module
// Phase 15: Professional GPU compute & graphics library
//
// Architecture:
//   Handle-table design — all Vulkan objects stored internally,
//   exposed to Sage via integer handles. Safe, leak-trackable.
//
// Layers:
//   C native module (this) -> lib/vulkan.sage (builders) -> lib/gpu.sage (high-level)

#ifndef SAGE_GRAPHICS_H
#define SAGE_GRAPHICS_H

#include "module.h"
#include "value.h"

#ifdef SAGE_HAS_VULKAN
#include <vulkan/vulkan.h>
#endif

// ============================================================================
// Handle System
// ============================================================================
// All GPU resources are tracked via integer handles.
// Invalid handle sentinel:
#define SAGE_GPU_INVALID_HANDLE (-1)

// Handle table growth factor
#define SAGE_GPU_INITIAL_CAPACITY 64

// Maximum push constant size (Vulkan spec minimum guarantee)
#define SAGE_GPU_MAX_PUSH_CONSTANT_SIZE 128

// Maximum descriptor bindings per layout
#define SAGE_GPU_MAX_BINDINGS 32

// Maximum vertex attributes
#define SAGE_GPU_MAX_VERTEX_ATTRIBS 16

// Maximum color attachments
#define SAGE_GPU_MAX_COLOR_ATTACHMENTS 8

// ============================================================================
// Resource Types (exposed as constants to Sage)
// ============================================================================

// Buffer usage flags
#define SAGE_BUFFER_STORAGE    0x01
#define SAGE_BUFFER_UNIFORM    0x02
#define SAGE_BUFFER_VERTEX     0x04
#define SAGE_BUFFER_INDEX      0x08
#define SAGE_BUFFER_STAGING    0x10
#define SAGE_BUFFER_INDIRECT   0x20
#define SAGE_BUFFER_TRANSFER_SRC 0x40
#define SAGE_BUFFER_TRANSFER_DST 0x80

// Memory property flags
#define SAGE_MEMORY_DEVICE_LOCAL  0x01
#define SAGE_MEMORY_HOST_VISIBLE  0x02
#define SAGE_MEMORY_HOST_COHERENT 0x04

// Image formats
#define SAGE_FORMAT_RGBA8       0
#define SAGE_FORMAT_RGBA16F     1
#define SAGE_FORMAT_RGBA32F     2
#define SAGE_FORMAT_R32F        3
#define SAGE_FORMAT_RG32F       4
#define SAGE_FORMAT_DEPTH32F    5
#define SAGE_FORMAT_DEPTH24_S8  6
#define SAGE_FORMAT_R8          7
#define SAGE_FORMAT_RG8         8
#define SAGE_FORMAT_BGRA8       9
#define SAGE_FORMAT_R32U        10
#define SAGE_FORMAT_RG16F       11
#define SAGE_FORMAT_R16F        12
#define SAGE_FORMAT_SWAPCHAIN   99   // Resolves to actual swapchain format at runtime

// Image usage flags
#define SAGE_IMAGE_SAMPLED      0x01
#define SAGE_IMAGE_STORAGE      0x02
#define SAGE_IMAGE_COLOR_ATTACH 0x04
#define SAGE_IMAGE_DEPTH_ATTACH 0x08
#define SAGE_IMAGE_TRANSFER_SRC 0x10
#define SAGE_IMAGE_TRANSFER_DST 0x20
#define SAGE_IMAGE_INPUT_ATTACH 0x40

// Image types
#define SAGE_IMAGE_1D  0
#define SAGE_IMAGE_2D  1
#define SAGE_IMAGE_3D  2
#define SAGE_IMAGE_CUBE 3

// Filter modes
#define SAGE_FILTER_NEAREST 0
#define SAGE_FILTER_LINEAR  1

// Address modes
#define SAGE_ADDRESS_REPEAT          0
#define SAGE_ADDRESS_MIRRORED_REPEAT 1
#define SAGE_ADDRESS_CLAMP_EDGE      2
#define SAGE_ADDRESS_CLAMP_BORDER    3

// Descriptor types
#define SAGE_DESC_STORAGE_BUFFER    0
#define SAGE_DESC_UNIFORM_BUFFER    1
#define SAGE_DESC_SAMPLED_IMAGE     2
#define SAGE_DESC_STORAGE_IMAGE     3
#define SAGE_DESC_SAMPLER            4
#define SAGE_DESC_COMBINED_SAMPLER   5
#define SAGE_DESC_INPUT_ATTACHMENT   6

// Shader stages
#define SAGE_STAGE_VERTEX   0x01
#define SAGE_STAGE_FRAGMENT 0x02
#define SAGE_STAGE_COMPUTE  0x04
#define SAGE_STAGE_GEOMETRY 0x08
#define SAGE_STAGE_TESS_CTRL  0x10
#define SAGE_STAGE_TESS_EVAL  0x20
#define SAGE_STAGE_ALL_GRAPHICS 0x1F
#define SAGE_STAGE_ALL      0x3F

// Topology
#define SAGE_TOPO_POINT_LIST     0
#define SAGE_TOPO_LINE_LIST      1
#define SAGE_TOPO_LINE_STRIP     2
#define SAGE_TOPO_TRIANGLE_LIST  3
#define SAGE_TOPO_TRIANGLE_STRIP 4
#define SAGE_TOPO_TRIANGLE_FAN   5

// Polygon mode
#define SAGE_POLY_FILL  0
#define SAGE_POLY_LINE  1
#define SAGE_POLY_POINT 2

// Cull mode
#define SAGE_CULL_NONE  0
#define SAGE_CULL_FRONT 1
#define SAGE_CULL_BACK  2
#define SAGE_CULL_BOTH  3

// Front face
#define SAGE_FRONT_CCW 0
#define SAGE_FRONT_CW  1

// Blend factors
#define SAGE_BLEND_ZERO              0
#define SAGE_BLEND_ONE               1
#define SAGE_BLEND_SRC_ALPHA         2
#define SAGE_BLEND_ONE_MINUS_SRC_ALPHA 3
#define SAGE_BLEND_DST_ALPHA         4
#define SAGE_BLEND_ONE_MINUS_DST_ALPHA 5
#define SAGE_BLEND_SRC_COLOR         6
#define SAGE_BLEND_DST_COLOR         7

// Blend ops
#define SAGE_BLEND_OP_ADD      0
#define SAGE_BLEND_OP_SUBTRACT 1
#define SAGE_BLEND_OP_MIN      2
#define SAGE_BLEND_OP_MAX      3

// Compare ops (depth/stencil)
#define SAGE_COMPARE_NEVER    0
#define SAGE_COMPARE_LESS     1
#define SAGE_COMPARE_EQUAL    2
#define SAGE_COMPARE_LEQUAL   3
#define SAGE_COMPARE_GREATER  4
#define SAGE_COMPARE_NEQUAL   5
#define SAGE_COMPARE_GEQUAL   6
#define SAGE_COMPARE_ALWAYS   7

// Load/store ops
#define SAGE_LOAD_CLEAR    0
#define SAGE_LOAD_LOAD     1
#define SAGE_LOAD_DONTCARE 2
#define SAGE_STORE_STORE    0
#define SAGE_STORE_DONTCARE 1

// Image layouts
#define SAGE_LAYOUT_UNDEFINED      0
#define SAGE_LAYOUT_GENERAL        1
#define SAGE_LAYOUT_COLOR_ATTACH   2
#define SAGE_LAYOUT_DEPTH_ATTACH   3
#define SAGE_LAYOUT_SHADER_READ    4
#define SAGE_LAYOUT_TRANSFER_SRC   5
#define SAGE_LAYOUT_TRANSFER_DST   6
#define SAGE_LAYOUT_PRESENT        7

// Pipeline stage flags (for barriers)
#define SAGE_PIPE_TOP            0x0001
#define SAGE_PIPE_DRAW_INDIRECT  0x0002
#define SAGE_PIPE_VERTEX_INPUT   0x0004
#define SAGE_PIPE_VERTEX_SHADER  0x0008
#define SAGE_PIPE_FRAGMENT       0x0010
#define SAGE_PIPE_EARLY_DEPTH    0x0020
#define SAGE_PIPE_LATE_DEPTH     0x0040
#define SAGE_PIPE_COLOR_OUTPUT   0x0080
#define SAGE_PIPE_COMPUTE        0x0100
#define SAGE_PIPE_TRANSFER       0x0200
#define SAGE_PIPE_BOTTOM         0x0400
#define SAGE_PIPE_HOST           0x0800
#define SAGE_PIPE_ALL_GRAPHICS   0x1000
#define SAGE_PIPE_ALL_COMMANDS   0x2000

// Access flags (for barriers)
#define SAGE_ACCESS_NONE             0x0000
#define SAGE_ACCESS_SHADER_READ      0x0001
#define SAGE_ACCESS_SHADER_WRITE     0x0002
#define SAGE_ACCESS_COLOR_READ       0x0004
#define SAGE_ACCESS_COLOR_WRITE      0x0008
#define SAGE_ACCESS_DEPTH_READ       0x0010
#define SAGE_ACCESS_DEPTH_WRITE      0x0020
#define SAGE_ACCESS_TRANSFER_READ    0x0040
#define SAGE_ACCESS_TRANSFER_WRITE   0x0080
#define SAGE_ACCESS_HOST_READ        0x0100
#define SAGE_ACCESS_HOST_WRITE       0x0200
#define SAGE_ACCESS_MEMORY_READ      0x0400
#define SAGE_ACCESS_MEMORY_WRITE     0x0800
#define SAGE_ACCESS_INDIRECT_READ    0x1000
#define SAGE_ACCESS_INDEX_READ       0x2000
#define SAGE_ACCESS_VERTEX_READ      0x4000
#define SAGE_ACCESS_UNIFORM_READ     0x8000

// Vertex input rate
#define SAGE_INPUT_RATE_VERTEX   0
#define SAGE_INPUT_RATE_INSTANCE 1

// Vertex attribute formats
#define SAGE_ATTR_FLOAT   0
#define SAGE_ATTR_VEC2    1
#define SAGE_ATTR_VEC3    2
#define SAGE_ATTR_VEC4    3
#define SAGE_ATTR_INT     4
#define SAGE_ATTR_IVEC2   5
#define SAGE_ATTR_IVEC3   6
#define SAGE_ATTR_IVEC4   7
#define SAGE_ATTR_UINT    8

// ============================================================================
// Internal Handle-Table Types (opaque to Sage)
// ============================================================================

#ifdef SAGE_HAS_VULKAN

typedef struct {
    VkBuffer       buffer;
    VkDeviceMemory memory;
    VkDeviceSize   size;
    int            usage;
    int            mem_props;
    void*          mapped;  // Non-NULL if persistently mapped
    int            alive;
} SageGPUBuffer;

typedef struct {
    VkImage        image;
    VkDeviceMemory memory;
    VkImageView    view;
    int            format;
    int            img_type;  // 1D/2D/3D/Cube
    int            width;
    int            height;
    int            depth;
    int            mip_levels;
    int            array_layers;
    int            usage;
    int            alive;
} SageGPUImage;

typedef struct {
    VkSampler sampler;
    int       alive;
} SageGPUSampler;

typedef struct {
    VkShaderModule module;
    int            stage;  // SAGE_STAGE_*
    int            alive;
} SageGPUShader;

typedef struct {
    VkDescriptorSetLayout layout;
    int                   binding_count;
    int                   alive;
} SageGPUDescriptorLayout;

typedef struct {
    VkDescriptorPool pool;
    int              alive;
} SageGPUDescriptorPool;

typedef struct {
    VkDescriptorSet set;
    int             alive;
} SageGPUDescriptorSet;

typedef struct {
    VkPipelineLayout layout;
    int              alive;
} SageGPUPipelineLayout;

typedef struct {
    VkPipeline pipeline;
    int        is_compute;
    int        alive;
} SageGPUPipeline;

typedef struct {
    VkRenderPass render_pass;
    int          alive;
} SageGPURenderPass;

typedef struct {
    VkFramebuffer framebuffer;
    int           width;
    int           height;
    int           alive;
} SageGPUFramebuffer;

typedef struct {
    VkCommandPool pool;
    int           alive;
} SageGPUCommandPool;

typedef struct {
    VkCommandBuffer cmd;
    int             recording;
    int             alive;
} SageGPUCommandBuffer;

typedef struct {
    VkFence   fence;
    int       alive;
} SageGPUFence;

typedef struct {
    VkSemaphore semaphore;
    int         alive;
} SageGPUSemaphore;

// Master GPU context — one per application
typedef struct {
    VkInstance       instance;
    VkPhysicalDevice physical_device;
    VkDevice         device;
    VkQueue          graphics_queue;
    VkQueue          compute_queue;
    VkQueue          transfer_queue;
    uint32_t         graphics_family;
    uint32_t         compute_family;
    uint32_t         transfer_family;
    VkPhysicalDeviceProperties       device_props;
    VkPhysicalDeviceMemoryProperties mem_props;
    int              validation_enabled;
    VkDebugUtilsMessengerEXT debug_messenger;

    // Handle tables (dynamic arrays)
    SageGPUBuffer*           buffers;
    int                      buffer_count;
    int                      buffer_cap;

    SageGPUImage*            images;
    int                      image_count;
    int                      image_cap;

    SageGPUSampler*          samplers;
    int                      sampler_count;
    int                      sampler_cap;

    SageGPUShader*           shaders;
    int                      shader_count;
    int                      shader_cap;

    SageGPUDescriptorLayout* desc_layouts;
    int                      desc_layout_count;
    int                      desc_layout_cap;

    SageGPUDescriptorPool*   desc_pools;
    int                      desc_pool_count;
    int                      desc_pool_cap;

    SageGPUDescriptorSet*    desc_sets;
    int                      desc_set_count;
    int                      desc_set_cap;

    SageGPUPipelineLayout*   pipe_layouts;
    int                      pipe_layout_count;
    int                      pipe_layout_cap;

    SageGPUPipeline*         pipelines;
    int                      pipeline_count;
    int                      pipeline_cap;

    SageGPURenderPass*       render_passes;
    int                      render_pass_count;
    int                      render_pass_cap;

    SageGPUFramebuffer*      framebuffers;
    int                      framebuffer_count;
    int                      framebuffer_cap;

    SageGPUCommandPool*      cmd_pools;
    int                      cmd_pool_count;
    int                      cmd_pool_cap;

    SageGPUCommandBuffer*    cmd_buffers;
    int                      cmd_buffer_count;
    int                      cmd_buffer_cap;

    SageGPUFence*            fences;
    int                      fence_count;
    int                      fence_cap;

    SageGPUSemaphore*        semaphores;
    int                      semaphore_count;
    int                      semaphore_cap;

    int initialized;
} SageGPUContext;

// Global context
extern SageGPUContext g_gpu_ctx;

// Internal helpers
uint32_t sage_gpu_find_memory_type(uint32_t type_filter, VkMemoryPropertyFlags properties);
VkFormat sage_gpu_translate_format(int sage_format);
int      sage_gpu_format_size(int sage_format);
VkShaderStageFlagBits sage_gpu_translate_stage(int sage_stage);
VkDescriptorType sage_gpu_translate_desc_type(int sage_desc_type);

#endif // SAGE_HAS_VULKAN

// ============================================================================
// Public API (registered as native module functions)
// ============================================================================

// --- Context lifecycle ---
Module* create_graphics_module(ModuleCache* cache);

// These are exposed as NativeFn to Sage:
// gpu.init(app_name, validation?) -> bool
// gpu.shutdown() -> nil
// gpu.device_name() -> string
// gpu.device_limits() -> dict

// --- Buffers ---
// gpu.create_buffer(size, usage, memory) -> handle
// gpu.destroy_buffer(handle) -> nil
// gpu.buffer_upload(handle, data_array) -> bool
// gpu.buffer_download(handle) -> array
// gpu.buffer_copy(src, dst, size) -> bool
// gpu.buffer_size(handle) -> number

// --- Images ---
// gpu.create_image(width, height, depth, format, usage) -> handle
// gpu.create_image_view(image_handle) -> handle  (auto from create_image)
// gpu.destroy_image(handle) -> nil
// gpu.image_dims(handle) -> dict {width, height, depth}

// --- Samplers ---
// gpu.create_sampler(mag_filter, min_filter, address_mode) -> handle
// gpu.destroy_sampler(handle) -> nil

// --- Shaders ---
// gpu.load_shader(path, stage) -> handle
// gpu.load_shader_bytes(byte_array, stage) -> handle
// gpu.destroy_shader(handle) -> nil

// --- Descriptor sets ---
// gpu.create_descriptor_layout(bindings_array) -> handle
//   binding: {binding, type, stage, count?}
// gpu.create_descriptor_pool(max_sets, pool_sizes) -> handle
// gpu.allocate_descriptor_set(pool_handle, layout_handle) -> handle
// gpu.update_descriptor(set_handle, binding, type, resource_handle) -> nil
// gpu.update_descriptor_image(set_handle, binding, image_handle, sampler_handle) -> nil

// --- Pipeline layouts ---
// gpu.create_pipeline_layout(desc_layouts_array, push_constant_size?, push_stages?) -> handle

// --- Compute pipelines ---
// gpu.create_compute_pipeline(layout_handle, shader_handle) -> handle
// gpu.destroy_pipeline(handle) -> nil

// --- Graphics pipelines ---
// gpu.create_graphics_pipeline(config_dict) -> handle
//   config: {layout, render_pass, vertex_shader, fragment_shader,
//            vertex_bindings?, vertex_attribs?, topology?, polygon_mode?,
//            cull_mode?, front_face?, depth_test?, depth_write?, blend?,
//            blend_src?, blend_dst?, subpass?}

// --- Render passes ---
// gpu.create_render_pass(attachments_array, subpass_config?) -> handle
//   attachment: {format, load_op, store_op, initial_layout, final_layout}
// gpu.destroy_render_pass(handle) -> nil

// --- Framebuffers ---
// gpu.create_framebuffer(render_pass, image_handles_array, width, height) -> handle
// gpu.destroy_framebuffer(handle) -> nil

// --- Command recording ---
// gpu.create_command_pool() -> handle
// gpu.create_command_buffer(pool_handle) -> handle
// gpu.begin_commands(cmd_handle) -> nil
// gpu.end_commands(cmd_handle) -> nil
// gpu.cmd_bind_compute_pipeline(cmd, pipeline) -> nil
// gpu.cmd_bind_graphics_pipeline(cmd, pipeline) -> nil
// gpu.cmd_bind_descriptor_set(cmd, pipe_layout, set_index, desc_set) -> nil
// gpu.cmd_dispatch(cmd, x, y, z) -> nil
// gpu.cmd_push_constants(cmd, pipe_layout, stage, data_array) -> nil
// gpu.cmd_begin_render_pass(cmd, render_pass, framebuffer, clear_values) -> nil
// gpu.cmd_end_render_pass(cmd) -> nil
// gpu.cmd_draw(cmd, vertex_count, instance_count, first_vertex, first_instance) -> nil
// gpu.cmd_draw_indexed(cmd, index_count, instance_count, first_index, vertex_offset, first_instance) -> nil
// gpu.cmd_bind_vertex_buffer(cmd, buffer_handle) -> nil
// gpu.cmd_bind_index_buffer(cmd, buffer_handle) -> nil
// gpu.cmd_set_viewport(cmd, x, y, w, h, min_depth, max_depth) -> nil
// gpu.cmd_set_scissor(cmd, x, y, w, h) -> nil
// gpu.cmd_copy_buffer(cmd, src, dst, size) -> nil
// gpu.cmd_copy_buffer_to_image(cmd, buffer, image, width, height) -> nil
// gpu.cmd_pipeline_barrier(cmd, src_stage, dst_stage, src_access, dst_access) -> nil
// gpu.cmd_image_barrier(cmd, image, old_layout, new_layout, src_stage, dst_stage, src_access, dst_access) -> nil

// --- Synchronization ---
// gpu.create_fence(signaled?) -> handle
// gpu.create_semaphore() -> handle
// gpu.wait_fence(fence, timeout_ns?) -> bool
// gpu.reset_fence(fence) -> nil
// gpu.destroy_fence(fence) -> nil
// gpu.destroy_semaphore(sem) -> nil

// --- Submission ---
// gpu.submit(cmd, wait_sems?, signal_sems?, fence?) -> nil
// gpu.submit_compute(cmd, wait_sems?, signal_sems?, fence?) -> nil
// gpu.queue_wait_idle() -> nil
// gpu.device_wait_idle() -> nil

// --- Query ---
// gpu.has_vulkan() -> bool   (always works, even without Vulkan)

#endif // SAGE_GRAPHICS_H
