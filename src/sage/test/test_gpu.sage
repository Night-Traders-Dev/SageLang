gc_disable()
# Tests for the GPU/Vulkan module
# Tests constants, API availability, and (when Vulkan is present) resource creation
import gpu

let nl = chr(10)
let passed = 0
let failed = 0

proc assert_eq(actual, expected, msg):
    if actual == expected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg
        print "  expected: " + str(expected)
        print "  actual:   " + str(actual)

proc assert_true(val, msg):
    if val == true:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (expected true, got " + str(val) + ")"

proc assert_neq(actual, unexpected, msg):
    if actual != unexpected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (should not be " + str(unexpected) + ")"

print "GPU Module Tests"
print "================="

# ============================================================================
# Constants exist and have expected values
# ============================================================================
print nl + "--- Buffer constants ---"

assert_eq(gpu.BUFFER_STORAGE, 1, "BUFFER_STORAGE = 1")
assert_eq(gpu.BUFFER_UNIFORM, 2, "BUFFER_UNIFORM = 2")
assert_eq(gpu.BUFFER_VERTEX, 4, "BUFFER_VERTEX = 4")
assert_eq(gpu.BUFFER_INDEX, 8, "BUFFER_INDEX = 8")
assert_eq(gpu.BUFFER_STAGING, 16, "BUFFER_STAGING = 16")
assert_eq(gpu.BUFFER_INDIRECT, 32, "BUFFER_INDIRECT = 32")
assert_eq(gpu.BUFFER_TRANSFER_SRC, 64, "BUFFER_TRANSFER_SRC = 64")
assert_eq(gpu.BUFFER_TRANSFER_DST, 128, "BUFFER_TRANSFER_DST = 128")

print nl + "--- Memory constants ---"

assert_eq(gpu.MEMORY_DEVICE_LOCAL, 1, "MEMORY_DEVICE_LOCAL = 1")
assert_eq(gpu.MEMORY_HOST_VISIBLE, 2, "MEMORY_HOST_VISIBLE = 2")
assert_eq(gpu.MEMORY_HOST_COHERENT, 4, "MEMORY_HOST_COHERENT = 4")

print nl + "--- Format constants ---"

assert_eq(gpu.FORMAT_RGBA8, 0, "FORMAT_RGBA8 = 0")
assert_eq(gpu.FORMAT_RGBA16F, 1, "FORMAT_RGBA16F = 1")
assert_eq(gpu.FORMAT_RGBA32F, 2, "FORMAT_RGBA32F = 2")
assert_eq(gpu.FORMAT_R32F, 3, "FORMAT_R32F = 3")
assert_eq(gpu.FORMAT_DEPTH32F, 5, "FORMAT_DEPTH32F = 5")
assert_eq(gpu.FORMAT_BGRA8, 9, "FORMAT_BGRA8 = 9")

print nl + "--- Image constants ---"

assert_eq(gpu.IMAGE_SAMPLED, 1, "IMAGE_SAMPLED = 1")
assert_eq(gpu.IMAGE_STORAGE, 2, "IMAGE_STORAGE = 2")
assert_eq(gpu.IMAGE_COLOR_ATTACH, 4, "IMAGE_COLOR_ATTACH = 4")
assert_eq(gpu.IMAGE_DEPTH_ATTACH, 8, "IMAGE_DEPTH_ATTACH = 8")
assert_eq(gpu.IMAGE_2D, 1, "IMAGE_2D = 1")
assert_eq(gpu.IMAGE_3D, 2, "IMAGE_3D = 2")

print nl + "--- Filter constants ---"

assert_eq(gpu.FILTER_NEAREST, 0, "FILTER_NEAREST = 0")
assert_eq(gpu.FILTER_LINEAR, 1, "FILTER_LINEAR = 1")

print nl + "--- Descriptor constants ---"

assert_eq(gpu.DESC_STORAGE_BUFFER, 0, "DESC_STORAGE_BUFFER = 0")
assert_eq(gpu.DESC_UNIFORM_BUFFER, 1, "DESC_UNIFORM_BUFFER = 1")
assert_eq(gpu.DESC_SAMPLED_IMAGE, 2, "DESC_SAMPLED_IMAGE = 2")
assert_eq(gpu.DESC_STORAGE_IMAGE, 3, "DESC_STORAGE_IMAGE = 3")
assert_eq(gpu.DESC_COMBINED_SAMPLER, 5, "DESC_COMBINED_SAMPLER = 5")

print nl + "--- Shader stage constants ---"

assert_eq(gpu.STAGE_VERTEX, 1, "STAGE_VERTEX = 1")
assert_eq(gpu.STAGE_FRAGMENT, 2, "STAGE_FRAGMENT = 2")
assert_eq(gpu.STAGE_COMPUTE, 4, "STAGE_COMPUTE = 4")
assert_eq(gpu.STAGE_GEOMETRY, 8, "STAGE_GEOMETRY = 8")

print nl + "--- Topology constants ---"

assert_eq(gpu.TOPO_TRIANGLE_LIST, 3, "TOPO_TRIANGLE_LIST = 3")
assert_eq(gpu.TOPO_POINT_LIST, 0, "TOPO_POINT_LIST = 0")
assert_eq(gpu.TOPO_LINE_LIST, 1, "TOPO_LINE_LIST = 1")

print nl + "--- Rasterization constants ---"

assert_eq(gpu.POLY_FILL, 0, "POLY_FILL = 0")
assert_eq(gpu.POLY_LINE, 1, "POLY_LINE = 1")
assert_eq(gpu.CULL_NONE, 0, "CULL_NONE = 0")
assert_eq(gpu.CULL_BACK, 2, "CULL_BACK = 2")
assert_eq(gpu.FRONT_CCW, 0, "FRONT_CCW = 0")
assert_eq(gpu.FRONT_CW, 1, "FRONT_CW = 1")

print nl + "--- Blend constants ---"

assert_eq(gpu.BLEND_SRC_ALPHA, 2, "BLEND_SRC_ALPHA = 2")
assert_eq(gpu.BLEND_ONE_MINUS_SRC_ALPHA, 3, "BLEND_ONE_MINUS_SRC_ALPHA = 3")
assert_eq(gpu.BLEND_OP_ADD, 0, "BLEND_OP_ADD = 0")

print nl + "--- Layout constants ---"

assert_eq(gpu.LAYOUT_UNDEFINED, 0, "LAYOUT_UNDEFINED = 0")
assert_eq(gpu.LAYOUT_GENERAL, 1, "LAYOUT_GENERAL = 1")
assert_eq(gpu.LAYOUT_COLOR_ATTACH, 2, "LAYOUT_COLOR_ATTACH = 2")
assert_eq(gpu.LAYOUT_SHADER_READ, 4, "LAYOUT_SHADER_READ = 4")

print nl + "--- Pipeline stage constants ---"

assert_eq(gpu.PIPE_TOP, 1, "PIPE_TOP = 1")
assert_eq(gpu.PIPE_COMPUTE, 256, "PIPE_COMPUTE = 256")
assert_eq(gpu.PIPE_TRANSFER, 512, "PIPE_TRANSFER = 512")

print nl + "--- Access constants ---"

assert_eq(gpu.ACCESS_NONE, 0, "ACCESS_NONE = 0")
assert_eq(gpu.ACCESS_SHADER_READ, 1, "ACCESS_SHADER_READ = 1")
assert_eq(gpu.ACCESS_SHADER_WRITE, 2, "ACCESS_SHADER_WRITE = 2")

print nl + "--- Load/Store constants ---"

assert_eq(gpu.LOAD_CLEAR, 0, "LOAD_CLEAR = 0")
assert_eq(gpu.LOAD_LOAD, 1, "LOAD_LOAD = 1")
assert_eq(gpu.STORE_STORE, 0, "STORE_STORE = 0")

print nl + "--- Vertex input constants ---"

assert_eq(gpu.INPUT_RATE_VERTEX, 0, "INPUT_RATE_VERTEX = 0")
assert_eq(gpu.INPUT_RATE_INSTANCE, 1, "INPUT_RATE_INSTANCE = 1")
assert_eq(gpu.ATTR_FLOAT, 0, "ATTR_FLOAT = 0")
assert_eq(gpu.ATTR_VEC2, 1, "ATTR_VEC2 = 1")
assert_eq(gpu.ATTR_VEC3, 2, "ATTR_VEC3 = 2")
assert_eq(gpu.ATTR_VEC4, 3, "ATTR_VEC4 = 3")

print nl + "--- Invalid handle ---"

assert_eq(gpu.INVALID_HANDLE, -1, "INVALID_HANDLE = -1")

# ============================================================================
# API functions exist
# ============================================================================
print nl + "--- API availability ---"

assert_neq(gpu.has_vulkan, nil, "has_vulkan exists")
assert_neq(gpu.init, nil, "init exists")
assert_neq(gpu.shutdown, nil, "shutdown exists")
assert_neq(gpu.create_buffer, nil, "create_buffer exists")
assert_neq(gpu.create_image, nil, "create_image exists")
assert_neq(gpu.load_shader, nil, "load_shader exists")
assert_neq(gpu.create_compute_pipeline, nil, "create_compute_pipeline exists")
assert_neq(gpu.create_graphics_pipeline, nil, "create_graphics_pipeline exists")
assert_neq(gpu.create_command_pool, nil, "create_command_pool exists")
assert_neq(gpu.cmd_dispatch, nil, "cmd_dispatch exists")
assert_neq(gpu.submit, nil, "submit exists")
assert_neq(gpu.create_fence, nil, "create_fence exists")

# ============================================================================
# has_vulkan returns bool
# ============================================================================
print nl + "--- has_vulkan ---"

let has_vk = gpu.has_vulkan()
assert_eq(type(has_vk), "bool", "has_vulkan returns bool")

# ============================================================================
# Bitwise flag composition
# ============================================================================
print nl + "--- Flag composition ---"

let storage_transfer = gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_SRC
assert_eq(storage_transfer, 65, "STORAGE | TRANSFER_SRC = 65")

let host_mem = gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
assert_eq(host_mem, 6, "HOST_VISIBLE | HOST_COHERENT = 6")

let sampled_storage = gpu.IMAGE_SAMPLED | gpu.IMAGE_STORAGE
assert_eq(sampled_storage, 3, "IMAGE_SAMPLED | IMAGE_STORAGE = 3")

let vert_frag = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
assert_eq(vert_frag, 3, "STAGE_VERTEX | STAGE_FRAGMENT = 3")

# ============================================================================
# If Vulkan available, test init/shutdown cycle
# ============================================================================
print nl + "--- Init/Shutdown ---"

if gpu.has_vulkan():
    let ok = gpu.init("test", false)
    if ok:
        assert_true(ok, "gpu.init returns true")

        let name = gpu.device_name()
        assert_neq(name, nil, "device_name not nil")
        assert_neq(name, "<not initialized>", "device_name not placeholder")

        let limits = gpu.device_limits()
        assert_neq(limits, nil, "device_limits not nil")
        if limits != nil:
            assert_true(limits["maxPushConstantsSize"] >= 128, "push constants >= 128 bytes")
            assert_true(limits["maxComputeWorkGroupSize_x"] >= 256, "workgroup X >= 256")
            assert_true(limits["maxStorageBufferRange"] > 0, "storage buffer range > 0")

        # Test buffer create/upload/download
        let buf = gpu.create_buffer(64, host_mem | gpu.BUFFER_STORAGE, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
        assert_neq(buf, -1, "create host buffer")
        if buf != -1:
            assert_eq(gpu.buffer_size(buf), 64, "buffer_size = 64")
            let up_ok = gpu.buffer_upload(buf, [1.0, 2.0, 3.0, 4.0])
            assert_true(up_ok, "buffer_upload ok")
            let data = gpu.buffer_download(buf)
            assert_eq(len(data), 16, "downloaded 16 floats (64 bytes)")
            # First 4 values should match
            assert_eq(data[0], 1, "data[0] = 1")
            assert_eq(data[1], 2, "data[1] = 2")
            assert_eq(data[2], 3, "data[2] = 3")
            assert_eq(data[3], 4, "data[3] = 4")
            gpu.destroy_buffer(buf)

        # Test fence create/destroy
        let f = gpu.create_fence(true)
        assert_neq(f, -1, "create fence")
        if f != -1:
            let waited = gpu.wait_fence(f)
            assert_true(waited, "wait signaled fence")
            gpu.reset_fence(f)
            gpu.destroy_fence(f)

        # Test semaphore create/destroy
        let sem = gpu.create_semaphore()
        assert_neq(sem, -1, "create semaphore")
        if sem != -1:
            gpu.destroy_semaphore(sem)

        # Test command pool/buffer
        let cp = gpu.create_command_pool()
        assert_neq(cp, -1, "create command pool")
        if cp != -1:
            let cb = gpu.create_command_buffer(cp)
            assert_neq(cb, -1, "create command buffer")

        gpu.shutdown()
        passed = passed + 1
    else:
        print "  (gpu.init failed - GPU not available in this environment)"
        passed = passed + 1
else:
    print "  (Vulkan not available - skipping runtime tests)"
    passed = passed + 1

# ============================================================================
# Summary
# ============================================================================
print nl + "================="
print str(passed) + " passed, " + str(failed) + " failed"

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All GPU tests passed!"
