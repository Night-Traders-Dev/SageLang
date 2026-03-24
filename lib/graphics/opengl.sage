# lib/opengl.sage - OpenGL backend for SageLang GPU engine
#
# Provides the same high-level API as gpu.sage/vulkan.sage but using
# the OpenGL graphics backend. Games can switch between Vulkan and OpenGL
# by changing which library they import.
#
# Usage:
#   import gpu
#   import opengl
#   opengl.init_windowed("My Game", 1280, 720)  # Uses OpenGL
#   # ... rest of the API is identical to gpu module

import gpu

# ============================================================================
# OpenGL Backend Selection
# ============================================================================

proc init_windowed(title, width, height)
    # Initialize with OpenGL backend instead of Vulkan
    return gpu.init_opengl_windowed(title, width, height, 4, 5)
end

proc init(app_name)
    return gpu.init_opengl(app_name, 4, 5)
end

proc init_with_version(app_name, major, minor)
    return gpu.init_opengl(app_name, major, minor)
end

# ============================================================================
# Re-export all GPU functions for API compatibility
# ============================================================================

proc shutdown()
    return gpu.shutdown()
end

proc shutdown_windowed()
    return gpu.shutdown_windowed()
end

proc has_opengl()
    return gpu.has_opengl()
end

proc has_vulkan()
    return gpu.has_vulkan()
end

proc device_name()
    return gpu.device_name()
end

proc last_error()
    return gpu.last_error()
end

# ============================================================================
# Buffer Operations
# ============================================================================

proc create_buffer(size, usage, mem_props)
    return gpu.create_buffer(size, usage, mem_props)
end

proc destroy_buffer(handle)
    return gpu.destroy_buffer(handle)
end

proc buffer_upload(handle, data)
    return gpu.buffer_upload(handle, data)
end

proc buffer_download(handle)
    return gpu.buffer_download(handle)
end

proc buffer_size(handle)
    return gpu.buffer_size(handle)
end

# ============================================================================
# Image Operations
# ============================================================================

proc create_image(w, h, format, usage, img_type)
    return gpu.create_image(w, h, format, usage, img_type)
end

proc destroy_image(handle)
    return gpu.destroy_image(handle)
end

proc image_dims(handle)
    return gpu.image_dims(handle)
end

# ============================================================================
# Sampler
# ============================================================================

proc create_sampler(min_filter, mag_filter, address)
    return gpu.create_sampler(min_filter, mag_filter, address)
end

proc destroy_sampler(handle)
    return gpu.destroy_sampler(handle)
end

# ============================================================================
# Shaders (OpenGL can accept GLSL directly)
# ============================================================================

proc load_shader(path, stage)
    return gpu.load_shader(path, stage)
end

proc load_shader_glsl(source, stage)
    return gpu.load_shader_glsl(source, stage)
end

proc destroy_shader(handle)
    return gpu.destroy_shader(handle)
end

# ============================================================================
# Descriptors
# ============================================================================

proc create_descriptor_layout(bindings)
    return gpu.create_descriptor_layout(bindings)
end

proc create_descriptor_pool(max_sets, type_counts)
    return gpu.create_descriptor_pool(max_sets, type_counts)
end

proc allocate_descriptor_set(pool, layout)
    return gpu.allocate_descriptor_set(pool, layout)
end

proc update_descriptor(set, binding, type, resource)
    return gpu.update_descriptor(set, binding, type, resource)
end

proc update_descriptor_image(set, binding, type, image, sampler)
    return gpu.update_descriptor_image(set, binding, type, image, sampler)
end

# ============================================================================
# Pipelines
# ============================================================================

proc create_pipeline_layout(layouts, push_size, push_stages)
    return gpu.create_pipeline_layout(layouts, push_size, push_stages)
end

proc create_compute_pipeline(layout, shader)
    return gpu.create_compute_pipeline(layout, shader)
end

proc create_graphics_pipeline(config)
    return gpu.create_graphics_pipeline(config)
end

proc destroy_pipeline(handle)
    return gpu.destroy_pipeline(handle)
end

# ============================================================================
# Render Pass & Framebuffer
# ============================================================================

proc create_render_pass(attachments, has_depth)
    return gpu.create_render_pass(attachments, has_depth)
end

proc destroy_render_pass(handle)
    return gpu.destroy_render_pass(handle)
end

proc create_framebuffer(rp, images, w, h)
    return gpu.create_framebuffer(rp, images, w, h)
end

proc destroy_framebuffer(handle)
    return gpu.destroy_framebuffer(handle)
end

proc create_depth_buffer(w, h, format)
    return gpu.create_depth_buffer(w, h, format)
end

# ============================================================================
# Command Buffers
# ============================================================================

proc create_command_pool(family)
    return gpu.create_command_pool(family)
end

proc create_command_buffer(pool)
    return gpu.create_command_buffer(pool)
end

proc begin_commands(cmd)
    return gpu.begin_commands(cmd)
end

proc end_commands(cmd)
    return gpu.end_commands(cmd)
end

# ============================================================================
# Drawing Commands
# ============================================================================

proc cmd_bind_graphics_pipeline(cmd, pipeline)
    return gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
end

proc cmd_bind_compute_pipeline(cmd, pipeline)
    return gpu.cmd_bind_compute_pipeline(cmd, pipeline)
end

proc cmd_bind_descriptor_set(cmd, layout, set, bind_point)
    return gpu.cmd_bind_descriptor_set(cmd, layout, set, bind_point)
end

proc cmd_begin_render_pass(cmd, rp, fb, w, h, clear)
    return gpu.cmd_begin_render_pass(cmd, rp, fb, w, h, clear)
end

proc cmd_end_render_pass(cmd)
    return gpu.cmd_end_render_pass(cmd)
end

proc cmd_draw(cmd, verts, instances, first_vert, first_inst)
    return gpu.cmd_draw(cmd, verts, instances, first_vert, first_inst)
end

proc cmd_draw_indexed(cmd, indices, instances, first_idx, vert_offset, first_inst)
    return gpu.cmd_draw_indexed(cmd, indices, instances, first_idx, vert_offset, first_inst)
end

proc cmd_bind_vertex_buffer(cmd, buffer)
    return gpu.cmd_bind_vertex_buffer(cmd, buffer)
end

proc cmd_bind_index_buffer(cmd, buffer)
    return gpu.cmd_bind_index_buffer(cmd, buffer)
end

proc cmd_set_viewport(cmd, x, y, w, h, min_d, max_d)
    return gpu.cmd_set_viewport(cmd, x, y, w, h, min_d, max_d)
end

proc cmd_set_scissor(cmd, x, y, w, h)
    return gpu.cmd_set_scissor(cmd, x, y, w, h)
end

proc cmd_dispatch(cmd, gx, gy, gz)
    return gpu.cmd_dispatch(cmd, gx, gy, gz)
end

proc cmd_push_constants(cmd, layout, stages, data)
    return gpu.cmd_push_constants(cmd, layout, stages, data)
end

proc cmd_pipeline_barrier(cmd, src_stage, dst_stage, src_access, dst_access)
    return gpu.cmd_pipeline_barrier(cmd, src_stage, dst_stage, src_access, dst_access)
end

proc cmd_copy_buffer(cmd, src, dst, size)
    return gpu.cmd_copy_buffer(cmd, src, dst, size)
end

# ============================================================================
# Synchronization
# ============================================================================

proc create_fence(signaled)
    return gpu.create_fence(signaled)
end

proc wait_fence(fence, timeout)
    return gpu.wait_fence(fence, timeout)
end

proc reset_fence(fence)
    return gpu.reset_fence(fence)
end

proc destroy_fence(fence)
    return gpu.destroy_fence(fence)
end

proc create_semaphore()
    return gpu.create_semaphore()
end

proc destroy_semaphore(sem)
    return gpu.destroy_semaphore(sem)
end

proc submit(cmd, fence)
    return gpu.submit(cmd, fence)
end

proc submit_with_sync(cmd, wait_sem, signal_sem, fence)
    return gpu.submit_with_sync(cmd, wait_sem, signal_sem, fence)
end

proc queue_wait_idle()
    return gpu.queue_wait_idle()
end

proc device_wait_idle()
    return gpu.device_wait_idle()
end

# ============================================================================
# Window & Swapchain
# ============================================================================

proc window_should_close()
    return gpu.window_should_close()
end

proc poll_events()
    return gpu.poll_events()
end

proc swapchain_image_count()
    return gpu.swapchain_image_count()
end

proc swapchain_format()
    return gpu.swapchain_format()
end

proc swapchain_extent()
    return gpu.swapchain_extent()
end

proc acquire_next_image(sem)
    return gpu.acquire_next_image(sem)
end

proc present(sem, image_idx)
    return gpu.present(sem, image_idx)
end

proc create_swapchain_framebuffers(rp)
    return gpu.create_swapchain_framebuffers(rp)
end

proc create_swapchain_framebuffers_depth(rp, depth)
    return gpu.create_swapchain_framebuffers_depth(rp, depth)
end

proc recreate_swapchain()
    return gpu.recreate_swapchain()
end

# ============================================================================
# Input
# ============================================================================

proc key_pressed(key)
    return gpu.key_pressed(key)
end

proc key_down(key)
    return gpu.key_down(key)
end

proc key_just_pressed(key)
    return gpu.key_just_pressed(key)
end

proc key_just_released(key)
    return gpu.key_just_released(key)
end

proc mouse_pos()
    return gpu.mouse_pos()
end

proc mouse_button(button)
    return gpu.mouse_button(button)
end

proc mouse_delta()
    return gpu.mouse_delta()
end

proc scroll_delta()
    return gpu.scroll_delta()
end

proc set_cursor_mode(mode)
    return gpu.set_cursor_mode(mode)
end

proc get_time()
    return gpu.get_time()
end

proc window_size()
    return gpu.window_size()
end

proc set_title(title)
    return gpu.set_title(title)
end

proc update_input()
    return gpu.update_input()
end

# ============================================================================
# Texture & Upload
# ============================================================================

proc load_texture(path, gen_mipmaps, filter, address)
    return gpu.load_texture(path, gen_mipmaps, filter, address)
end

proc texture_dims(handle)
    return gpu.texture_dims(handle)
end

proc upload_device_local(data, usage)
    return gpu.upload_device_local(data, usage)
end

proc create_uniform_buffer(size)
    return gpu.create_uniform_buffer(size)
end

proc update_uniform(handle, data)
    return gpu.update_uniform(handle, data)
end

# ============================================================================
# Constants (re-exported from gpu module)
# ============================================================================

# All constants from gpu module are available via gpu.CONSTANT_NAME
# or you can use them directly after import:
#   let BUFFER_VERTEX = gpu.BUFFER_VERTEX
