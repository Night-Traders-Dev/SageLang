gc_disable()
# octree.sage - Spatial octree for frustum culling and neighbor queries
# Stores object indices in a tree of axis-aligned bounding boxes

import math
from graphics.math3d import vec3, v3_sub, v3_length

let MAX_OBJECTS_PER_NODE = 16
let MAX_DEPTH = 8

# Create octree node
proc create_octree(center, half_size):
    let node = {}
    node["center"] = center
    node["half_size"] = half_size
    node["objects"] = []
    node["children"] = nil
    node["count"] = 0
    return node

# Check if point is inside node
proc point_in_node(node, pos):
    let c = node["center"]
    let h = node["half_size"]
    if pos[0] < c[0] - h:
        return false
    if pos[0] > c[0] + h:
        return false
    if pos[1] < c[1] - h:
        return false
    if pos[1] > c[1] + h:
        return false
    if pos[2] < c[2] - h:
        return false
    if pos[2] > c[2] + h:
        return false
    return true

# Get child octant index for a position
proc get_octant(node, pos):
    let c = node["center"]
    let idx = 0
    if pos[0] >= c[0]:
        idx = idx + 1
    if pos[1] >= c[1]:
        idx = idx + 2
    if pos[2] >= c[2]:
        idx = idx + 4
    return idx

# Subdivide a node into 8 children
proc subdivide(node):
    let c = node["center"]
    let h = node["half_size"] / 2
    let children = []
    let i = 0
    while i < 8:
        let ox = c[0] + h * (2 * (i - (i / 2) * 2) - 1)
        let oy = c[1] + h * (2 * ((i / 2) - (i / 4) * 2) - 1)
        let oz = c[2] + h * (2 * (i / 4) - 1)
        push(children, create_octree(vec3(ox, oy, oz), h))
        i = i + 1
    node["children"] = children

# Insert an object (index + position) into octree
proc octree_insert(node, obj_index, pos, depth):
    if point_in_node(node, pos) == false:
        return false

    if node["children"] == nil:
        if node["count"] < MAX_OBJECTS_PER_NODE:
            push(node["objects"], obj_index)
            node["count"] = node["count"] + 1
            return true
        if depth >= MAX_DEPTH:
            push(node["objects"], obj_index)
            node["count"] = node["count"] + 1
            return true
        # Subdivide
        subdivide(node)
        # Re-insert existing objects
        let old = node["objects"]
        node["objects"] = []
        node["count"] = 0
        # (simplified: objects stay in parent for now)
        let oi = 0
        while oi < len(old):
            push(node["objects"], old[oi])
            node["count"] = node["count"] + 1
            oi = oi + 1

    if node["children"] != nil:
        let octant = get_octant(node, pos)
        return octree_insert(node["children"][octant], obj_index, pos, depth + 1)

    push(node["objects"], obj_index)
    node["count"] = node["count"] + 1
    return true

# Query: find all objects within radius of point
proc octree_query_radius(node, center, radius, results):
    # Quick reject: if node is entirely outside query sphere
    let c = node["center"]
    let h = node["half_size"]
    let dx = 0
    if center[0] < c[0] - h:
        dx = center[0] - (c[0] - h)
    if center[0] > c[0] + h:
        dx = center[0] - (c[0] + h)
    let dy = 0
    if center[1] < c[1] - h:
        dy = center[1] - (c[1] - h)
    if center[1] > c[1] + h:
        dy = center[1] - (c[1] + h)
    let dz = 0
    if center[2] < c[2] - h:
        dz = center[2] - (c[2] - h)
    if center[2] > c[2] + h:
        dz = center[2] - (c[2] + h)
    let dist_sq = dx * dx + dy * dy + dz * dz
    if dist_sq > radius * radius:
        return nil

    # Add objects in this node
    let i = 0
    while i < len(node["objects"]):
        push(results, node["objects"][i])
        i = i + 1

    # Recurse into children
    if node["children"] != nil:
        i = 0
        while i < 8:
            octree_query_radius(node["children"][i], center, radius, results)
            i = i + 1

# Count total objects in tree
proc octree_count(node):
    let total = node["count"]
    if node["children"] != nil:
        let i = 0
        while i < 8:
            total = total + octree_count(node["children"][i])
            i = i + 1
    return total
