# gpu_solarsystem.sage - Solar System Demo
# Sun + planets orbiting with proper relative sizes and distances
# Interactive WASD camera
#
# Run: ./sage examples/gpu_solarsystem.sage

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, aspect_ratio, update_title_fps
from math3d import mat4_perspective, mat4_mul, mat4_translate, mat4_scale, mat4_rotate_y, radians, vec3, pack_mvp
from mesh import sphere_mesh, upload_mesh, mesh_vertex_binding, mesh_vertex_attribs
from camera import create_camera, update_camera

print "=== Sage GPU: Solar System ==="

let r = create_renderer(1280, 720, "Sage - Solar System")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

let vert = gpu.load_shader("examples/shaders/cube.vert.spv", gpu.STAGE_VERTEX)
let frag = gpu.load_shader("examples/shaders/cube.frag.spv", gpu.STAGE_FRAGMENT)

let sph = sphere_mesh(16, 32)
let gpu_sph = upload_mesh(sph)

let pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)
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

# Planet definitions: [name, distance, radius, speed, color_r, color_g, color_b]
let planets = []
# Sun (at center)
push(planets, [0.0, 2.0, 0.0, 1.0, 0.95, 0.8])
# Mercury
push(planets, [4.0, 0.3, 4.0, 0.7, 0.6, 0.5])
# Venus
push(planets, [6.0, 0.5, 2.5, 0.9, 0.8, 0.5])
# Earth
push(planets, [9.0, 0.55, 1.8, 0.2, 0.4, 0.8])
# Mars
push(planets, [12.0, 0.35, 1.3, 0.8, 0.3, 0.2])
# Jupiter
push(planets, [18.0, 1.2, 0.7, 0.8, 0.7, 0.5])
# Saturn
push(planets, [24.0, 1.0, 0.5, 0.9, 0.85, 0.6])
# Uranus
push(planets, [30.0, 0.7, 0.35, 0.5, 0.7, 0.8])
# Neptune
push(planets, [36.0, 0.65, 0.25, 0.3, 0.4, 0.9])

let cam = create_camera(0.0, 15.0, 35.0)
cam["speed"] = 15.0
cam["pitch"] = -0.4
let aspect = aspect_ratio(r)
let proj = mat4_perspective(radians(60.0), aspect, 0.01, 200.0)

print str(len(planets)) + " bodies. WASD + mouse to fly."
let frame_data = begin_frame(r)
while frame_data != nil:
    let cmd = frame_data["cmd"]
    let t = frame_data["time"]
    gpu.update_input()

    let dt = 0.016
    let view = update_camera(cam, dt)
    let vp = mat4_mul(proj, view)

    gpu.cmd_bind_graphics_pipeline(cmd, pipeline)
    gpu.cmd_bind_vertex_buffer(cmd, gpu_sph["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, gpu_sph["ibuf"])

    let pi = 0
    while pi < len(planets):
        let p = planets[pi]
        let dist = p[0]
        let radius = p[1]
        let speed = p[2]

        let px = 0.0
        let pz = 0.0
        if dist > 0:
            px = math.cos(t * speed * 0.3) * dist
            pz = math.sin(t * speed * 0.3) * dist

        let model = mat4_mul(mat4_translate(px, 0.0, pz), mat4_mul(mat4_scale(radius, radius, radius), mat4_rotate_y(t * speed)))
        let mvp = pack_mvp(model, view, proj)
        gpu.cmd_push_constants(cmd, pipe_layout, gpu.STAGE_VERTEX, mvp)
        gpu.cmd_draw_indexed(cmd, gpu_sph["index_count"], 1, 0, 0, 0)

        pi = pi + 1

    update_title_fps(r, "Sage Solar System")
    end_frame(r, frame_data)
    frame_data = begin_frame(r)

shutdown_renderer(r)
print "Done!"
