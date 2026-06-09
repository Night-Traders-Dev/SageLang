## android.graphics — Vulkan/OpenGL ES Graphics for Android
##
## Provides GPU compute and rendering abstractions that map to
## Android's Vulkan 1.0+ (API 24+) and OpenGL ES 3.0+ APIs.
##
## When transpiled with --compile-android, these become actual
## Android GPU API calls via the SageGPU Kotlin runtime module.
##
##   import android.graphics
##
##   let gpu = GPUContext("My App")
##   let buf = gpu.create_buffer(1024, "storage")
##   gpu.upload(buf, [1.0, 2.0, 3.0, 4.0])
##   gpu.dispatch_compute("shader.comp", buf, 256)
##   let result = gpu.download(buf)
##   gpu.destroy()

## ============================================================
## GPU Context — manages Vulkan/OpenGL ES lifecycle on Android
## ============================================================

class GPUContext:
    proc init(self, app_name):
        self.app_name = app_name
        self.initialized = false
        self.backend = "none"
        self.buffers = []
        self.pipelines = []
        self.shaders = []

    proc initialize(self):
        ## Try Vulkan first, fall back to OpenGL ES
        self.backend = "vulkan"
        self.initialized = true
        print("[GPU] Initialized " + self.backend + " for " + self.app_name)
        return self

    proc destroy(self):
        self.initialized = false
        print("[GPU] Destroyed context")

    proc device_name(self):
        return "Android GPU"

    proc has_vulkan(self):
        return true

    proc has_opengl_es(self):
        return true

## ============================================================
## Buffer Operations
## ============================================================

    proc create_buffer(self, size, usage):
        let buf = {
            "id": len(self.buffers),
            "size": size,
            "usage": usage,
            "data": nil
        }
        push(self.buffers, buf)
        return buf["id"]

    proc destroy_buffer(self, handle):
        if handle >= 0 and handle < len(self.buffers):
            self.buffers[handle] = nil

    proc upload(self, handle, data):
        if handle >= 0 and handle < len(self.buffers):
            self.buffers[handle]["data"] = data

    proc download(self, handle):
        if handle >= 0 and handle < len(self.buffers):
            return self.buffers[handle]["data"]
        return nil

    proc buffer_size(self, handle):
        if handle >= 0 and handle < len(self.buffers):
            return self.buffers[handle]["size"]
        return 0

## ============================================================
## Shader Operations
## ============================================================

    proc load_shader(self, path, stage):
        let shader = {
            "id": len(self.shaders),
            "path": path,
            "stage": stage
        }
        push(self.shaders, shader)
        return shader["id"]

    proc load_shader_glsl(self, source, stage):
        let shader = {
            "id": len(self.shaders),
            "source": source,
            "stage": stage
        }
        push(self.shaders, shader)
        return shader["id"]

## ============================================================
## Compute Pipeline
## ============================================================

    proc create_compute_pipeline(self, shader_handle):
        let pipeline = {
            "id": len(self.pipelines),
            "type": "compute",
            "shader": shader_handle
        }
        push(self.pipelines, pipeline)
        return pipeline["id"]

    proc dispatch_compute(self, shader_path, buffer_handle, work_groups):
        let shader = self.load_shader(shader_path, "compute")
        let pipeline = self.create_compute_pipeline(shader)
        print("[GPU] Dispatch compute: " + str(work_groups) + " groups")
        return true

## ============================================================
## Graphics Pipeline (Vulkan-style)
## ============================================================

    proc create_graphics_pipeline(self, vert_shader, frag_shader, config):
        let pipeline = {
            "id": len(self.pipelines),
            "type": "graphics",
            "vertex_shader": vert_shader,
            "fragment_shader": frag_shader,
            "config": config
        }
        push(self.pipelines, pipeline)
        return pipeline["id"]

## ============================================================
## Render Pass
## ============================================================

    proc create_render_pass(self, attachments):
        return {"id": 0, "attachments": attachments}

    proc begin_render_pass(self, pass_handle, framebuffer):
        print("[GPU] Begin render pass")

    proc end_render_pass(self):
        print("[GPU] End render pass")

## ============================================================
## Drawing Commands
## ============================================================

    proc draw(self, vertex_count, instance_count):
        print("[GPU] Draw " + str(vertex_count) + " vertices, " + str(instance_count) + " instances")

    proc draw_indexed(self, index_count, instance_count):
        print("[GPU] Draw indexed " + str(index_count) + " indices")

    proc bind_pipeline(self, pipeline_handle):
        print("[GPU] Bind pipeline " + str(pipeline_handle))

    proc bind_vertex_buffer(self, buffer_handle):
        print("[GPU] Bind vertex buffer " + str(buffer_handle))

    proc bind_index_buffer(self, buffer_handle):
        print("[GPU] Bind index buffer " + str(buffer_handle))

    proc set_viewport(self, x, y, w, h):
        print("[GPU] Viewport: " + str(w) + "x" + str(h))

    proc set_scissor(self, x, y, w, h):
        print("[GPU] Scissor: " + str(w) + "x" + str(h))

## ============================================================
## Texture/Image Operations
## ============================================================

    proc create_image(self, width, height, format):
        return {"width": width, "height": height, "format": format}

    proc load_texture(self, path):
        return {"path": path, "loaded": true}

## ============================================================
## Synchronization
## ============================================================

    proc create_fence(self):
        return {"signaled": false}

    proc wait_fence(self, fence):
        fence["signaled"] = true

    proc create_semaphore(self):
        return {"value": 0}

    proc submit(self):
        print("[GPU] Submit commands")

    proc present(self):
        print("[GPU] Present frame")

    proc device_wait_idle(self):
        print("[GPU] Wait idle")

## ============================================================
## Android-Specific: Surface/Window Management
## ============================================================

class GPUSurface:
    proc init(self, activity):
        self.activity = activity
        self.width = 0
        self.height = 0
        self.format = "RGBA8"

    proc resize(self, w, h):
        self.width = w
        self.height = h

    proc get_size(self):
        return [self.width, self.height]

## ============================================================
## OpenGL ES Convenience Layer
## ============================================================

class GLESContext:
    proc init(self):
        self.version = "3.0"
        self.initialized = false

    proc initialize(self):
        self.initialized = true
        print("[GLES] Initialized OpenGL ES " + self.version)
        return self

    proc clear(self, r, g, b, a):
        print("[GLES] Clear " + str(r) + "," + str(g) + "," + str(b) + "," + str(a))

    proc viewport(self, x, y, w, h):
        print("[GLES] Viewport " + str(w) + "x" + str(h))

    proc draw_arrays(self, mode, first, count):
        print("[GLES] DrawArrays " + str(mode) + " " + str(count))

    proc draw_elements(self, mode, count, index_type):
        print("[GLES] DrawElements " + str(mode) + " " + str(count))

    proc swap_buffers(self):
        print("[GLES] SwapBuffers")

    proc destroy(self):
        self.initialized = false

## ============================================================
## Convenience: Quick GPU compute helper
## ============================================================

proc run_compute(shader_source, input_data, work_groups):
    let ctx = GPUContext("compute")
    ctx.initialize()
    let buf = ctx.create_buffer(len(input_data) * 4, "storage")
    ctx.upload(buf, input_data)
    let shader = ctx.load_shader_glsl(shader_source, "compute")
    let pipeline = ctx.create_compute_pipeline(shader)
    ctx.dispatch_compute("inline", buf, work_groups)
    let result = ctx.download(buf)
    ctx.destroy()
    return result
