# gpu_phong.sage - Demo: Phong-Lit Scene with Multiple Objects
# Renders a cube and floor with Phong shading (ambient + diffuse + specular)
#
# Run: ./sage examples/gpu_phong.sage

import gpu
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, aspect_ratio
from math3d import mat4_perspective, mat4_rotate_y, mat4_rotate_x, mat4_mul, mat4_translate, mat4_scale, mat4_identity, radians, pack_mvp, camera_orbit
from mesh import cube_mesh, plane_mesh, upload_mesh, mesh_vertex_binding, mesh_vertex_attribs

print "=== Sage GPU Demo: Phong Lighting ==="

let r = create_renderer(1024, 768, "Sage - Phong Lighting")
if r == nil:
    raise "Failed to create renderer"

print "GPU: " + gpu.device_name()

# Load shaders
let vert = gpu.load_shader("examples/shaders/phong.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("examples/shaders/phong.frag.spv", gpu.STAGE_FRAGMENT)
if vert < 0:
    raise "Failed to load phong vertex shader"
if frag < 0:
    raise "Failed to load phong fragment shader"

# Create meshes
let cube = upload_mesh(cube_mesh())
let floor = upload_mesh(plane_mesh(10.0))
print "Meshes uploaded"

# Pipeline layout: push constants = 128 bytes (mat4 MVP + mat4 Model)
let pipe_layout = gpu.create_pipeline_layout([], 128, gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT)

# Graphics pipeline
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
if pipeline < 0:
    raise "Failed to create phong pipeline"
print "Pipeline created"

let aspect = aspect_ratio(r)
let proj = mat4_perspective(radians(50.0), aspect, 0.1, 100.0)

# Helper: draw a mesh with given model matrix
proc draw_object(cmd, pl, mesh_gpu, model, view_proj):
    let mvp = mat4_mul(view_proj, model)
    # Pack MVP (16 floats) + Model (16 floats) = 32 floats = 128 bytes
    let push_data = []
    let i = 0
    while i < 16:
        push(push_data, mvp[i])
        i = i + 1
    i = 0
    while i < 16:
        push(push_data, model[i])
        i = i + 1
    gpu.cmd_push_constants(cmd, pl, gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)

# Render loop
print "Rendering scene... (close window to exit)"
let frame_data = begin_frame(r)
while frame_data != nil:
    let cmd = frame_data["cmd"]
    let t = frame_data["time"]

    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)

    # Orbit camera
    let view = camera_orbit(t * 0.3, 0.4, 5.0, [0.0, 0.5, 0.0])
    let vp = mat4_mul(proj, view)

    # Floor
    let floor_model = mat4_translate(0.0, -0.5, 0.0)
    draw_object(cmd, pipe_layout, floor, floor_model, vp)

    # Spinning cube
    let cube_model = mat4_mul(mat4_translate(0.0, 0.5, 0.0), mat4_mul(mat4_rotate_y(t * 1.5), mat4_rotate_x(t * 0.8)))
    draw_object(cmd, pipe_layout, cube, cube_model, vp)

    # Second cube offset
    let cube2_model = mat4_mul(mat4_translate(2.0, 0.3, -1.0), mat4_mul(mat4_rotate_y(t * 0.7), mat4_scale(0.6, 0.6, 0.6)))
    draw_object(cmd, pipe_layout, cube, cube2_model, vp)

    # Third cube
    let cube3_model = mat4_mul(mat4_translate(-1.5, 0.2, 1.0), mat4_mul(mat4_rotate_y(0 - t), mat4_scale(0.4, 0.4, 0.4)))
    draw_object(cmd, pipe_layout, cube, cube3_model, vp)

    end_frame(r, frame_data)
    frame_data = begin_frame(r)

shutdown_renderer(r)
print "Done!"
