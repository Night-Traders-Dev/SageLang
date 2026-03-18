gc_disable()
# -----------------------------------------
# vulkan.sage - Ergonomic Vulkan wrapper for SageLang
# Phase 15: Builder-pattern API over the native gpu module
#
# Usage:
#   import vulkan
#   vulkan.init("My App", true)
#   let buf = vulkan.buffer(1024, "storage")
#   let shader = vulkan.shader("compute.spv", "compute")
#   let pipe = vulkan.compute_pipeline(shader, [buf])
#   vulkan.dispatch(pipe, 256, 1, 1)
#   vulkan.shutdown()
# -----------------------------------------

import gpu

# -----------------------------------------
# Initialization
# -----------------------------------------
proc init(app_name, validation):
    return gpu.init(app_name, validation)

proc shutdown():
    return gpu.shutdown()

proc has_vulkan():
    return gpu.has_vulkan()

proc device_name():
    return gpu.device_name()

proc device_limits():
    return gpu.device_limits()

# -----------------------------------------
# Buffer helpers - friendly string-based API
# -----------------------------------------
proc parse_buffer_usage(usage_str):
    let flags = 0
    if contains(usage_str, "storage"):
        flags = flags | gpu.BUFFER_STORAGE
    if contains(usage_str, "uniform"):
        flags = flags | gpu.BUFFER_UNIFORM
    if contains(usage_str, "vertex"):
        flags = flags | gpu.BUFFER_VERTEX
    if contains(usage_str, "index"):
        flags = flags | gpu.BUFFER_INDEX
    if contains(usage_str, "staging"):
        flags = flags | gpu.BUFFER_STAGING
    if contains(usage_str, "indirect"):
        flags = flags | gpu.BUFFER_INDIRECT
    if contains(usage_str, "transfer_src"):
        flags = flags | gpu.BUFFER_TRANSFER_SRC
    if contains(usage_str, "transfer_dst"):
        flags = flags | gpu.BUFFER_TRANSFER_DST
    if flags == 0:
        flags = gpu.BUFFER_STORAGE
    return flags

proc parse_memory(mem_str):
    if contains(mem_str, "host"):
        return gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
    if contains(mem_str, "staging"):
        return gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
    return gpu.MEMORY_DEVICE_LOCAL

# buffer(size, usage_str, memory_str?) -> handle
# usage_str: "storage", "uniform", "vertex", "index", "staging", or combinations
# memory_str: "device" (default), "host" (host-visible+coherent)
proc buffer(size, usage_str):
    let mem_str = "device"
    if contains(usage_str, "staging"):
        mem_str = "host"
    if contains(usage_str, "host"):
        mem_str = "host"
    let usage = parse_buffer_usage(usage_str)
    let mem = parse_memory(mem_str)
    return gpu.create_buffer(size, usage, mem)

proc host_buffer(size, usage_str):
    let usage = parse_buffer_usage(usage_str)
    let mem = gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
    return gpu.create_buffer(size, usage, mem)

proc staging_buffer(size):
    let usage = gpu.BUFFER_STAGING | gpu.BUFFER_TRANSFER_SRC
    let mem = gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
    return gpu.create_buffer(size, usage, mem)

proc upload(buf_handle, data):
    return gpu.buffer_upload(buf_handle, data)

proc download(buf_handle):
    return gpu.buffer_download(buf_handle)

# -----------------------------------------
# Image helpers
# -----------------------------------------
proc parse_format(fmt_str):
    if fmt_str == "rgba8":
        return gpu.FORMAT_RGBA8
    if fmt_str == "rgba16f":
        return gpu.FORMAT_RGBA16F
    if fmt_str == "rgba32f":
        return gpu.FORMAT_RGBA32F
    if fmt_str == "r32f":
        return gpu.FORMAT_R32F
    if fmt_str == "rg32f":
        return gpu.FORMAT_RG32F
    if fmt_str == "depth32f":
        return gpu.FORMAT_DEPTH32F
    if fmt_str == "depth24_s8":
        return gpu.FORMAT_DEPTH24_S8
    if fmt_str == "r8":
        return gpu.FORMAT_R8
    if fmt_str == "bgra8":
        return gpu.FORMAT_BGRA8
    if fmt_str == "r32u":
        return gpu.FORMAT_R32U
    if fmt_str == "rg16f":
        return gpu.FORMAT_RG16F
    if fmt_str == "r16f":
        return gpu.FORMAT_R16F
    return gpu.FORMAT_RGBA8

proc parse_image_usage(usage_str):
    let flags = 0
    if contains(usage_str, "sampled"):
        flags = flags | gpu.IMAGE_SAMPLED
    if contains(usage_str, "storage"):
        flags = flags | gpu.IMAGE_STORAGE
    if contains(usage_str, "color"):
        flags = flags | gpu.IMAGE_COLOR_ATTACH
    if contains(usage_str, "depth"):
        flags = flags | gpu.IMAGE_DEPTH_ATTACH
    if contains(usage_str, "transfer_src"):
        flags = flags | gpu.IMAGE_TRANSFER_SRC
    if contains(usage_str, "transfer_dst"):
        flags = flags | gpu.IMAGE_TRANSFER_DST
    if flags == 0:
        flags = gpu.IMAGE_SAMPLED
    return flags

# image2d(w, h, format_str, usage_str) -> handle
proc image2d(w, h, fmt_str, usage_str):
    let fmt = parse_format(fmt_str)
    let usage = parse_image_usage(usage_str)
    return gpu.create_image(w, h, 1, fmt, usage)

# image3d(w, h, d, format_str, usage_str) -> handle
proc image3d(w, h, d, fmt_str, usage_str):
    let fmt = parse_format(fmt_str)
    let usage = parse_image_usage(usage_str)
    return gpu.create_image(w, h, d, fmt, usage)

# storage_image(w, h, format_str?) -> handle
proc storage_image(w, h, fmt_str):
    let fmt = parse_format(fmt_str)
    return gpu.create_image(w, h, 1, fmt, gpu.IMAGE_STORAGE | gpu.IMAGE_SAMPLED)

# -----------------------------------------
# Sampler helpers
# -----------------------------------------
proc sampler_nearest():
    return gpu.create_sampler(gpu.FILTER_NEAREST, gpu.FILTER_NEAREST, gpu.ADDRESS_CLAMP_EDGE)

proc sampler_linear():
    return gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_REPEAT)

proc sampler(mag, mn, addr):
    return gpu.create_sampler(mag, mn, addr)

# -----------------------------------------
# Shader loading
# -----------------------------------------
proc shader(path, stage_str):
    let stage = gpu.STAGE_COMPUTE
    if stage_str == "vertex":
        stage = gpu.STAGE_VERTEX
    if stage_str == "fragment":
        stage = gpu.STAGE_FRAGMENT
    if stage_str == "geometry":
        stage = gpu.STAGE_GEOMETRY
    return gpu.load_shader(path, stage)

# -----------------------------------------
# Descriptor layout builder
# -----------------------------------------
# binding_desc(index, type_str, stage_str) -> dict
proc binding_desc(index, type_str, stage_str):
    let b = {}
    b["binding"] = index

    if type_str == "storage":
        b["type"] = gpu.DESC_STORAGE_BUFFER
    if type_str == "uniform":
        b["type"] = gpu.DESC_UNIFORM_BUFFER
    if type_str == "sampled_image":
        b["type"] = gpu.DESC_SAMPLED_IMAGE
    if type_str == "storage_image":
        b["type"] = gpu.DESC_STORAGE_IMAGE
    if type_str == "combined_sampler":
        b["type"] = gpu.DESC_COMBINED_SAMPLER
    if dict_has(b, "type") == false:
        b["type"] = gpu.DESC_STORAGE_BUFFER

    if stage_str == "compute":
        b["stage"] = gpu.STAGE_COMPUTE
    if stage_str == "vertex":
        b["stage"] = gpu.STAGE_VERTEX
    if stage_str == "fragment":
        b["stage"] = gpu.STAGE_FRAGMENT
    if stage_str == "all":
        b["stage"] = gpu.STAGE_ALL
    if dict_has(b, "stage") == false:
        b["stage"] = gpu.STAGE_ALL

    b["count"] = 1
    return b

# desc_layout(bindings_array) -> handle
proc desc_layout(bindings):
    return gpu.create_descriptor_layout(bindings)

# desc_pool(max_sets, sizes_array) -> handle
# sizes: [{type: "storage", count: 10}, ...]
proc desc_pool(max_sets, sizes):
    let vk_sizes = []
    let i = 0
    while i < len(sizes):
        let s = sizes[i]
        let vs = {}
        let t = s["type"]
        if t == "storage":
            vs["type"] = gpu.DESC_STORAGE_BUFFER
        if t == "uniform":
            vs["type"] = gpu.DESC_UNIFORM_BUFFER
        if t == "sampled_image":
            vs["type"] = gpu.DESC_SAMPLED_IMAGE
        if t == "storage_image":
            vs["type"] = gpu.DESC_STORAGE_IMAGE
        if t == "combined_sampler":
            vs["type"] = gpu.DESC_COMBINED_SAMPLER
        if dict_has(vs, "type") == false:
            vs["type"] = gpu.DESC_STORAGE_BUFFER
        vs["count"] = s["count"]
        push(vk_sizes, vs)
        i = i + 1
    return gpu.create_descriptor_pool(max_sets, vk_sizes)

# desc_set(pool, layout) -> handle
proc desc_set(pool, layout):
    return gpu.allocate_descriptor_set(pool, layout)

# bind_buffer(set, binding, buffer) -> nil
proc bind_buffer(set, binding, buf):
    return gpu.update_descriptor(set, binding, gpu.DESC_STORAGE_BUFFER, buf)

# bind_uniform(set, binding, buffer) -> nil
proc bind_uniform(set, binding, buf):
    return gpu.update_descriptor(set, binding, gpu.DESC_UNIFORM_BUFFER, buf)

# bind_storage_image(set, binding, image) -> nil
proc bind_storage_image(set, binding, img):
    return gpu.update_descriptor(set, binding, gpu.DESC_STORAGE_IMAGE, img)

# bind_sampled_image(set, binding, image, sampler) -> nil
proc bind_sampled_image(set, binding, img, smp):
    return gpu.update_descriptor_image(set, binding, img, smp)

# -----------------------------------------
# Pipeline layout builder
# -----------------------------------------
# pipe_layout(desc_layouts, push_size?, push_stages?) -> handle
proc pipe_layout(layouts, push_size):
    return gpu.create_pipeline_layout(layouts, push_size, gpu.STAGE_ALL)

proc pipe_layout_no_push(layouts):
    return gpu.create_pipeline_layout(layouts, 0)

# -----------------------------------------
# Compute pipeline — one-liner
# -----------------------------------------
# compute_pipeline(shader_handle, desc_layout_handle, push_size?) -> dict
# Returns {pipeline, layout, desc_layout} for easy dispatch
proc compute_pipeline(shader_h, layout_h, push_size):
    let pl = gpu.create_pipeline_layout([layout_h], push_size, gpu.STAGE_COMPUTE)
    let pipe = gpu.create_compute_pipeline(pl, shader_h)
    let result = {}
    result["pipeline"] = pipe
    result["layout"] = pl
    return result

# compute_pipeline_simple(shader_path, bindings_array, push_size?) -> dict
# Full one-shot: loads shader, creates layout+pool+set+pipeline
proc compute_pipeline_simple(shader_path, bindings, push_size):
    let sh = shader(shader_path, "compute")
    let dl = desc_layout(bindings)
    let pl = gpu.create_pipeline_layout([dl], push_size, gpu.STAGE_COMPUTE)
    let pipe = gpu.create_compute_pipeline(pl, sh)
    let result = {}
    result["pipeline"] = pipe
    result["layout"] = pl
    result["desc_layout"] = dl
    result["shader"] = sh
    return result

# -----------------------------------------
# Command recording helpers
# -----------------------------------------
proc command_pool():
    return gpu.create_command_pool()

proc command_buffer(pool):
    return gpu.create_command_buffer(pool)

proc begin(cmd):
    return gpu.begin_commands(cmd)

proc end(cmd):
    return gpu.end_commands(cmd)

# -----------------------------------------
# Dispatch helper
# -----------------------------------------
# dispatch(cmd, pipeline_dict_or_handle, x, y, z, desc_set?, push_data?) -> nil
proc dispatch_compute(cmd, pipe_h, layout_h, x, y, z):
    gpu.cmd_bind_compute_pipeline(cmd, pipe_h)
    gpu.cmd_dispatch(cmd, x, y, z)

# Full dispatch with descriptor binding
proc dispatch_full(cmd, pipe_h, layout_h, desc_set_h, x, y, z):
    gpu.cmd_bind_compute_pipeline(cmd, pipe_h)
    gpu.cmd_bind_descriptor_set(cmd, layout_h, 0, desc_set_h)
    gpu.cmd_dispatch(cmd, x, y, z)

# Dispatch with push constants
proc dispatch_push(cmd, pipe_h, layout_h, desc_set_h, push_data, x, y, z):
    gpu.cmd_bind_compute_pipeline(cmd, pipe_h)
    gpu.cmd_bind_descriptor_set(cmd, layout_h, 0, desc_set_h)
    gpu.cmd_push_constants(cmd, layout_h, gpu.STAGE_COMPUTE, push_data)
    gpu.cmd_dispatch(cmd, x, y, z)

# -----------------------------------------
# Synchronization helpers
# -----------------------------------------
proc fence():
    return gpu.create_fence(false)

proc fence_signaled():
    return gpu.create_fence(true)

proc semaphore():
    return gpu.create_semaphore()

proc wait(fence_h):
    return gpu.wait_fence(fence_h)

proc reset(fence_h):
    return gpu.reset_fence(fence_h)

# -----------------------------------------
# Submission helpers
# -----------------------------------------
proc submit(cmd, fence_h):
    return gpu.submit(cmd, nil, nil, fence_h)

proc submit_compute(cmd, fence_h):
    return gpu.submit_compute(cmd, nil, nil, fence_h)

proc wait_idle():
    return gpu.device_wait_idle()

# -----------------------------------------
# Barrier helpers
# -----------------------------------------
proc compute_barrier(cmd):
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_COMPUTE, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

proc compute_to_transfer(cmd):
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_TRANSFER, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_TRANSFER_READ)

proc transfer_to_compute(cmd):
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_TRANSFER, gpu.PIPE_COMPUTE, gpu.ACCESS_TRANSFER_WRITE, gpu.ACCESS_SHADER_READ)

proc compute_to_host(cmd):
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_BOTTOM, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_HOST_READ)

proc image_to_general(cmd, img):
    gpu.cmd_image_barrier(cmd, img, gpu.LAYOUT_UNDEFINED, gpu.LAYOUT_GENERAL, gpu.PIPE_TOP, gpu.PIPE_COMPUTE, gpu.ACCESS_NONE, gpu.ACCESS_SHADER_WRITE)

proc image_to_shader_read(cmd, img):
    gpu.cmd_image_barrier(cmd, img, gpu.LAYOUT_GENERAL, gpu.LAYOUT_SHADER_READ, gpu.PIPE_COMPUTE, gpu.PIPE_FRAGMENT, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

# -----------------------------------------
# Cleanup helpers
# -----------------------------------------
proc destroy_buffer(h):
    gpu.destroy_buffer(h)

proc destroy_image(h):
    gpu.destroy_image(h)

proc destroy_sampler(h):
    gpu.destroy_sampler(h)

proc destroy_shader(h):
    gpu.destroy_shader(h)

proc destroy_pipeline(h):
    gpu.destroy_pipeline(h)

proc destroy_render_pass(h):
    gpu.destroy_render_pass(h)

proc destroy_framebuffer(h):
    gpu.destroy_framebuffer(h)

proc destroy_fence(h):
    gpu.destroy_fence(h)

proc destroy_semaphore(h):
    gpu.destroy_semaphore(h)
