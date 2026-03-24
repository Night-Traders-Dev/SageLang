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

    # Index data: pack as uint32 little-endian bytes
    let indices = mesh_dict["indices"]
    let byte_arr = []
    let ii = 0
    while ii < len(indices):
        let val = indices[ii]
        if val < 0:
            val = 0
        # Pack uint32 as 4 little-endian bytes using math.floor for integer division
        let b0 = val - math.floor(val / 256) * 256
        let r1 = math.floor(val / 256)
        let b1_val = r1 - math.floor(r1 / 256) * 256
        let r2 = math.floor(val / 65536)
        let b2 = r2 - math.floor(r2 / 256) * 256
        let r3 = math.floor(val / 16777216)
        let b3 = r3 - math.floor(r3 / 256) * 256
        push(byte_arr, b0)
        push(byte_arr, b1_val)
        push(byte_arr, b2)
        push(byte_arr, b3)
        ii = ii + 1
    let ibuf = gpu.upload_bytes(byte_arr, gpu.BUFFER_INDEX)

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

# ============================================================================
# OBJ File Loading
# Parses Wavefront .obj files (v, vn, vt, f lines)
# Returns mesh dict compatible with upload_mesh()
# ============================================================================
proc load_obj(path):
    import io
    let content = io.readfile(path)
    if content == nil:
        print "mesh: failed to read " + path
        return nil

    let positions = []
    let normals = []
    let uvs = []
    let vertices = []
    let indices = []
    let vert_map = {}
    let vert_count = 0

    # Parse line by line
    let line_start = 0
    let ci = 0
    let clen = len(content)
    while ci <= clen:
        let at_end = ci == clen
        let is_nl = false
        if at_end == false:
            if content[ci] == chr(10):
                is_nl = true
        if is_nl:
            let line = ""
            let li = line_start
            while li < ci:
                line = line + content[li]
                li = li + 1
            line_start = ci + 1

            # Process line
            if startswith(line, "v "):
                # Vertex position
                let parts = split(line, " ")
                if len(parts) >= 4:
                    push(positions, [tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])])
            if startswith(line, "vn "):
                let parts = split(line, " ")
                if len(parts) >= 4:
                    push(normals, [tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])])
            if startswith(line, "vt "):
                let parts = split(line, " ")
                if len(parts) >= 3:
                    push(uvs, [tonumber(parts[1]), tonumber(parts[2])])
            if startswith(line, "f "):
                let parts = split(line, " ")
                # Triangulate face (fan from first vertex)
                let face_indices = []
                let fi = 1
                while fi < len(parts):
                    let vert_str = parts[fi]
                    if dict_has(vert_map, vert_str):
                        push(face_indices, vert_map[vert_str])
                    else:
                        # Parse v/vt/vn or v//vn or v
                        let slash_parts = split(vert_str, "/")
                        let vi = tonumber(slash_parts[0]) - 1
                        let ti = -1
                        let ni = -1
                        if len(slash_parts) >= 2:
                            if len(slash_parts[1]) > 0:
                                ti = tonumber(slash_parts[1]) - 1
                        if len(slash_parts) >= 3:
                            ni = tonumber(slash_parts[2]) - 1

                        # Emit vertex: pos, normal, uv
                        if vi >= 0:
                            if vi < len(positions):
                                let p = positions[vi]
                                push(vertices, p[0])
                                push(vertices, p[1])
                                push(vertices, p[2])
                            else:
                                push(vertices, 0.0)
                                push(vertices, 0.0)
                                push(vertices, 0.0)
                        if ni >= 0:
                            if ni < len(normals):
                                let n = normals[ni]
                                push(vertices, n[0])
                                push(vertices, n[1])
                                push(vertices, n[2])
                            else:
                                push(vertices, 0.0)
                                push(vertices, 1.0)
                                push(vertices, 0.0)
                        else:
                            push(vertices, 0.0)
                            push(vertices, 1.0)
                            push(vertices, 0.0)
                        if ti >= 0:
                            if ti < len(uvs):
                                let u = uvs[ti]
                                push(vertices, u[0])
                                push(vertices, u[1])
                            else:
                                push(vertices, 0.0)
                                push(vertices, 0.0)
                        else:
                            push(vertices, 0.0)
                            push(vertices, 0.0)

                        vert_map[vert_str] = vert_count
                        push(face_indices, vert_count)
                        vert_count = vert_count + 1
                    fi = fi + 1

                # Fan triangulation
                let ti2 = 1
                while ti2 < len(face_indices) - 1:
                    push(indices, face_indices[0])
                    push(indices, face_indices[ti2])
                    push(indices, face_indices[ti2 + 1])
                    ti2 = ti2 + 1
        if at_end:
            ci = ci + 1
            continue
        ci = ci + 1

    let result = {}
    result["vertices"] = vertices
    result["indices"] = indices
    result["vertex_count"] = vert_count
    result["index_count"] = len(indices)
    result["has_normals"] = len(normals) > 0
    result["has_uvs"] = len(uvs) > 0
    return result
