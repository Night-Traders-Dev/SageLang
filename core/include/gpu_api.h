// include/gpu_api.h — Pure C GPU API for SageLang
//
// Backend-agnostic GPU API using simple C types (no Value dependency).
// Used by both the interpreter (graphics.c) and LLVM compiled path (llvm_runtime.c).
// Supports Vulkan and OpenGL backends via compile-time flags.
//
// All GPU resources are tracked via integer handles.
// Invalid handle sentinel: -1

#ifndef SAGE_GPU_API_H
#define SAGE_GPU_API_H

#include <stddef.h>
#include <stdint.h>

// ============================================================================
// Backend Selection
// ============================================================================

#define SAGE_GPU_BACKEND_NONE    0
#define SAGE_GPU_BACKEND_VULKAN  1
#define SAGE_GPU_BACKEND_OPENGL  2

// ============================================================================
// Constants (re-exported from graphics.h for standalone use)
// ============================================================================

#define SGPU_INVALID_HANDLE (-1)

// Buffer usage
#define SGPU_BUFFER_STORAGE      0x01
#define SGPU_BUFFER_UNIFORM      0x02
#define SGPU_BUFFER_VERTEX       0x04
#define SGPU_BUFFER_INDEX        0x08
#define SGPU_BUFFER_STAGING      0x10
#define SGPU_BUFFER_INDIRECT     0x20
#define SGPU_BUFFER_TRANSFER_SRC 0x40
#define SGPU_BUFFER_TRANSFER_DST 0x80

// Memory properties
#define SGPU_MEMORY_DEVICE_LOCAL  0x01
#define SGPU_MEMORY_HOST_VISIBLE  0x02
#define SGPU_MEMORY_HOST_COHERENT 0x04

// Image formats
#define SGPU_FORMAT_RGBA8      0
#define SGPU_FORMAT_RGBA16F    1
#define SGPU_FORMAT_RGBA32F    2
#define SGPU_FORMAT_R32F       3
#define SGPU_FORMAT_RG32F      4
#define SGPU_FORMAT_DEPTH32F   5
#define SGPU_FORMAT_DEPTH24_S8 6
#define SGPU_FORMAT_R8         7
#define SGPU_FORMAT_RG8        8
#define SGPU_FORMAT_BGRA8      9
#define SGPU_FORMAT_R32U       10
#define SGPU_FORMAT_RG16F      11
#define SGPU_FORMAT_R16F       12
#define SGPU_FORMAT_SWAPCHAIN  99

// Image usage
#define SGPU_IMAGE_SAMPLED      0x01
#define SGPU_IMAGE_STORAGE      0x02
#define SGPU_IMAGE_COLOR_ATTACH 0x04
#define SGPU_IMAGE_DEPTH_ATTACH 0x08
#define SGPU_IMAGE_TRANSFER_SRC 0x10
#define SGPU_IMAGE_TRANSFER_DST 0x20
#define SGPU_IMAGE_INPUT_ATTACH 0x40

// Image types
#define SGPU_IMAGE_1D   0
#define SGPU_IMAGE_2D   1
#define SGPU_IMAGE_3D   2
#define SGPU_IMAGE_CUBE 3

// Filter modes
#define SGPU_FILTER_NEAREST 0
#define SGPU_FILTER_LINEAR  1

// Address modes
#define SGPU_ADDRESS_REPEAT          0
#define SGPU_ADDRESS_MIRRORED_REPEAT 1
#define SGPU_ADDRESS_CLAMP_EDGE      2
#define SGPU_ADDRESS_CLAMP_BORDER    3

// Descriptor types
#define SGPU_DESC_STORAGE_BUFFER   0
#define SGPU_DESC_UNIFORM_BUFFER   1
#define SGPU_DESC_SAMPLED_IMAGE    2
#define SGPU_DESC_STORAGE_IMAGE    3
#define SGPU_DESC_SAMPLER          4
#define SGPU_DESC_COMBINED_SAMPLER 5
#define SGPU_DESC_INPUT_ATTACHMENT 6

// Shader stages
#define SGPU_STAGE_VERTEX   0x01
#define SGPU_STAGE_FRAGMENT 0x02
#define SGPU_STAGE_COMPUTE  0x04
#define SGPU_STAGE_GEOMETRY 0x08
#define SGPU_STAGE_ALL      0x3F

// Topology
#define SGPU_TOPO_POINT_LIST     0
#define SGPU_TOPO_LINE_LIST      1
#define SGPU_TOPO_LINE_STRIP     2
#define SGPU_TOPO_TRIANGLE_LIST  3
#define SGPU_TOPO_TRIANGLE_STRIP 4
#define SGPU_TOPO_TRIANGLE_FAN   5

// Polygon mode
#define SGPU_POLY_FILL  0
#define SGPU_POLY_LINE  1
#define SGPU_POLY_POINT 2

// Cull mode
#define SGPU_CULL_NONE  0
#define SGPU_CULL_FRONT 1
#define SGPU_CULL_BACK  2
#define SGPU_CULL_BOTH  3

// Front face
#define SGPU_FRONT_CCW 0
#define SGPU_FRONT_CW  1

// Blend factors
#define SGPU_BLEND_ZERO                0
#define SGPU_BLEND_ONE                 1
#define SGPU_BLEND_SRC_ALPHA           2
#define SGPU_BLEND_ONE_MINUS_SRC_ALPHA 3

// Blend ops
#define SGPU_BLEND_OP_ADD      0
#define SGPU_BLEND_OP_SUBTRACT 1
#define SGPU_BLEND_OP_MIN      2
#define SGPU_BLEND_OP_MAX      3

// Compare ops
#define SGPU_COMPARE_NEVER   0
#define SGPU_COMPARE_LESS    1
#define SGPU_COMPARE_LEQUAL  3
#define SGPU_COMPARE_GREATER 4
#define SGPU_COMPARE_ALWAYS  7

// Load/store ops
#define SGPU_LOAD_CLEAR    0
#define SGPU_LOAD_LOAD     1
#define SGPU_LOAD_DONTCARE 2
#define SGPU_STORE_STORE    0
#define SGPU_STORE_DONTCARE 1

// Image layouts
#define SGPU_LAYOUT_UNDEFINED    0
#define SGPU_LAYOUT_GENERAL      1
#define SGPU_LAYOUT_COLOR_ATTACH 2
#define SGPU_LAYOUT_DEPTH_ATTACH 3
#define SGPU_LAYOUT_SHADER_READ  4
#define SGPU_LAYOUT_TRANSFER_SRC 5
#define SGPU_LAYOUT_TRANSFER_DST 6
#define SGPU_LAYOUT_PRESENT      7

// Pipeline stages
#define SGPU_PIPE_TOP           0x0001
#define SGPU_PIPE_VERTEX_INPUT  0x0004
#define SGPU_PIPE_VERTEX_SHADER 0x0008
#define SGPU_PIPE_FRAGMENT      0x0010
#define SGPU_PIPE_COLOR_OUTPUT  0x0080
#define SGPU_PIPE_COMPUTE       0x0100
#define SGPU_PIPE_TRANSFER      0x0200
#define SGPU_PIPE_BOTTOM        0x0400
#define SGPU_PIPE_ALL_COMMANDS  0x2000

// Access flags
#define SGPU_ACCESS_NONE           0x0000
#define SGPU_ACCESS_SHADER_READ    0x0001
#define SGPU_ACCESS_SHADER_WRITE   0x0002
#define SGPU_ACCESS_TRANSFER_READ  0x0040
#define SGPU_ACCESS_TRANSFER_WRITE 0x0080
#define SGPU_ACCESS_HOST_READ      0x0100
#define SGPU_ACCESS_HOST_WRITE     0x0200
#define SGPU_ACCESS_MEMORY_READ    0x0400
#define SGPU_ACCESS_MEMORY_WRITE   0x0800

// Vertex input rate
#define SGPU_INPUT_RATE_VERTEX   0
#define SGPU_INPUT_RATE_INSTANCE 1

// Vertex attribute formats
#define SGPU_ATTR_FLOAT 0
#define SGPU_ATTR_VEC2  1
#define SGPU_ATTR_VEC3  2
#define SGPU_ATTR_VEC4  3
#define SGPU_ATTR_INT   4
#define SGPU_ATTR_UINT  8

// ============================================================================
// Configuration Structures (for complex functions)
// ============================================================================

typedef struct {
    int binding;
    int stride;
    int rate;  // SGPU_INPUT_RATE_*
} SageGPUVertexBinding;

typedef struct {
    int location;
    int binding;
    int format;  // SGPU_ATTR_*
    int offset;
} SageGPUVertexAttrib;

typedef struct {
    int binding;
    int type;   // SGPU_DESC_*
    int stage;  // SGPU_STAGE_*
    int count;  // descriptor count (default 1)
} SageGPUDescBinding;

typedef struct {
    int layout;           // pipeline layout handle
    int render_pass;      // render pass handle
    int vertex_shader;    // shader handle
    int fragment_shader;  // shader handle
    int topology;         // SGPU_TOPO_*
    int polygon_mode;     // SGPU_POLY_*
    int cull_mode;        // SGPU_CULL_*
    int front_face;       // SGPU_FRONT_*
    int depth_test;       // bool
    int depth_write;      // bool
    int blend;            // bool
    int subpass;
    int color_attachment_count;  // for MRT (default 1)
    SageGPUVertexBinding* vertex_bindings;
    int vertex_binding_count;
    SageGPUVertexAttrib* vertex_attribs;
    int vertex_attrib_count;
} SageGPUGraphicsPipelineConfig;

typedef struct {
    int format;        // SGPU_FORMAT_*
    int load_op;       // SGPU_LOAD_*
    int store_op;      // SGPU_STORE_*
    int initial_layout;
    int final_layout;
} SageGPURenderPassAttachment;

typedef struct {
    int width;
    int height;
    int depth;
} SageGPUExtent;

// ============================================================================
// Core Lifecycle
// ============================================================================

int  sgpu_get_active_backend(void);
int  sgpu_has_vulkan(void);
int  sgpu_has_opengl(void);
int  sgpu_init(const char* app_name, int validation);
int  sgpu_init_opengl(const char* app_name, int major, int minor);
void sgpu_shutdown(void);
const char* sgpu_device_name(void);
const char* sgpu_last_error(void);

// ============================================================================
// Buffer Operations
// ============================================================================

int  sgpu_create_buffer(int size, int usage, int mem_props);
void sgpu_destroy_buffer(int handle);
int  sgpu_buffer_upload(int handle, const float* data, int count);
int  sgpu_buffer_upload_bytes(int handle, const uint8_t* data, int size);
int  sgpu_buffer_download(int handle, float* out, int max_count);
int  sgpu_buffer_size(int handle);

// ============================================================================
// Image Operations
// ============================================================================

int  sgpu_create_image(int width, int height, int format, int usage, int img_type);
int  sgpu_create_image_3d(int width, int height, int depth, int format, int usage);
void sgpu_destroy_image(int handle);
void sgpu_image_dims(int handle, int* w, int* h, int* d);

// ============================================================================
// Sampler
// ============================================================================

int  sgpu_create_sampler(int min_filter, int mag_filter, int address_mode);
int  sgpu_create_sampler_advanced(int min_filter, int mag_filter, int address_mode,
                                   int mip_mode, float max_anisotropy, int compare_op);
void sgpu_destroy_sampler(int handle);

// ============================================================================
// Shaders
// ============================================================================

int  sgpu_load_shader(const char* path, int stage);
int  sgpu_load_shader_glsl(const char* source, int stage);  // OpenGL: direct GLSL
int  sgpu_reload_shader(int handle, const char* path);
void sgpu_destroy_shader(int handle);

// ============================================================================
// Descriptors
// ============================================================================

int  sgpu_create_descriptor_layout(const SageGPUDescBinding* bindings, int count);
int  sgpu_create_descriptor_pool(int max_sets, const int* type_counts, int type_count);
int  sgpu_allocate_descriptor_set(int pool, int layout);
int  sgpu_allocate_descriptor_sets(int pool, int layout, int count, int* out_handles);
void sgpu_update_descriptor(int set, int binding, int type, int resource_handle);
void sgpu_update_descriptor_image(int set, int binding, int type, int image, int sampler);
void sgpu_update_descriptor_range(int set, int binding, int type, const int* handles, int count);

// ============================================================================
// Pipeline
// ============================================================================

int  sgpu_create_pipeline_layout(const int* desc_layouts, int layout_count,
                                  int push_constant_size, int push_constant_stages);
int  sgpu_create_compute_pipeline(int layout, int shader);
int  sgpu_create_graphics_pipeline(const SageGPUGraphicsPipelineConfig* config);
void sgpu_destroy_pipeline(int handle);
int  sgpu_create_pipeline_cache(void);

// ============================================================================
// Render Pass & Framebuffer
// ============================================================================

int  sgpu_create_render_pass(const SageGPURenderPassAttachment* attachments, int count,
                              int has_depth);
int  sgpu_create_render_pass_mrt(const SageGPURenderPassAttachment* attachments, int count,
                                  int has_depth);
void sgpu_destroy_render_pass(int handle);
int  sgpu_create_framebuffer(int render_pass, const int* image_handles, int count,
                              int width, int height);
void sgpu_destroy_framebuffer(int handle);
int  sgpu_create_depth_buffer(int width, int height, int format);

// ============================================================================
// Command Buffers
// ============================================================================

int  sgpu_create_command_pool(int queue_family);
int  sgpu_create_command_buffer(int pool);
int  sgpu_create_secondary_command_buffer(int pool);
int  sgpu_begin_commands(int cmd);
int  sgpu_begin_secondary(int cmd, int render_pass, int framebuffer, int subpass);
int  sgpu_end_commands(int cmd);

// ============================================================================
// Command Recording
// ============================================================================

void sgpu_cmd_bind_compute_pipeline(int cmd, int pipeline);
void sgpu_cmd_bind_graphics_pipeline(int cmd, int pipeline);
void sgpu_cmd_bind_descriptor_set(int cmd, int pipeline_layout, int set, int bind_point);
void sgpu_cmd_dispatch(int cmd, int gx, int gy, int gz);
void sgpu_cmd_dispatch_indirect(int cmd, int buffer, int offset);
void sgpu_cmd_push_constants(int cmd, int layout, int stages, const float* data, int count);
void sgpu_cmd_begin_render_pass(int cmd, int render_pass, int framebuffer,
                                 int w, int h, float r, float g, float b, float a);
void sgpu_cmd_end_render_pass(int cmd);
void sgpu_cmd_draw(int cmd, int vertex_count, int instance_count, int first_vertex, int first_instance);
void sgpu_cmd_draw_indexed(int cmd, int index_count, int instance_count,
                            int first_index, int vertex_offset, int first_instance);
void sgpu_cmd_draw_indirect(int cmd, int buffer, int offset, int draw_count, int stride);
void sgpu_cmd_draw_indexed_indirect(int cmd, int buffer, int offset, int draw_count, int stride);
void sgpu_cmd_bind_vertex_buffer(int cmd, int buffer);
void sgpu_cmd_bind_vertex_buffers(int cmd, const int* buffers, int count);
void sgpu_cmd_bind_index_buffer(int cmd, int buffer);
void sgpu_cmd_set_viewport(int cmd, float x, float y, float w, float h, float min_d, float max_d);
void sgpu_cmd_set_scissor(int cmd, int x, int y, int w, int h);
void sgpu_cmd_pipeline_barrier(int cmd, int src_stage, int dst_stage,
                                int src_access, int dst_access);
void sgpu_cmd_image_barrier(int cmd, int image, int old_layout, int new_layout,
                             int src_stage, int dst_stage, int src_access, int dst_access);
void sgpu_cmd_copy_buffer(int cmd, int src, int dst, int size);
void sgpu_cmd_copy_buffer_to_image(int cmd, int buffer, int image, int w, int h);
void sgpu_cmd_execute_commands(int cmd, const int* secondary_cmds, int count);
void sgpu_cmd_queue_transfer_barrier(int cmd, int buffer, int src_family, int dst_family);

// ============================================================================
// Synchronization
// ============================================================================

int  sgpu_create_fence(int signaled);
int  sgpu_wait_fence(int fence, double timeout_seconds);
void sgpu_reset_fence(int fence);
void sgpu_destroy_fence(int fence);
int  sgpu_create_semaphore(void);
void sgpu_destroy_semaphore(int sem);
int  sgpu_submit(int cmd, int fence);
int  sgpu_submit_compute(int cmd, int fence);
int  sgpu_submit_with_sync(int cmd, int wait_sem, int signal_sem, int fence);
void sgpu_queue_wait_idle(void);
void sgpu_device_wait_idle(void);

// ============================================================================
// Window & Swapchain
// ============================================================================

int  sgpu_create_window(int width, int height, const char* title);
void sgpu_destroy_window(void);
int  sgpu_window_should_close(void);
void sgpu_poll_events(void);
int  sgpu_init_windowed(const char* title, int width, int height, int validation);
int  sgpu_init_opengl_windowed(const char* title, int width, int height, int major, int minor);
void sgpu_shutdown_windowed(void);
int  sgpu_swapchain_image_count(void);
int  sgpu_swapchain_format(void);
void sgpu_swapchain_extent(int* w, int* h);
int  sgpu_acquire_next_image(int semaphore, int* image_index);
int  sgpu_present(int semaphore, int image_index);
int  sgpu_create_swapchain_framebuffers(int render_pass, int* out_handles, int max_count);
int  sgpu_create_swapchain_framebuffers_depth(int render_pass, int depth_image,
                                               int* out_handles, int max_count);
int  sgpu_recreate_swapchain(void);

// ============================================================================
// Input
// ============================================================================

int  sgpu_key_pressed(int key);
int  sgpu_key_down(int key);
int  sgpu_key_just_pressed(int key);
int  sgpu_key_just_released(int key);
void sgpu_mouse_pos(double* x, double* y);
int  sgpu_mouse_button(int button);
int  sgpu_mouse_just_pressed(int button);
int  sgpu_mouse_just_released(int button);
void sgpu_mouse_delta(double* dx, double* dy);
void sgpu_scroll_delta(double* dx, double* dy);
void sgpu_set_cursor_mode(int mode);
double sgpu_get_time(void);
void sgpu_window_size(int* w, int* h);
void sgpu_set_title(const char* title);
int  sgpu_window_resized(void);
void sgpu_update_input(void);
int  sgpu_text_input_available(void);
int  sgpu_text_input_read(void);  // returns codepoint or 0

// ============================================================================
// Texture Loading (stb_image based)
// ============================================================================

int  sgpu_load_texture(const char* path, int gen_mipmaps, int filter, int address);
void sgpu_texture_dims(int handle, int* w, int* h);
int  sgpu_generate_mipmaps(int image);
int  sgpu_create_cubemap(const char** face_paths, int face_count);

// ============================================================================
// Upload Helpers
// ============================================================================

int  sgpu_upload_device_local(const float* data, int count, int usage);
int  sgpu_upload_bytes(const uint8_t* data, int size, int usage);

// ============================================================================
// Uniform Buffers
// ============================================================================

int  sgpu_create_uniform_buffer(int size);
int  sgpu_update_uniform(int handle, const float* data, int count);

// ============================================================================
// Offscreen Rendering
// ============================================================================

int  sgpu_create_offscreen_target(int width, int height, int format, int usage);

// ============================================================================
// Screenshot
// ============================================================================

int  sgpu_screenshot(uint8_t* out_pixels, int max_size, int* w, int* h);
int  sgpu_save_screenshot(const char* path);

// ============================================================================
// Font Rendering
// ============================================================================

int  sgpu_load_font(const char* path, int size);
int  sgpu_font_atlas(int font);
int  sgpu_font_set_atlas(int font, int image, int sampler);
int  sgpu_font_text_verts(int font, const char* text, float x, float y, float scale,
                           float* out_verts, int max_verts);
void sgpu_font_measure(int font, const char* text, float scale, float* w, float* h);

// ============================================================================
// glTF Loading
// ============================================================================

int  sgpu_load_gltf(const char* path);  // Returns mesh handle

// ============================================================================
// Queue Families
// ============================================================================

int  sgpu_graphics_family(void);
int  sgpu_compute_family(void);

// ============================================================================
// Platform Override
// ============================================================================

void sgpu_set_platform(const char* platform);
const char* sgpu_get_platform(void);
const char* sgpu_detected_platform(void);

#endif // SAGE_GPU_API_H
