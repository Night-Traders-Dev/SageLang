# gpu_cube.sage - Demo: Spinning Textured Cube with Depth Buffer
# Renders a 3D cube with checkerboard texture and directional lighting
#
# Run: ./sage examples/gpu_cube.sage

import gpu
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, aspect_ratio
from math3d import mat4_perspective, mat4_rotate_y, mat4_rotate_x, mat4_mul, mat4_translate, radians, pack_mvp
from mesh import cube_mesh, upload_mesh, mesh_vertex_binding, mesh_vertex_attribs

print "=== Sage GPU Demo: Spinning Cube ==="

let r = create_renderer(1024, 768, "Sage - Spinning Cube")
if r == nil:
    raise "Failed to create renderer"

print "GPU: " + gpu.device_name()

# Load shaders
let vert = gpu.load_shader("examples/shaders/cube.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("examples/shaders/cube.frag.spv", gpu.STAGE_FRAGMENT)
if vert < 0:
    raise "Failed to load cube vertex shader"
if frag < 0:
    raise "Failed to load cube fragment shader"

# Create mesh
let mesh = cube_mesh()
let gpu_mesh = upload_mesh(mesh)
print "Cube: " + str(gpu_mesh["vertex_count"]) + " vertices, " + str(gpu_mesh["index_count"]) + " indices"

# Pipeline layout with push constants (64 bytes = 1 mat4 MVP)
let pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)

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
    raise "Failed to create cube pipeline"
print "Pipeline created"

# Projection matrix
let aspect = aspect_ratio(r)
let proj = mat4_perspective(radians(60.0), aspect, 0.1, 100.0)

# Render loop
print "Rendering cube... (close window to exit)"
let frame_data = begin_frame(r)
while frame_data != nil:
    let cmd = frame_data["cmd"]
    let t = frame_data["time"]

    # Model: rotate around Y and X
    let model = mat4_mul(mat4_rotate_y(t * 1.2), mat4_rotate_x(t * 0.7))

    # View: camera at (0, 1.5, 3) looking at origin
    let view = mat4_translate(0.0, -1.0, -3.0)

    # MVP
    let mvp = pack_mvp(model, view, proj)

    # Draw
    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
    gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX, mvp)
    gpu.cmd_bind_vertex_buffer(cmd, gpu_mesh["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, gpu_mesh["ibuf"])
    gpu.cmd_draw_indexed(cmd, gpu_mesh["index_count"], 1, 0, 0, 0)

    end_frame(r, frame_data)
    frame_data = begin_frame(r)

shutdown_renderer(r)
print "Done!"
