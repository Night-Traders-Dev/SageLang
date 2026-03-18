gc_disable()
# -----------------------------------------
# mesh.sage - Mesh generation and loading for SageLang
# Procedural meshes (cube, plane, sphere) and OBJ file loading
# Vertex format: [px, py, pz, nx, ny, nz, u, v] per vertex (stride 32 bytes)
# -----------------------------------------

import gpu
import math

let VERTEX_STRIDE = 8

# ============================================================================
# Procedural: Unit Cube (-0.5 to 0.5)
# 24 vertices (4 per face), 36 indices, with normals and UVs
# ============================================================================
proc cube_mesh():
    let v = []
    let idx = []

    # Helper: add a face (4 verts, 2 triangles)
    # Each vert: px,py,pz, nx,ny,nz, u,v
    proc add_face(p0, p1, p2, p3, n):
        let base = len(v) / VERTEX_STRIDE
        # v0
        push(v, p0[0])
        push(v, p0[1])
        push(v, p0[2])
        push(v, n[0])
        push(v, n[1])
        push(v, n[2])
        push(v, 0.0)
        push(v, 0.0)
        # v1
        push(v, p1[0])
        push(v, p1[1])
        push(v, p1[2])
        push(v, n[0])
        push(v, n[1])
        push(v, n[2])
        push(v, 1.0)
        push(v, 0.0)
        # v2
        push(v, p2[0])
        push(v, p2[1])
        push(v, p2[2])
        push(v, n[0])
        push(v, n[1])
        push(v, n[2])
        push(v, 1.0)
        push(v, 1.0)
        # v3
        push(v, p3[0])
        push(v, p3[1])
        push(v, p3[2])
        push(v, n[0])
        push(v, n[1])
        push(v, n[2])
        push(v, 0.0)
        push(v, 1.0)
        # Two triangles
        push(idx, base)
        push(idx, base + 1)
        push(idx, base + 2)
        push(idx, base)
        push(idx, base + 2)
        push(idx, base + 3)

    let h = 0.5
    # Front face (z+)
    add_face([0-h, 0-h, h], [h, 0-h, h], [h, h, h], [0-h, h, h], [0, 0, 1])
    # Back face (z-)
    add_face([h, 0-h, 0-h], [0-h, 0-h, 0-h], [0-h, h, 0-h], [h, h, 0-h], [0, 0, -1])
    # Right face (x+)
    add_face([h, 0-h, h], [h, 0-h, 0-h], [h, h, 0-h], [h, h, h], [1, 0, 0])
    # Left face (x-)
    add_face([0-h, 0-h, 0-h], [0-h, 0-h, h], [0-h, h, h], [0-h, h, 0-h], [-1, 0, 0])
    # Top face (y+)
    add_face([0-h, h, h], [h, h, h], [h, h, 0-h], [0-h, h, 0-h], [0, 1, 0])
    # Bottom face (y-)
    add_face([0-h, 0-h, 0-h], [h, 0-h, 0-h], [h, 0-h, h], [0-h, 0-h, h], [0, -1, 0])

    let result = {}
    result["vertices"] = v
    result["indices"] = idx
    result["vertex_count"] = len(v) / VERTEX_STRIDE
    result["index_count"] = len(idx)
    result["has_normals"] = true
    result["has_uvs"] = true
    return result

# ============================================================================
# Procedural: XZ Plane centered at origin
# ============================================================================
proc plane_mesh(size):
    let h = size / 2
    let v = []
    let idx = []

    # 4 vertices
    # v0: -h, 0, -h
    push(v, 0 - h)
    push(v, 0.0)
    push(v, 0 - h)
    push(v, 0.0)
    push(v, 1.0)
    push(v, 0.0)
    push(v, 0.0)
    push(v, 0.0)
    # v1: h, 0, -h
    push(v, h)
    push(v, 0.0)
    push(v, 0 - h)
    push(v, 0.0)
    push(v, 1.0)
    push(v, 0.0)
    push(v, 1.0)
    push(v, 0.0)
    # v2: h, 0, h
    push(v, h)
    push(v, 0.0)
    push(v, h)
    push(v, 0.0)
    push(v, 1.0)
    push(v, 0.0)
    push(v, 1.0)
    push(v, 1.0)
    # v3: -h, 0, h
    push(v, 0 - h)
    push(v, 0.0)
    push(v, h)
    push(v, 0.0)
    push(v, 1.0)
    push(v, 0.0)
    push(v, 0.0)
    push(v, 1.0)

    push(idx, 0)
    push(idx, 1)
    push(idx, 2)
    push(idx, 0)
    push(idx, 2)
    push(idx, 3)

    let result = {}
    result["vertices"] = v
    result["indices"] = idx
    result["vertex_count"] = 4
    result["index_count"] = 6
    result["has_normals"] = true
    result["has_uvs"] = true
    return result

# ============================================================================
# Procedural: UV Sphere
# ============================================================================
proc sphere_mesh(rings, segments):
    let v = []
    let idx = []

    let ri = 0
    while ri <= rings:
        let phi = 3.14159265 * ri / rings
        let sp = math.sin(phi)
        let cp = math.cos(phi)

        let si = 0
        while si <= segments:
            let theta = 2.0 * 3.14159265 * si / segments
            let st = math.sin(theta)
            let ct = math.cos(theta)

            let x = ct * sp
            let y = cp
            let z = st * sp
            let u = si / segments
            let uv = ri / rings

            push(v, x)
            push(v, y)
            push(v, z)
            push(v, x)
            push(v, y)
            push(v, z)
            push(v, u)
            push(v, uv)

            si = si + 1
        ri = ri + 1

    # Indices
    let r = 0
    while r < rings:
        let s = 0
        while s < segments:
            let a = r * (segments + 1) + s
            let b = a + segments + 1
            push(idx, a)
            push(idx, b)
            push(idx, a + 1)
            push(idx, b)
            push(idx, b + 1)
            push(idx, a + 1)
            s = s + 1
        r = r + 1

    let result = {}
    result["vertices"] = v
    result["indices"] = idx
    result["vertex_count"] = len(v) / VERTEX_STRIDE
    result["index_count"] = len(idx)
    result["has_normals"] = true
    result["has_uvs"] = true
    return result

# ============================================================================
# Upload mesh to GPU (device-local buffers)
# Returns dict with vbuf, ibuf, index_count
# ============================================================================
proc upload_mesh(mesh_dict):
    let vbuf = gpu.upload_device_local(mesh_dict["vertices"], gpu.BUFFER_VERTEX)
    # Index data needs to be uploaded as uint32 - convert float indices
    let ibuf = gpu.upload_device_local(mesh_dict["indices"], gpu.BUFFER_INDEX)
    let result = {}
    result["vbuf"] = vbuf
    result["ibuf"] = ibuf
    result["index_count"] = mesh_dict["index_count"]
    result["vertex_count"] = mesh_dict["vertex_count"]
    return result

# ============================================================================
# Standard vertex binding/attribute descriptions for mesh vertex format
# [px, py, pz, nx, ny, nz, u, v] stride = 32 bytes
# ============================================================================
proc mesh_vertex_binding():
    let b = {}
    b["binding"] = 0
    b["stride"] = 32
    b["rate"] = gpu.INPUT_RATE_VERTEX
    return b

proc mesh_vertex_attribs():
    let a0 = {}
    a0["location"] = 0
    a0["binding"] = 0
    a0["format"] = gpu.ATTR_VEC3
    a0["offset"] = 0
    let a1 = {}
    a1["location"] = 1
    a1["binding"] = 0
    a1["format"] = gpu.ATTR_VEC3
    a1["offset"] = 12
    let a2 = {}
    a2["location"] = 2
    a2["binding"] = 0
    a2["format"] = gpu.ATTR_VEC2
    a2["offset"] = 24
    return [a0, a1, a2]
