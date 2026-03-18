# gpu_pbr.sage - Demo 2: PBR Metallic-Roughness Spheres
# Cook-Torrance BRDF with varying metallic/roughness parameters
#
# Run: ./sage examples/gpu_pbr.sage

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, aspect_ratio, update_title_fps
from math3d import mat4_perspective, mat4_mul, mat4_translate, mat4_scale, mat4_identity, radians, vec3, camera_orbit
from mesh import sphere_mesh, upload_mesh, mesh_vertex_binding, mesh_vertex_attribs
from pbr import create_pbr_material, pack_pbr_material, create_point_light, pack_point_light

print "=== Sage GPU Demo: PBR Materials ==="

let r = create_renderer(1024, 768, "Sage - PBR Materials")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# Shaders
let vert = gpu.load_shader("examples/shaders/pbr.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("examples/shaders/pbr.frag.spv", gpu.STAGE_FRAGMENT)

# Mesh: sphere
let sph = sphere_mesh(24, 48)
let gpu_sph = upload_mesh(sph)
print "Sphere: " + str(gpu_sph["vertex_count"]) + " verts, " + str(gpu_sph["index_count"]) + " indices"

# UBO for material params (96 bytes = 24 floats: material + camPos + light)
let mat_ubo = gpu.create_uniform_buffer(96)

# Descriptor layout: binding 0 = UBO
let bd = {}
bd["binding"] = 0
bd["type"] = gpu.DESC_UNIFORM_BUFFER
bd["stage"] = gpu.STAGE_FRAGMENT
bd["count"] = 1
let desc_layout = gpu.create_descriptor_layout([bd])

let pool_s = {}
pool_s["type"] = gpu.DESC_UNIFORM_BUFFER
pool_s["count"] = 1
let desc_pool = gpu.create_descriptor_pool(1, [pool_s])
let desc_set = gpu.allocate_descriptor_set(desc_pool, desc_layout)
gpu.update_descriptor(desc_set, 0, gpu.DESC_UNIFORM_BUFFER, mat_ubo)

# Pipeline layout: push constants (128 bytes = MVP + Model) + 1 descriptor set
let pipe_layout = gpu.create_pipeline_layout([desc_layout], 128, gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT)

let cfg = {}
cfg["layout"] = pipe_layout
cfg["render_pass"] = r["render_pass"]
cfg["vertex_shader"] = vert
cfg["fragment_shader"] = frag
cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
cfg["cull_mode"] = gpu.CULL_BACK
cfg["front_face"] = gpu.FRONT_CCW
cfg["depth_test"] = true
cfg["depth_write"] = true
cfg["vertex_bindings"] = [mesh_vertex_binding()]
cfg["vertex_attribs"] = mesh_vertex_attribs()
let pipeline = gpu.create_graphics_pipeline(cfg)

let aspect = aspect_ratio(r)
let proj = mat4_perspective(radians(50.0), aspect, 0.1, 100.0)

# 5x5 grid of spheres with varying metallic (X) and roughness (Y)
let grid_size = 5
let spacing = 2.5

# Light
let light = create_point_light([5.0, 5.0, 10.0], [1.0, 1.0, 1.0], 300.0)

print "Rendering " + str(grid_size * grid_size) + " PBR spheres... (close window to exit)"
let frame_data = begin_frame(r)
while frame_data != nil:
    let cmd = frame_data["cmd"]
    let t = frame_data["time"]

    # Orbit camera
    let view = camera_orbit(t * 0.2, 0.3, 12.0, vec3(spacing * 2, 0, spacing * 2))
    let vp = mat4_mul(proj, view)

    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
    gpu.cmd_bind_descriptor_set(cmd, pipe_layout, 0, desc_set, 0)
    gpu.cmd_bind_vertex_buffer(cmd, gpu_sph["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, gpu_sph["ibuf"])

    let row = 0
    while row < grid_size:
        let col = 0
        while col < grid_size:
            let metallic = col / (grid_size - 1)
            let roughness = 0.05 + row / (grid_size - 1) * 0.95

            let model = mat4_mul(mat4_translate(col * spacing, row * spacing, 0.0), mat4_scale(0.9, 0.9, 0.9))
            let mvp = mat4_mul(vp, model)

            # Push MVP + Model (128 bytes)
            let push_data = []
            let pi = 0
            while pi < 16:
                push(push_data, mvp[pi])
                pi = pi + 1
            pi = 0
            while pi < 16:
                push(push_data, model[pi])
                pi = pi + 1
            gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT, push_data)

            # Update UBO with material + camera + light
            let cam_pos = [12.0 * math.sin(t * 0.2), 5.0, 12.0 * math.cos(t * 0.2)]
            let ubo_data = []
            # albedo
            push(ubo_data, 0.9)
            push(ubo_data, 0.2)
            push(ubo_data, 0.2)
            push(ubo_data, 1.0)
            # metallic, roughness, ao, pad
            push(ubo_data, metallic)
            push(ubo_data, roughness)
            push(ubo_data, 1.0)
            push(ubo_data, 0.0)
            # emission
            push(ubo_data, 0.0)
            push(ubo_data, 0.0)
            push(ubo_data, 0.0)
            push(ubo_data, 0.0)
            # camPos
            push(ubo_data, cam_pos[0])
            push(ubo_data, cam_pos[1])
            push(ubo_data, cam_pos[2])
            push(ubo_data, 0.0)
            # light pos + intensity
            push(ubo_data, 5.0)
            push(ubo_data, 5.0)
            push(ubo_data, 10.0)
            push(ubo_data, 300.0)
            # light color
            push(ubo_data, 1.0)
            push(ubo_data, 1.0)
            push(ubo_data, 1.0)
            push(ubo_data, 0.0)
            gpu.update_uniform(mat_ubo, ubo_data)

            gpu.cmd_draw_indexed(cmd, gpu_sph["index_count"], 1, 0, 0, 0)
            col = col + 1
        row = row + 1

    update_title_fps(r, "Sage - PBR")
    end_frame(r, frame_data)
    frame_data = begin_frame(r)

shutdown_renderer(r)
print "Done!"
