gc_disable()
# -----------------------------------------
# gpu.sage - High-level GPU compute & graphics helpers
# Phase 15: One-liner GPU operations for SageLang
#
# This module builds on lib/vulkan.sage to provide
# the simplest possible API for common GPU tasks.
#
# Usage:
#   import gpu as vk    # use the native module directly
#   from gpu import *   # not supported - use import
#
#   # Or use this high-level library:
#   import gpu_utils
#   gpu_utils.run_compute("shader.spv", input_data, output_size)
# -----------------------------------------

import gpu

# -----------------------------------------
# Quick compute dispatch
# Runs a compute shader on input data and returns output
#
# shader_path: path to .spv file
# input_data: array of floats for input buffer (binding 0)
# output_floats: number of output floats (binding 1)
# workgroup_x, y, z: dispatch dimensions
# push_data: optional push constants (array of floats)
#
# Returns: array of floats from output buffer
# -----------------------------------------
proc run_compute(shader_path, input_data, output_floats, wg_x, wg_y, wg_z):
    if gpu.has_vulkan() == false:
        print "gpu_utils: Vulkan not available"
        return []

    let input_size = len(input_data) * 4
    let output_size = output_floats * 4

    # Create resources
    let in_buf = gpu.create_buffer(input_size, gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)
    let out_buf = gpu.create_buffer(output_size, gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_SRC, gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT)

    # Upload input
    gpu.buffer_upload(in_buf, input_data)

    # Descriptor layout: binding 0 = input SSBO, binding 1 = output SSBO
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_STORAGE_BUFFER
    b0["stage"] = gpu.STAGE_COMPUTE
    b0["count"] = 1
    let b1 = {}
    b1["binding"] = 1
    b1["type"] = gpu.DESC_STORAGE_BUFFER
    b1["stage"] = gpu.STAGE_COMPUTE
    b1["count"] = 1
    let layout = gpu.create_descriptor_layout([b0, b1])

    # Pool and set
    let ps = {}
    ps["type"] = gpu.DESC_STORAGE_BUFFER
    ps["count"] = 2
    let pool = gpu.create_descriptor_pool(1, [ps])
    let desc = gpu.allocate_descriptor_set(pool, layout)

    # Bind buffers
    gpu.update_descriptor(desc, 0, gpu.DESC_STORAGE_BUFFER, in_buf)
    gpu.update_descriptor(desc, 1, gpu.DESC_STORAGE_BUFFER, out_buf)

    # Pipeline
    let sh = gpu.load_shader(shader_path, gpu.STAGE_COMPUTE)
    let pl = gpu.create_pipeline_layout([layout], 0)
    let pipe = gpu.create_compute_pipeline(pl, sh)

    # Command buffer
    let cmd_pool = gpu.create_command_pool()
    let cmd = gpu.create_command_buffer(cmd_pool)

    # Record
    gpu.begin_commands(cmd)
    gpu.cmd_bind_compute_pipeline(cmd, pipe)
    gpu.cmd_bind_descriptor_set(cmd, pl, 0, desc)
    gpu.cmd_dispatch(cmd, wg_x, wg_y, wg_z)
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_BOTTOM, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_HOST_READ)
    gpu.end_commands(cmd)

    # Submit and wait
    let fence = gpu.create_fence(false)
    gpu.submit_compute(cmd, nil, nil, fence)
    gpu.wait_fence(fence)

    # Download result
    let result = gpu.buffer_download(out_buf)

    # Cleanup
    gpu.destroy_fence(fence)
    gpu.destroy_pipeline(pipe)
    gpu.destroy_shader(sh)
    gpu.destroy_buffer(in_buf)
    gpu.destroy_buffer(out_buf)

    return result

# -----------------------------------------
# GPU info printer
# -----------------------------------------
proc print_info():
    if gpu.has_vulkan() == false:
        print "Vulkan not available"
        return nil

    print "GPU: " + gpu.device_name()
    let lim = gpu.device_limits()
    if lim == nil:
        print "  (no limits available - call gpu.initialize first)"
        return nil
    print "  Max compute workgroup size: " + str(lim["maxComputeWorkGroupSize_x"]) + " x " + str(lim["maxComputeWorkGroupSize_y"]) + " x " + str(lim["maxComputeWorkGroupSize_z"])
    print "  Max compute invocations: " + str(lim["maxComputeWorkGroupInvocations"])
    print "  Max push constants: " + str(lim["maxPushConstantsSize"]) + " bytes"
    print "  Max storage buffer: " + str(lim["maxStorageBufferRange"]) + " bytes"
    print "  Max image 2D: " + str(lim["maxImageDimension2D"])
    print "  Max image 3D: " + str(lim["maxImageDimension3D"])
    print "  Max bound descriptor sets: " + str(lim["maxBoundDescriptorSets"])

# -----------------------------------------
# Double-buffer helper for ping-pong compute
# -----------------------------------------
proc create_ping_pong(size):
    let a = gpu.create_buffer(size, gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_SRC | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_DEVICE_LOCAL)
    let b = gpu.create_buffer(size, gpu.BUFFER_STORAGE | gpu.BUFFER_TRANSFER_SRC | gpu.BUFFER_TRANSFER_DST, gpu.MEMORY_DEVICE_LOCAL)
    let pp = {}
    pp["a"] = a
    pp["b"] = b
    pp["current"] = 0
    return pp

proc ping_pong_read(pp):
    if pp["current"] == 0:
        return pp["a"]
    return pp["b"]

proc ping_pong_write(pp):
    if pp["current"] == 0:
        return pp["b"]
    return pp["a"]

proc ping_pong_swap(pp):
    if pp["current"] == 0:
        pp["current"] = 1
    else:
        pp["current"] = 0

proc ping_pong_destroy(pp):
    gpu.destroy_buffer(pp["a"])
    gpu.destroy_buffer(pp["b"])
