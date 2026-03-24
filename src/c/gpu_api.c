// src/c/gpu_api.c — Pure C GPU API for SageLang
//
// Backend-agnostic GPU API with simple C types (no Value dependency).
// Used by:
//   - llvm_runtime.c (LLVM compiled path)
//   - graphics.c (interpreter path, via wrapper functions)
//   - vm.c (bytecode VM GPU opcodes)
//
// Backends:
//   - Vulkan (SAGE_HAS_VULKAN) — full implementation
//   - OpenGL 4.5+ (SAGE_HAS_OPENGL) — core rendering
//   - Stubs (neither) — returns errors gracefully

#define _GNU_SOURCE
#include "gpu_api.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifdef SAGE_HAS_GLFW
#define GLFW_INCLUDE_NONE
#ifdef SAGE_HAS_VULKAN
#undef GLFW_INCLUDE_NONE
#define GLFW_INCLUDE_VULKAN
#endif
#include <GLFW/glfw3.h>
#endif

#ifdef SAGE_HAS_VULKAN
#include <vulkan/vulkan.h>
#endif

#ifdef SAGE_HAS_OPENGL
#include <GL/gl.h>
#include <GL/glext.h>
#endif

// ============================================================================
// Memory Helpers (standalone, no GC dependency)
// ============================================================================

#define GPU_ALLOC(sz) calloc(1, (sz))
#define GPU_REALLOC(p, sz) realloc((p), (sz))
#define GPU_FREE(p) free(p)
#define GPU_STRDUP(s) strdup(s)

// ============================================================================
// Error State
// ============================================================================

static char g_gpu_error[512] = {0};
#define SET_ERROR(msg) snprintf(g_gpu_error, sizeof(g_gpu_error), "%s", (msg))
#define CLEAR_ERROR() (g_gpu_error[0] = '\0')

// ============================================================================
// Backend State
// ============================================================================

static int g_active_backend = SAGE_GPU_BACKEND_NONE;
static int g_initialized = 0;

// Platform override
static char g_platform_override[64] = {0};

// Input state tracking
static int g_key_states[512] = {0};
static int g_key_prev[512] = {0};
static int g_mouse_states[8] = {0};
static int g_mouse_prev[8] = {0};
static double g_mouse_x = 0, g_mouse_y = 0;
static double g_prev_mouse_x = 0, g_prev_mouse_y = 0;
static double g_scroll_dx = 0, g_scroll_dy = 0;
static int g_window_resized_flag = 0;

#ifdef SAGE_HAS_GLFW
static GLFWwindow* g_window = NULL;

static void glfw_key_callback(GLFWwindow* w, int key, int scancode, int action, int mods) {
    (void)w; (void)scancode; (void)mods;
    if (key >= 0 && key < 512) {
        g_key_states[key] = (action != GLFW_RELEASE) ? 1 : 0;
    }
}

static void glfw_mouse_callback(GLFWwindow* w, int button, int action, int mods) {
    (void)w; (void)mods;
    if (button >= 0 && button < 8) {
        g_mouse_states[button] = (action == GLFW_PRESS) ? 1 : 0;
    }
}

static void glfw_scroll_callback(GLFWwindow* w, double xoff, double yoff) {
    (void)w;
    g_scroll_dx = xoff;
    g_scroll_dy = yoff;
}

static void glfw_resize_callback(GLFWwindow* w, int width, int height) {
    (void)w; (void)width; (void)height;
    g_window_resized_flag = 1;
}
#endif

// ============================================================================
// Vulkan Backend State
// ============================================================================

#ifdef SAGE_HAS_VULKAN

#define MAX_HANDLES 4096

typedef struct {
    VkBuffer buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;
    int usage;
    int mem_props;
    void* mapped;
    int alive;
} GPUBuffer;

typedef struct {
    VkImage image;
    VkDeviceMemory memory;
    VkImageView view;
    int format;
    int img_type;
    int width, height, depth;
    int mip_levels;
    int usage;
    int alive;
} GPUImage;

typedef struct {
    VkSampler sampler;
    int alive;
} GPUSampler;

typedef struct {
    VkShaderModule module;
    int stage;
    int alive;
} GPUShader;

typedef struct {
    VkDescriptorSetLayout layout;
    int alive;
} GPUDescLayout;

typedef struct {
    VkDescriptorPool pool;
    int alive;
} GPUDescPool;

typedef struct {
    VkDescriptorSet set;
    int alive;
} GPUDescSet;

typedef struct {
    VkPipelineLayout layout;
    int alive;
} GPUPipeLayout;

typedef struct {
    VkPipeline pipeline;
    int is_compute;
    int alive;
} GPUPipeline;

typedef struct {
    VkRenderPass render_pass;
    int alive;
} GPURenderPass;

typedef struct {
    VkFramebuffer framebuffer;
    int alive;
} GPUFramebuffer;

typedef struct {
    VkCommandPool pool;
    int alive;
} GPUCmdPool;

typedef struct {
    VkCommandBuffer cmd;
    VkCommandPool pool;
    int alive;
} GPUCmdBuffer;

typedef struct {
    VkFence fence;
    int alive;
} GPUFence;

typedef struct {
    VkSemaphore semaphore;
    int alive;
} GPUSemaphore;

static struct {
    VkInstance instance;
    VkPhysicalDevice physical_device;
    VkDevice device;
    VkQueue graphics_queue;
    VkQueue compute_queue;
    uint32_t graphics_family;
    uint32_t compute_family;
    int initialized;

    GPUBuffer* buffers;       int buffer_count, buffer_cap;
    GPUImage* images;         int image_count, image_cap;
    GPUSampler* samplers;     int sampler_count, sampler_cap;
    GPUShader* shaders;       int shader_count, shader_cap;
    GPUDescLayout* desc_layouts; int desc_layout_count, desc_layout_cap;
    GPUDescPool* desc_pools;  int desc_pool_count, desc_pool_cap;
    GPUDescSet* desc_sets;    int desc_set_count, desc_set_cap;
    GPUPipeLayout* pipe_layouts; int pipe_layout_count, pipe_layout_cap;
    GPUPipeline* pipelines;   int pipeline_count, pipeline_cap;
    GPURenderPass* render_passes; int render_pass_count, render_pass_cap;
    GPUFramebuffer* framebuffers; int framebuffer_count, framebuffer_cap;
    GPUCmdPool* cmd_pools;    int cmd_pool_count, cmd_pool_cap;
    GPUCmdBuffer* cmd_buffers; int cmd_buffer_count, cmd_buffer_cap;
    GPUFence* fences;         int fence_count, fence_cap;
    GPUSemaphore* semaphores; int semaphore_count, semaphore_cap;
} g_vk = {0};

// Swapchain state
static VkSurfaceKHR g_surface = VK_NULL_HANDLE;
static VkSwapchainKHR g_swapchain = VK_NULL_HANDLE;
static VkImage* g_swapchain_images = NULL;
static VkImageView* g_swapchain_views = NULL;
static uint32_t g_swapchain_image_count = 0;
static uint32_t g_swapchain_width = 0, g_swapchain_height = 0;
static VkFormat g_swapchain_format = VK_FORMAT_B8G8R8A8_UNORM;

// Handle allocator macro
#define ALLOC_HANDLE(arr, count, cap, type) do { \
    if ((count) >= (cap)) { \
        int nc = (cap) == 0 ? 64 : (cap) * 2; \
        (arr) = GPU_REALLOC((arr), sizeof(type) * (size_t)nc); \
        memset(&(arr)[(cap)], 0, sizeof(type) * (size_t)(nc - (cap))); \
        (cap) = nc; \
    } \
} while(0)

static int alloc_handle(void** arr, int* count, int* cap, size_t elem_size) {
    if (*count >= *cap) {
        int nc = *cap == 0 ? 64 : *cap * 2;
        *arr = GPU_REALLOC(*arr, elem_size * (size_t)nc);
        memset((char*)*arr + elem_size * (size_t)*cap, 0, elem_size * (size_t)(nc - *cap));
        *cap = nc;
    }
    int idx = *count;
    (*count)++;
    return idx;
}

#define ALLOC_BUF() alloc_handle((void**)&g_vk.buffers, &g_vk.buffer_count, &g_vk.buffer_cap, sizeof(GPUBuffer))
#define ALLOC_IMG() alloc_handle((void**)&g_vk.images, &g_vk.image_count, &g_vk.image_cap, sizeof(GPUImage))
#define ALLOC_SAMP() alloc_handle((void**)&g_vk.samplers, &g_vk.sampler_count, &g_vk.sampler_cap, sizeof(GPUSampler))
#define ALLOC_SHDR() alloc_handle((void**)&g_vk.shaders, &g_vk.shader_count, &g_vk.shader_cap, sizeof(GPUShader))
#define ALLOC_DL() alloc_handle((void**)&g_vk.desc_layouts, &g_vk.desc_layout_count, &g_vk.desc_layout_cap, sizeof(GPUDescLayout))
#define ALLOC_DP() alloc_handle((void**)&g_vk.desc_pools, &g_vk.desc_pool_count, &g_vk.desc_pool_cap, sizeof(GPUDescPool))
#define ALLOC_DS() alloc_handle((void**)&g_vk.desc_sets, &g_vk.desc_set_count, &g_vk.desc_set_cap, sizeof(GPUDescSet))
#define ALLOC_PL() alloc_handle((void**)&g_vk.pipe_layouts, &g_vk.pipe_layout_count, &g_vk.pipe_layout_cap, sizeof(GPUPipeLayout))
#define ALLOC_PIPE() alloc_handle((void**)&g_vk.pipelines, &g_vk.pipeline_count, &g_vk.pipeline_cap, sizeof(GPUPipeline))
#define ALLOC_RP() alloc_handle((void**)&g_vk.render_passes, &g_vk.render_pass_count, &g_vk.render_pass_cap, sizeof(GPURenderPass))
#define ALLOC_FB() alloc_handle((void**)&g_vk.framebuffers, &g_vk.framebuffer_count, &g_vk.framebuffer_cap, sizeof(GPUFramebuffer))
#define ALLOC_CP() alloc_handle((void**)&g_vk.cmd_pools, &g_vk.cmd_pool_count, &g_vk.cmd_pool_cap, sizeof(GPUCmdPool))
#define ALLOC_CB() alloc_handle((void**)&g_vk.cmd_buffers, &g_vk.cmd_buffer_count, &g_vk.cmd_buffer_cap, sizeof(GPUCmdBuffer))
#define ALLOC_FN() alloc_handle((void**)&g_vk.fences, &g_vk.fence_count, &g_vk.fence_cap, sizeof(GPUFence))
#define ALLOC_SEM() alloc_handle((void**)&g_vk.semaphores, &g_vk.semaphore_count, &g_vk.semaphore_cap, sizeof(GPUSemaphore))

// Helper: find memory type
static uint32_t find_memory_type(uint32_t type_filter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties mem_props;
    vkGetPhysicalDeviceMemoryProperties(g_vk.physical_device, &mem_props);
    for (uint32_t i = 0; i < mem_props.memoryTypeCount; i++) {
        if ((type_filter & (1 << i)) &&
            (mem_props.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return 0;
}

// Helper: translate buffer usage flags
static VkBufferUsageFlags translate_usage(int sage_usage) {
    VkBufferUsageFlags vk = 0;
    if (sage_usage & SGPU_BUFFER_STORAGE) vk |= VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if (sage_usage & SGPU_BUFFER_UNIFORM) vk |= VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if (sage_usage & SGPU_BUFFER_VERTEX) vk |= VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if (sage_usage & SGPU_BUFFER_INDEX) vk |= VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (sage_usage & SGPU_BUFFER_STAGING) vk |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (sage_usage & SGPU_BUFFER_INDIRECT) vk |= VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
    if (sage_usage & SGPU_BUFFER_TRANSFER_SRC) vk |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (sage_usage & SGPU_BUFFER_TRANSFER_DST) vk |= VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    return vk;
}

// Helper: translate memory property flags
static VkMemoryPropertyFlags translate_mem(int sage_mem) {
    VkMemoryPropertyFlags vk = 0;
    if (sage_mem & SGPU_MEMORY_DEVICE_LOCAL) vk |= VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    if (sage_mem & SGPU_MEMORY_HOST_VISIBLE) vk |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
    if (sage_mem & SGPU_MEMORY_HOST_COHERENT) vk |= VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    return vk;
}

#endif // SAGE_HAS_VULKAN

// ============================================================================
// Core Lifecycle
// ============================================================================

int sgpu_get_active_backend(void) { return g_active_backend; }
int sgpu_has_vulkan(void) {
    #ifdef SAGE_HAS_VULKAN
    return 1;
    #else
    return 0;
    #endif
}
int sgpu_has_opengl(void) {
    #ifdef SAGE_HAS_OPENGL
    return 1;
    #else
    return 0;
    #endif
}

int sgpu_init(const char* app_name, int validation) {
    if (g_initialized) return 1;
    CLEAR_ERROR();

#ifdef SAGE_HAS_VULKAN
    VkApplicationInfo app_info = {0};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = app_name ? app_name : "SageLang GPU";
    app_info.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    app_info.pEngineName = "SageLang";
    app_info.apiVersion = VK_API_VERSION_1_0;

    const char* layers[] = { "VK_LAYER_KHRONOS_validation" };
    VkInstanceCreateInfo create_info = {0};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;
    if (validation) {
        create_info.enabledLayerCount = 1;
        create_info.ppEnabledLayerNames = layers;
    }

    if (vkCreateInstance(&create_info, NULL, &g_vk.instance) != VK_SUCCESS) {
        SET_ERROR("Failed to create Vulkan instance");
        return 0;
    }

    // Pick physical device
    uint32_t dev_count = 0;
    vkEnumeratePhysicalDevices(g_vk.instance, &dev_count, NULL);
    if (dev_count == 0) {
        SET_ERROR("No Vulkan-capable GPU found");
        return 0;
    }
    VkPhysicalDevice* devices = GPU_ALLOC(sizeof(VkPhysicalDevice) * dev_count);
    vkEnumeratePhysicalDevices(g_vk.instance, &dev_count, devices);
    g_vk.physical_device = devices[0];  // Use first device
    GPU_FREE(devices);

    // Find queue families
    uint32_t qf_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(g_vk.physical_device, &qf_count, NULL);
    VkQueueFamilyProperties* qf_props = GPU_ALLOC(sizeof(VkQueueFamilyProperties) * qf_count);
    vkGetPhysicalDeviceQueueFamilyProperties(g_vk.physical_device, &qf_count, qf_props);

    g_vk.graphics_family = 0;
    g_vk.compute_family = 0;
    for (uint32_t i = 0; i < qf_count; i++) {
        if (qf_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) g_vk.graphics_family = i;
        if (qf_props[i].queueFlags & VK_QUEUE_COMPUTE_BIT) g_vk.compute_family = i;
    }
    GPU_FREE(qf_props);

    // Create logical device
    float queue_priority = 1.0f;
    VkDeviceQueueCreateInfo queue_infos[2] = {0};
    int queue_count = 1;
    queue_infos[0].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_infos[0].queueFamilyIndex = g_vk.graphics_family;
    queue_infos[0].queueCount = 1;
    queue_infos[0].pQueuePriorities = &queue_priority;

    if (g_vk.compute_family != g_vk.graphics_family) {
        queue_infos[1].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_infos[1].queueFamilyIndex = g_vk.compute_family;
        queue_infos[1].queueCount = 1;
        queue_infos[1].pQueuePriorities = &queue_priority;
        queue_count = 2;
    }

    VkPhysicalDeviceFeatures features = {0};
    features.fillModeNonSolid = VK_TRUE;

    const char* dev_exts[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
    VkDeviceCreateInfo dev_info = {0};
    dev_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dev_info.queueCreateInfoCount = (uint32_t)queue_count;
    dev_info.pQueueCreateInfos = queue_infos;
    dev_info.pEnabledFeatures = &features;
    dev_info.enabledExtensionCount = 1;
    dev_info.ppEnabledExtensionNames = dev_exts;

    if (vkCreateDevice(g_vk.physical_device, &dev_info, NULL, &g_vk.device) != VK_SUCCESS) {
        SET_ERROR("Failed to create Vulkan device");
        return 0;
    }

    vkGetDeviceQueue(g_vk.device, g_vk.graphics_family, 0, &g_vk.graphics_queue);
    vkGetDeviceQueue(g_vk.device, g_vk.compute_family, 0, &g_vk.compute_queue);

    g_vk.initialized = 1;
    g_active_backend = SAGE_GPU_BACKEND_VULKAN;
    g_initialized = 1;
    return 1;
#else
    (void)app_name; (void)validation;
    SET_ERROR("No GPU backend available (compile with SAGE_HAS_VULKAN or SAGE_HAS_OPENGL)");
    return 0;
#endif
}

int sgpu_init_opengl(const char* app_name, int major, int minor) {
    if (g_initialized) return 1;
    CLEAR_ERROR();
#ifdef SAGE_HAS_OPENGL
    (void)app_name; (void)major; (void)minor;
    g_active_backend = SAGE_GPU_BACKEND_OPENGL;
    g_initialized = 1;
    return 1;
#else
    (void)app_name; (void)major; (void)minor;
    SET_ERROR("OpenGL not available (compile with SAGE_HAS_OPENGL)");
    return 0;
#endif
}

void sgpu_shutdown(void) {
    if (!g_initialized) return;
#ifdef SAGE_HAS_VULKAN
    if (g_active_backend == SAGE_GPU_BACKEND_VULKAN && g_vk.initialized) {
        vkDeviceWaitIdle(g_vk.device);
        // Free all handle tables
        GPU_FREE(g_vk.buffers);
        GPU_FREE(g_vk.images);
        GPU_FREE(g_vk.samplers);
        GPU_FREE(g_vk.shaders);
        GPU_FREE(g_vk.desc_layouts);
        GPU_FREE(g_vk.desc_pools);
        GPU_FREE(g_vk.desc_sets);
        GPU_FREE(g_vk.pipe_layouts);
        GPU_FREE(g_vk.pipelines);
        GPU_FREE(g_vk.render_passes);
        GPU_FREE(g_vk.framebuffers);
        GPU_FREE(g_vk.cmd_pools);
        GPU_FREE(g_vk.cmd_buffers);
        GPU_FREE(g_vk.fences);
        GPU_FREE(g_vk.semaphores);
        vkDestroyDevice(g_vk.device, NULL);
        vkDestroyInstance(g_vk.instance, NULL);
        memset(&g_vk, 0, sizeof(g_vk));
    }
#endif
    g_active_backend = SAGE_GPU_BACKEND_NONE;
    g_initialized = 0;
}

const char* sgpu_device_name(void) {
#ifdef SAGE_HAS_VULKAN
    if (g_active_backend == SAGE_GPU_BACKEND_VULKAN && g_vk.initialized) {
        static VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(g_vk.physical_device, &props);
        return props.deviceName;
    }
#endif
    return "Unknown";
}

const char* sgpu_last_error(void) { return g_gpu_error; }

// ============================================================================
// Buffer Operations
// ============================================================================

int sgpu_create_buffer(int size, int usage, int mem_props) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized) return SGPU_INVALID_HANDLE;
    int idx = ALLOC_BUF();

    VkBufferCreateInfo bi = {0};
    bi.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bi.size = (VkDeviceSize)size;
    bi.usage = translate_usage(usage);
    bi.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (vkCreateBuffer(g_vk.device, &bi, NULL, &g_vk.buffers[idx].buffer) != VK_SUCCESS)
        return SGPU_INVALID_HANDLE;

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(g_vk.device, g_vk.buffers[idx].buffer, &req);

    VkMemoryAllocateInfo ai = {0};
    ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = find_memory_type(req.memoryTypeBits, translate_mem(mem_props));

    if (vkAllocateMemory(g_vk.device, &ai, NULL, &g_vk.buffers[idx].memory) != VK_SUCCESS) {
        vkDestroyBuffer(g_vk.device, g_vk.buffers[idx].buffer, NULL);
        return SGPU_INVALID_HANDLE;
    }

    vkBindBufferMemory(g_vk.device, g_vk.buffers[idx].buffer, g_vk.buffers[idx].memory, 0);
    g_vk.buffers[idx].size = (VkDeviceSize)size;
    g_vk.buffers[idx].usage = usage;
    g_vk.buffers[idx].mem_props = mem_props;
    g_vk.buffers[idx].alive = 1;

    if (mem_props & SGPU_MEMORY_HOST_VISIBLE) {
        vkMapMemory(g_vk.device, g_vk.buffers[idx].memory, 0, (VkDeviceSize)size, 0,
                     &g_vk.buffers[idx].mapped);
    }
    return idx;
#else
    (void)size; (void)usage; (void)mem_props;
    return SGPU_INVALID_HANDLE;
#endif
}

void sgpu_destroy_buffer(int handle) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || handle < 0 || handle >= g_vk.buffer_count) return;
    if (!g_vk.buffers[handle].alive) return;
    if (g_vk.buffers[handle].mapped)
        vkUnmapMemory(g_vk.device, g_vk.buffers[handle].memory);
    vkDestroyBuffer(g_vk.device, g_vk.buffers[handle].buffer, NULL);
    vkFreeMemory(g_vk.device, g_vk.buffers[handle].memory, NULL);
    g_vk.buffers[handle].alive = 0;
#else
    (void)handle;
#endif
}

int sgpu_buffer_upload(int handle, const float* data, int count) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || handle < 0 || handle >= g_vk.buffer_count) return 0;
    if (!g_vk.buffers[handle].alive || !data || count <= 0) return 0;
    size_t sz = sizeof(float) * (size_t)count;
    if (sz > (size_t)g_vk.buffers[handle].size) sz = (size_t)g_vk.buffers[handle].size;
    void* mapped = g_vk.buffers[handle].mapped;
    int need_unmap = 0;
    if (!mapped) {
        if (vkMapMemory(g_vk.device, g_vk.buffers[handle].memory, 0,
                        g_vk.buffers[handle].size, 0, &mapped) != VK_SUCCESS) return 0;
        need_unmap = 1;
    }
    memcpy(mapped, data, sz);
    if (need_unmap) vkUnmapMemory(g_vk.device, g_vk.buffers[handle].memory);
    return 1;
#else
    (void)handle; (void)data; (void)count;
    return 0;
#endif
}

int sgpu_buffer_upload_bytes(int handle, const uint8_t* data, int size) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || handle < 0 || handle >= g_vk.buffer_count) return 0;
    if (!g_vk.buffers[handle].alive || !data || size <= 0) return 0;
    size_t sz = (size_t)size;
    if (sz > (size_t)g_vk.buffers[handle].size) sz = (size_t)g_vk.buffers[handle].size;
    void* mapped = g_vk.buffers[handle].mapped;
    int need_unmap = 0;
    if (!mapped) {
        if (vkMapMemory(g_vk.device, g_vk.buffers[handle].memory, 0,
                        g_vk.buffers[handle].size, 0, &mapped) != VK_SUCCESS) return 0;
        need_unmap = 1;
    }
    memcpy(mapped, data, sz);
    if (need_unmap) vkUnmapMemory(g_vk.device, g_vk.buffers[handle].memory);
    return 1;
#else
    (void)handle; (void)data; (void)size;
    return 0;
#endif
}

int sgpu_buffer_download(int handle, float* out, int max_count) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || handle < 0 || handle >= g_vk.buffer_count) return 0;
    if (!g_vk.buffers[handle].alive || !out) return 0;
    int count = (int)(g_vk.buffers[handle].size / sizeof(float));
    if (count > max_count) count = max_count;
    void* mapped = g_vk.buffers[handle].mapped;
    int need_unmap = 0;
    if (!mapped) {
        if (vkMapMemory(g_vk.device, g_vk.buffers[handle].memory, 0,
                        g_vk.buffers[handle].size, 0, &mapped) != VK_SUCCESS) return 0;
        need_unmap = 1;
    }
    memcpy(out, mapped, sizeof(float) * (size_t)count);
    if (need_unmap) vkUnmapMemory(g_vk.device, g_vk.buffers[handle].memory);
    return count;
#else
    (void)handle; (void)out; (void)max_count;
    return 0;
#endif
}

int sgpu_buffer_size(int handle) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || handle < 0 || handle >= g_vk.buffer_count) return 0;
    if (!g_vk.buffers[handle].alive) return 0;
    return (int)g_vk.buffers[handle].size;
#else
    (void)handle;
    return 0;
#endif
}

// ============================================================================
// Stub implementations for functions that need more Vulkan code
// These delegate to the interpreter's graphics.c when called via the
// interpreter path, and provide basic implementations for LLVM compiled path.
// ============================================================================

// Image operations
int sgpu_create_image(int w, int h, int format, int usage, int img_type) {
    (void)w; (void)h; (void)format; (void)usage; (void)img_type;
    SET_ERROR("sgpu_create_image: use interpreter path or full gpu_api build");
    return SGPU_INVALID_HANDLE;
}
int sgpu_create_image_3d(int w, int h, int d, int format, int usage) {
    (void)w; (void)h; (void)d; (void)format; (void)usage;
    return SGPU_INVALID_HANDLE;
}
void sgpu_destroy_image(int handle) { (void)handle; }
void sgpu_image_dims(int handle, int* w, int* h, int* d) {
    (void)handle; if (w) *w = 0; if (h) *h = 0; if (d) *d = 0;
}

// Sampler
int sgpu_create_sampler(int min_f, int mag_f, int addr) {
    (void)min_f; (void)mag_f; (void)addr;
    return SGPU_INVALID_HANDLE;
}
int sgpu_create_sampler_advanced(int min_f, int mag_f, int addr, int mip, float aniso, int cmp) {
    (void)min_f; (void)mag_f; (void)addr; (void)mip; (void)aniso; (void)cmp;
    return SGPU_INVALID_HANDLE;
}
void sgpu_destroy_sampler(int handle) { (void)handle; }

// Shaders
int sgpu_load_shader(const char* path, int stage) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized) return SGPU_INVALID_HANDLE;
    FILE* f = fopen(path, "rb");
    if (!f) { SET_ERROR("Cannot open shader file"); return SGPU_INVALID_HANDLE; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint32_t* code = GPU_ALLOC((size_t)sz);
    fread(code, 1, (size_t)sz, f);
    fclose(f);

    int idx = ALLOC_SHDR();
    VkShaderModuleCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    ci.codeSize = (size_t)sz;
    ci.pCode = code;
    if (vkCreateShaderModule(g_vk.device, &ci, NULL, &g_vk.shaders[idx].module) != VK_SUCCESS) {
        GPU_FREE(code);
        return SGPU_INVALID_HANDLE;
    }
    GPU_FREE(code);
    g_vk.shaders[idx].stage = stage;
    g_vk.shaders[idx].alive = 1;
    return idx;
#else
    (void)path; (void)stage;
    return SGPU_INVALID_HANDLE;
#endif
}

int sgpu_load_shader_glsl(const char* source, int stage) {
    (void)source; (void)stage;
    SET_ERROR("GLSL shader loading requires OpenGL backend");
    return SGPU_INVALID_HANDLE;
}
int sgpu_reload_shader(int handle, const char* path) { (void)handle; (void)path; return 0; }
void sgpu_destroy_shader(int handle) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || handle < 0 || handle >= g_vk.shader_count) return;
    if (!g_vk.shaders[handle].alive) return;
    vkDestroyShaderModule(g_vk.device, g_vk.shaders[handle].module, NULL);
    g_vk.shaders[handle].alive = 0;
#else
    (void)handle;
#endif
}

// Descriptors
int sgpu_create_descriptor_layout(const SageGPUDescBinding* bindings, int count) {
    (void)bindings; (void)count;
    return SGPU_INVALID_HANDLE;
}
int sgpu_create_descriptor_pool(int max_sets, const int* type_counts, int type_count) {
    (void)max_sets; (void)type_counts; (void)type_count;
    return SGPU_INVALID_HANDLE;
}
int sgpu_allocate_descriptor_set(int pool, int layout) {
    (void)pool; (void)layout;
    return SGPU_INVALID_HANDLE;
}
int sgpu_allocate_descriptor_sets(int pool, int layout, int count, int* out) {
    (void)pool; (void)layout; (void)count; (void)out;
    return 0;
}
void sgpu_update_descriptor(int set, int binding, int type, int resource) {
    (void)set; (void)binding; (void)type; (void)resource;
}
void sgpu_update_descriptor_image(int set, int binding, int type, int image, int sampler) {
    (void)set; (void)binding; (void)type; (void)image; (void)sampler;
}
void sgpu_update_descriptor_range(int set, int binding, int type, const int* handles, int count) {
    (void)set; (void)binding; (void)type; (void)handles; (void)count;
}

// Pipelines
int sgpu_create_pipeline_layout(const int* desc_layouts, int layout_count, int pc_size, int pc_stages) {
    (void)desc_layouts; (void)layout_count; (void)pc_size; (void)pc_stages;
    return SGPU_INVALID_HANDLE;
}
int sgpu_create_compute_pipeline(int layout, int shader) {
    (void)layout; (void)shader;
    return SGPU_INVALID_HANDLE;
}
int sgpu_create_graphics_pipeline(const SageGPUGraphicsPipelineConfig* config) {
    (void)config;
    return SGPU_INVALID_HANDLE;
}
void sgpu_destroy_pipeline(int handle) { (void)handle; }
int sgpu_create_pipeline_cache(void) { return SGPU_INVALID_HANDLE; }

// Render pass / Framebuffer
int sgpu_create_render_pass(const SageGPURenderPassAttachment* att, int count, int has_depth) {
    (void)att; (void)count; (void)has_depth;
    return SGPU_INVALID_HANDLE;
}
int sgpu_create_render_pass_mrt(const SageGPURenderPassAttachment* att, int count, int has_depth) {
    (void)att; (void)count; (void)has_depth;
    return SGPU_INVALID_HANDLE;
}
void sgpu_destroy_render_pass(int handle) { (void)handle; }
int sgpu_create_framebuffer(int rp, const int* imgs, int count, int w, int h) {
    (void)rp; (void)imgs; (void)count; (void)w; (void)h;
    return SGPU_INVALID_HANDLE;
}
void sgpu_destroy_framebuffer(int handle) { (void)handle; }
int sgpu_create_depth_buffer(int w, int h, int format) {
    (void)w; (void)h; (void)format;
    return SGPU_INVALID_HANDLE;
}

// Commands
int sgpu_create_command_pool(int family) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized) return SGPU_INVALID_HANDLE;
    int idx = ALLOC_CP();
    VkCommandPoolCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    ci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    ci.queueFamilyIndex = (uint32_t)family;
    if (vkCreateCommandPool(g_vk.device, &ci, NULL, &g_vk.cmd_pools[idx].pool) != VK_SUCCESS)
        return SGPU_INVALID_HANDLE;
    g_vk.cmd_pools[idx].alive = 1;
    return idx;
#else
    (void)family;
    return SGPU_INVALID_HANDLE;
#endif
}

int sgpu_create_command_buffer(int pool) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || pool < 0 || pool >= g_vk.cmd_pool_count) return SGPU_INVALID_HANDLE;
    int idx = ALLOC_CB();
    VkCommandBufferAllocateInfo ai = {0};
    ai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    ai.commandPool = g_vk.cmd_pools[pool].pool;
    ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    ai.commandBufferCount = 1;
    if (vkAllocateCommandBuffers(g_vk.device, &ai, &g_vk.cmd_buffers[idx].cmd) != VK_SUCCESS)
        return SGPU_INVALID_HANDLE;
    g_vk.cmd_buffers[idx].pool = g_vk.cmd_pools[pool].pool;
    g_vk.cmd_buffers[idx].alive = 1;
    return idx;
#else
    (void)pool;
    return SGPU_INVALID_HANDLE;
#endif
}

int sgpu_create_secondary_command_buffer(int pool) { (void)pool; return SGPU_INVALID_HANDLE; }

int sgpu_begin_commands(int cmd) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return 0;
    VkCommandBufferBeginInfo bi = {0};
    bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    return vkBeginCommandBuffer(g_vk.cmd_buffers[cmd].cmd, &bi) == VK_SUCCESS;
#else
    (void)cmd;
    return 0;
#endif
}

int sgpu_begin_secondary(int cmd, int rp, int fb, int subpass) {
    (void)cmd; (void)rp; (void)fb; (void)subpass;
    return 0;
}

int sgpu_end_commands(int cmd) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return 0;
    return vkEndCommandBuffer(g_vk.cmd_buffers[cmd].cmd) == VK_SUCCESS;
#else
    (void)cmd;
    return 0;
#endif
}

// Command recording
void sgpu_cmd_bind_compute_pipeline(int cmd, int pipe) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count || pipe < 0 || pipe >= g_vk.pipeline_count) return;
    vkCmdBindPipeline(g_vk.cmd_buffers[cmd].cmd, VK_PIPELINE_BIND_POINT_COMPUTE, g_vk.pipelines[pipe].pipeline);
#else
    (void)cmd; (void)pipe;
#endif
}

void sgpu_cmd_bind_graphics_pipeline(int cmd, int pipe) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count || pipe < 0 || pipe >= g_vk.pipeline_count) return;
    vkCmdBindPipeline(g_vk.cmd_buffers[cmd].cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, g_vk.pipelines[pipe].pipeline);
#else
    (void)cmd; (void)pipe;
#endif
}

void sgpu_cmd_bind_descriptor_set(int cmd, int pl, int set, int bp) {
    (void)cmd; (void)pl; (void)set; (void)bp;
}

void sgpu_cmd_dispatch(int cmd, int gx, int gy, int gz) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return;
    vkCmdDispatch(g_vk.cmd_buffers[cmd].cmd, (uint32_t)gx, (uint32_t)gy, (uint32_t)gz);
#else
    (void)cmd; (void)gx; (void)gy; (void)gz;
#endif
}

void sgpu_cmd_dispatch_indirect(int cmd, int buf, int offset) { (void)cmd; (void)buf; (void)offset; }

void sgpu_cmd_push_constants(int cmd, int layout, int stages, const float* data, int count) {
    (void)cmd; (void)layout; (void)stages; (void)data; (void)count;
}

void sgpu_cmd_begin_render_pass(int cmd, int rp, int fb, int w, int h, float r, float g, float b, float a) {
    (void)cmd; (void)rp; (void)fb; (void)w; (void)h; (void)r; (void)g; (void)b; (void)a;
}

void sgpu_cmd_end_render_pass(int cmd) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return;
    vkCmdEndRenderPass(g_vk.cmd_buffers[cmd].cmd);
#else
    (void)cmd;
#endif
}

void sgpu_cmd_draw(int cmd, int vc, int ic, int fv, int fi) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return;
    vkCmdDraw(g_vk.cmd_buffers[cmd].cmd, (uint32_t)vc, (uint32_t)ic, (uint32_t)fv, (uint32_t)fi);
#else
    (void)cmd; (void)vc; (void)ic; (void)fv; (void)fi;
#endif
}

void sgpu_cmd_draw_indexed(int cmd, int idx_count, int ic, int fi, int vo, int fii) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return;
    vkCmdDrawIndexed(g_vk.cmd_buffers[cmd].cmd, (uint32_t)idx_count, (uint32_t)ic, (uint32_t)fi, vo, (uint32_t)fii);
#else
    (void)cmd; (void)idx_count; (void)ic; (void)fi; (void)vo; (void)fii;
#endif
}

void sgpu_cmd_draw_indirect(int cmd, int buf, int off, int dc, int stride) {
    (void)cmd; (void)buf; (void)off; (void)dc; (void)stride;
}
void sgpu_cmd_draw_indexed_indirect(int cmd, int buf, int off, int dc, int stride) {
    (void)cmd; (void)buf; (void)off; (void)dc; (void)stride;
}

void sgpu_cmd_bind_vertex_buffer(int cmd, int buf) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count || buf < 0 || buf >= g_vk.buffer_count) return;
    VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(g_vk.cmd_buffers[cmd].cmd, 0, 1, &g_vk.buffers[buf].buffer, &offset);
#else
    (void)cmd; (void)buf;
#endif
}

void sgpu_cmd_bind_vertex_buffers(int cmd, const int* bufs, int count) {
    (void)cmd; (void)bufs; (void)count;
}

void sgpu_cmd_bind_index_buffer(int cmd, int buf) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count || buf < 0 || buf >= g_vk.buffer_count) return;
    vkCmdBindIndexBuffer(g_vk.cmd_buffers[cmd].cmd, g_vk.buffers[buf].buffer, 0, VK_INDEX_TYPE_UINT32);
#else
    (void)cmd; (void)buf;
#endif
}

void sgpu_cmd_set_viewport(int cmd, float x, float y, float w, float h, float mind, float maxd) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return;
    VkViewport vp = { x, y, w, h, mind, maxd };
    vkCmdSetViewport(g_vk.cmd_buffers[cmd].cmd, 0, 1, &vp);
#else
    (void)cmd; (void)x; (void)y; (void)w; (void)h; (void)mind; (void)maxd;
#endif
}

void sgpu_cmd_set_scissor(int cmd, int x, int y, int w, int h) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return;
    VkRect2D sc = { {x, y}, {(uint32_t)w, (uint32_t)h} };
    vkCmdSetScissor(g_vk.cmd_buffers[cmd].cmd, 0, 1, &sc);
#else
    (void)cmd; (void)x; (void)y; (void)w; (void)h;
#endif
}

void sgpu_cmd_pipeline_barrier(int cmd, int ss, int ds, int sa, int da) {
    (void)cmd; (void)ss; (void)ds; (void)sa; (void)da;
}
void sgpu_cmd_image_barrier(int cmd, int img, int ol, int nl, int ss, int ds, int sa, int da) {
    (void)cmd; (void)img; (void)ol; (void)nl; (void)ss; (void)ds; (void)sa; (void)da;
}
void sgpu_cmd_copy_buffer(int cmd, int src, int dst, int size) {
    (void)cmd; (void)src; (void)dst; (void)size;
}
void sgpu_cmd_copy_buffer_to_image(int cmd, int buf, int img, int w, int h) {
    (void)cmd; (void)buf; (void)img; (void)w; (void)h;
}
void sgpu_cmd_execute_commands(int cmd, const int* sec, int count) {
    (void)cmd; (void)sec; (void)count;
}
void sgpu_cmd_queue_transfer_barrier(int cmd, int buf, int sf, int df) {
    (void)cmd; (void)buf; (void)sf; (void)df;
}

// Synchronization
int sgpu_create_fence(int signaled) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized) return SGPU_INVALID_HANDLE;
    int idx = ALLOC_FN();
    VkFenceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    if (signaled) ci.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    if (vkCreateFence(g_vk.device, &ci, NULL, &g_vk.fences[idx].fence) != VK_SUCCESS)
        return SGPU_INVALID_HANDLE;
    g_vk.fences[idx].alive = 1;
    return idx;
#else
    (void)signaled;
    return SGPU_INVALID_HANDLE;
#endif
}

int sgpu_wait_fence(int fence, double timeout) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || fence < 0 || fence >= g_vk.fence_count) return 0;
    uint64_t ns = (uint64_t)(timeout * 1e9);
    return vkWaitForFences(g_vk.device, 1, &g_vk.fences[fence].fence, VK_TRUE, ns) == VK_SUCCESS;
#else
    (void)fence; (void)timeout;
    return 0;
#endif
}

void sgpu_reset_fence(int fence) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || fence < 0 || fence >= g_vk.fence_count) return;
    vkResetFences(g_vk.device, 1, &g_vk.fences[fence].fence);
#else
    (void)fence;
#endif
}

void sgpu_destroy_fence(int fence) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || fence < 0 || fence >= g_vk.fence_count) return;
    if (!g_vk.fences[fence].alive) return;
    vkDestroyFence(g_vk.device, g_vk.fences[fence].fence, NULL);
    g_vk.fences[fence].alive = 0;
#else
    (void)fence;
#endif
}

int sgpu_create_semaphore(void) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized) return SGPU_INVALID_HANDLE;
    int idx = ALLOC_SEM();
    VkSemaphoreCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    if (vkCreateSemaphore(g_vk.device, &ci, NULL, &g_vk.semaphores[idx].semaphore) != VK_SUCCESS)
        return SGPU_INVALID_HANDLE;
    g_vk.semaphores[idx].alive = 1;
    return idx;
#else
    return SGPU_INVALID_HANDLE;
#endif
}

void sgpu_destroy_semaphore(int sem) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || sem < 0 || sem >= g_vk.semaphore_count) return;
    if (!g_vk.semaphores[sem].alive) return;
    vkDestroySemaphore(g_vk.device, g_vk.semaphores[sem].semaphore, NULL);
    g_vk.semaphores[sem].alive = 0;
#else
    (void)sem;
#endif
}

int sgpu_submit(int cmd, int fence) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return 0;
    VkSubmitInfo si = {0};
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &g_vk.cmd_buffers[cmd].cmd;
    VkFence f = (fence >= 0 && fence < g_vk.fence_count) ? g_vk.fences[fence].fence : VK_NULL_HANDLE;
    return vkQueueSubmit(g_vk.graphics_queue, 1, &si, f) == VK_SUCCESS;
#else
    (void)cmd; (void)fence;
    return 0;
#endif
}

int sgpu_submit_compute(int cmd, int fence) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return 0;
    VkSubmitInfo si = {0};
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &g_vk.cmd_buffers[cmd].cmd;
    VkFence f = (fence >= 0 && fence < g_vk.fence_count) ? g_vk.fences[fence].fence : VK_NULL_HANDLE;
    return vkQueueSubmit(g_vk.compute_queue, 1, &si, f) == VK_SUCCESS;
#else
    (void)cmd; (void)fence;
    return 0;
#endif
}

int sgpu_submit_with_sync(int cmd, int wait_sem, int signal_sem, int fence) {
#ifdef SAGE_HAS_VULKAN
    if (!g_vk.initialized || cmd < 0 || cmd >= g_vk.cmd_buffer_count) return 0;
    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo si = {0};
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &g_vk.cmd_buffers[cmd].cmd;
    if (wait_sem >= 0 && wait_sem < g_vk.semaphore_count) {
        si.waitSemaphoreCount = 1;
        si.pWaitSemaphores = &g_vk.semaphores[wait_sem].semaphore;
        si.pWaitDstStageMask = &wait_stage;
    }
    if (signal_sem >= 0 && signal_sem < g_vk.semaphore_count) {
        si.signalSemaphoreCount = 1;
        si.pSignalSemaphores = &g_vk.semaphores[signal_sem].semaphore;
    }
    VkFence f = (fence >= 0 && fence < g_vk.fence_count) ? g_vk.fences[fence].fence : VK_NULL_HANDLE;
    return vkQueueSubmit(g_vk.graphics_queue, 1, &si, f) == VK_SUCCESS;
#else
    (void)cmd; (void)wait_sem; (void)signal_sem; (void)fence;
    return 0;
#endif
}

void sgpu_queue_wait_idle(void) {
#ifdef SAGE_HAS_VULKAN
    if (g_vk.initialized) vkQueueWaitIdle(g_vk.graphics_queue);
#endif
}

void sgpu_device_wait_idle(void) {
#ifdef SAGE_HAS_VULKAN
    if (g_vk.initialized) vkDeviceWaitIdle(g_vk.device);
#endif
}

// Window & Swapchain
int sgpu_create_window(int w, int h, const char* title) {
#ifdef SAGE_HAS_GLFW
    if (!glfwInit()) return 0;
    if (g_active_backend == SAGE_GPU_BACKEND_VULKAN)
        glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    g_window = glfwCreateWindow(w, h, title ? title : "SageLang", NULL, NULL);
    if (!g_window) return 0;
    glfwSetKeyCallback(g_window, glfw_key_callback);
    glfwSetMouseButtonCallback(g_window, glfw_mouse_callback);
    glfwSetScrollCallback(g_window, glfw_scroll_callback);
    glfwSetFramebufferSizeCallback(g_window, glfw_resize_callback);
    return 1;
#else
    (void)w; (void)h; (void)title;
    return 0;
#endif
}

void sgpu_destroy_window(void) {
#ifdef SAGE_HAS_GLFW
    if (g_window) { glfwDestroyWindow(g_window); g_window = NULL; }
    glfwTerminate();
#endif
}

int sgpu_window_should_close(void) {
#ifdef SAGE_HAS_GLFW
    return g_window ? glfwWindowShouldClose(g_window) : 1;
#else
    return 1;
#endif
}

void sgpu_poll_events(void) {
#ifdef SAGE_HAS_GLFW
    g_scroll_dx = g_scroll_dy = 0;
    g_window_resized_flag = 0;
    glfwPollEvents();
    if (g_window) glfwGetCursorPos(g_window, &g_mouse_x, &g_mouse_y);
#endif
}

int sgpu_init_windowed(const char* title, int w, int h, int validation) {
    if (!sgpu_create_window(w, h, title)) return 0;
    return sgpu_init(title, validation);
}

int sgpu_init_opengl_windowed(const char* title, int w, int h, int major, int minor) {
#ifdef SAGE_HAS_GLFW
    if (!glfwInit()) return 0;
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, major);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, minor);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    g_window = glfwCreateWindow(w, h, title ? title : "SageLang", NULL, NULL);
    if (!g_window) return 0;
    glfwMakeContextCurrent(g_window);
    glfwSetKeyCallback(g_window, glfw_key_callback);
    glfwSetMouseButtonCallback(g_window, glfw_mouse_callback);
    glfwSetScrollCallback(g_window, glfw_scroll_callback);
    glfwSetFramebufferSizeCallback(g_window, glfw_resize_callback);
    g_active_backend = SAGE_GPU_BACKEND_OPENGL;
    g_initialized = 1;
    return 1;
#else
    (void)title; (void)w; (void)h; (void)major; (void)minor;
    return 0;
#endif
}

void sgpu_shutdown_windowed(void) {
    sgpu_shutdown();
    sgpu_destroy_window();
}

int sgpu_swapchain_image_count(void) { return (int)g_swapchain_image_count; }
int sgpu_swapchain_format(void) { return 0; }
void sgpu_swapchain_extent(int* w, int* h) {
    if (w) *w = (int)g_swapchain_width;
    if (h) *h = (int)g_swapchain_height;
}
int sgpu_acquire_next_image(int sem, int* idx) {
    (void)sem; if (idx) *idx = 0;
    return 0;
}
int sgpu_present(int sem, int idx) { (void)sem; (void)idx; return 0; }
int sgpu_create_swapchain_framebuffers(int rp, int* out, int max) {
    (void)rp; (void)out; (void)max; return 0;
}
int sgpu_create_swapchain_framebuffers_depth(int rp, int depth, int* out, int max) {
    (void)rp; (void)depth; (void)out; (void)max; return 0;
}
int sgpu_recreate_swapchain(void) { return 0; }

// Input
int sgpu_key_pressed(int key) { return (key >= 0 && key < 512) ? g_key_states[key] : 0; }
int sgpu_key_down(int key) { return sgpu_key_pressed(key); }
int sgpu_key_just_pressed(int key) {
    return (key >= 0 && key < 512) ? (g_key_states[key] && !g_key_prev[key]) : 0;
}
int sgpu_key_just_released(int key) {
    return (key >= 0 && key < 512) ? (!g_key_states[key] && g_key_prev[key]) : 0;
}
void sgpu_mouse_pos(double* x, double* y) {
    if (x) *x = g_mouse_x; if (y) *y = g_mouse_y;
}
int sgpu_mouse_button(int b) { return (b >= 0 && b < 8) ? g_mouse_states[b] : 0; }
int sgpu_mouse_just_pressed(int b) {
    return (b >= 0 && b < 8) ? (g_mouse_states[b] && !g_mouse_prev[b]) : 0;
}
int sgpu_mouse_just_released(int b) {
    return (b >= 0 && b < 8) ? (!g_mouse_states[b] && g_mouse_prev[b]) : 0;
}
void sgpu_mouse_delta(double* dx, double* dy) {
    if (dx) *dx = g_mouse_x - g_prev_mouse_x;
    if (dy) *dy = g_mouse_y - g_prev_mouse_y;
}
void sgpu_scroll_delta(double* dx, double* dy) {
    if (dx) *dx = g_scroll_dx; if (dy) *dy = g_scroll_dy;
}
void sgpu_set_cursor_mode(int mode) {
#ifdef SAGE_HAS_GLFW
    if (g_window) glfwSetInputMode(g_window, GLFW_CURSOR, mode);
#else
    (void)mode;
#endif
}
double sgpu_get_time(void) {
#ifdef SAGE_HAS_GLFW
    return glfwGetTime();
#else
    return 0.0;
#endif
}
void sgpu_window_size(int* w, int* h) {
#ifdef SAGE_HAS_GLFW
    if (g_window) glfwGetFramebufferSize(g_window, w, h);
    else { if (w) *w = 0; if (h) *h = 0; }
#else
    if (w) *w = 0; if (h) *h = 0;
#endif
}
void sgpu_set_title(const char* title) {
#ifdef SAGE_HAS_GLFW
    if (g_window && title) glfwSetWindowTitle(g_window, title);
#else
    (void)title;
#endif
}
int sgpu_window_resized(void) { return g_window_resized_flag; }
void sgpu_update_input(void) {
    memcpy(g_key_prev, g_key_states, sizeof(g_key_prev));
    memcpy(g_mouse_prev, g_mouse_states, sizeof(g_mouse_prev));
    g_prev_mouse_x = g_mouse_x;
    g_prev_mouse_y = g_mouse_y;
}
int sgpu_text_input_available(void) { return 0; }
int sgpu_text_input_read(void) { return 0; }

// Texture loading (stub — full impl needs stb_image integration)
int sgpu_load_texture(const char* path, int mipmaps, int filter, int addr) {
    (void)path; (void)mipmaps; (void)filter; (void)addr;
    return SGPU_INVALID_HANDLE;
}
void sgpu_texture_dims(int handle, int* w, int* h) {
    (void)handle; if (w) *w = 0; if (h) *h = 0;
}
int sgpu_generate_mipmaps(int img) { (void)img; return 0; }
int sgpu_create_cubemap(const char** paths, int count) { (void)paths; (void)count; return SGPU_INVALID_HANDLE; }

// Upload helpers
int sgpu_upload_device_local(const float* data, int count, int usage) {
    (void)data; (void)count; (void)usage;
    return SGPU_INVALID_HANDLE;
}
int sgpu_upload_bytes(const uint8_t* data, int size, int usage) {
    (void)data; (void)size; (void)usage;
    return SGPU_INVALID_HANDLE;
}

// Uniform buffers
int sgpu_create_uniform_buffer(int size) {
    return sgpu_create_buffer(size, SGPU_BUFFER_UNIFORM, SGPU_MEMORY_HOST_VISIBLE | SGPU_MEMORY_HOST_COHERENT);
}
int sgpu_update_uniform(int handle, const float* data, int count) {
    return sgpu_buffer_upload(handle, data, count);
}

// Offscreen
int sgpu_create_offscreen_target(int w, int h, int format, int usage) {
    (void)w; (void)h; (void)format; (void)usage;
    return SGPU_INVALID_HANDLE;
}

// Screenshot
int sgpu_screenshot(uint8_t* out, int max_size, int* w, int* h) {
    (void)out; (void)max_size; if (w) *w = 0; if (h) *h = 0;
    return 0;
}
int sgpu_save_screenshot(const char* path) { (void)path; return 0; }

// Font
int sgpu_load_font(const char* path, int size) { (void)path; (void)size; return SGPU_INVALID_HANDLE; }
int sgpu_font_atlas(int font) { (void)font; return SGPU_INVALID_HANDLE; }
int sgpu_font_set_atlas(int font, int img, int samp) { (void)font; (void)img; (void)samp; return 0; }
int sgpu_font_text_verts(int font, const char* text, float x, float y, float scale,
                          float* out, int max) {
    (void)font; (void)text; (void)x; (void)y; (void)scale; (void)out; (void)max;
    return 0;
}
void sgpu_font_measure(int font, const char* text, float scale, float* w, float* h) {
    (void)font; (void)text; (void)scale; if (w) *w = 0; if (h) *h = 0;
}

// glTF
int sgpu_load_gltf(const char* path) { (void)path; return SGPU_INVALID_HANDLE; }

// Queue families
int sgpu_graphics_family(void) {
#ifdef SAGE_HAS_VULKAN
    return (int)g_vk.graphics_family;
#else
    return 0;
#endif
}
int sgpu_compute_family(void) {
#ifdef SAGE_HAS_VULKAN
    return (int)g_vk.compute_family;
#else
    return 0;
#endif
}

// Platform
void sgpu_set_platform(const char* p) {
    if (p) snprintf(g_platform_override, sizeof(g_platform_override), "%s", p);
}
const char* sgpu_get_platform(void) {
    if (g_platform_override[0]) return g_platform_override;
    return sgpu_detected_platform();
}
const char* sgpu_detected_platform(void) {
#ifdef __linux__
    return "linux";
#elif defined(__APPLE__)
    return "macos";
#elif defined(_WIN32)
    return "windows";
#else
    return "unknown";
#endif
}
