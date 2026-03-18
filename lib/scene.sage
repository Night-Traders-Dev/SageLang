gc_disable()
# -----------------------------------------
# scene.sage - Feature 12: Scene Graph
# Dict-based node hierarchy with transforms
# -----------------------------------------

from math3d import mat4_identity, mat4_mul

# Create a scene node
proc create_node(name):
    let n = {}
    n["name"] = name
    n["transform"] = mat4_identity()
    n["children"] = []
    n["parent"] = nil
    n["mesh"] = nil
    n["material"] = nil
    n["visible"] = true
    n["user_data"] = nil
    return n

# Add child to parent
proc add_child(parent, child):
    push(parent["children"], child)
    child["parent"] = parent

# Remove child by name
proc remove_child(parent, child):
    let child_name = child["name"]
    let new_children = []
    let i = 0
    while i < len(parent["children"]):
        let c = parent["children"][i]
        if c["name"] != child_name:
            push(new_children, c)
        i = i + 1
    parent["children"] = new_children
    child["parent"] = nil

# Compute world transform (walk up parent chain)
proc world_transform(node):
    let result = node["transform"]
    let current = node["parent"]
    while current != nil:
        result = mat4_mul(current["transform"], result)
        current = current["parent"]
    return result

# Visit all nodes (depth-first)
proc traverse(node, visitor):
    if node["visible"] == false:
        return nil
    visitor(node)
    let i = 0
    while i < len(node["children"]):
        traverse(node["children"][i], visitor)
        i = i + 1

# Count nodes in subtree
proc node_count(node):
    let count = 1
    let i = 0
    while i < len(node["children"]):
        count = count + node_count(node["children"][i])
        i = i + 1
    return count

# Find node by name (DFS)
proc find_node(root, name):
    if root["name"] == name:
        return root
    let i = 0
    while i < len(root["children"]):
        let found = find_node(root["children"][i], name)
        if found != nil:
            return found
        i = i + 1
    return nil
