gc_disable()
# -----------------------------------------
# gltf.sage - P13: glTF 2.0 Model Loading
# Minimal glTF JSON parser for mesh + material extraction
# Uses the existing json library for parsing
# -----------------------------------------

import gpu
from mesh import VERTEX_STRIDE

# ============================================================================
# glTF file loading (JSON portion)
# ============================================================================
import io

proc load_gltf(path):
    let content = io.readfile(path)
    if content == nil:
        print "gltf: failed to read " + path
        return nil

    # Parse JSON
    from json import cJSON_Parse, cJSON_ToSage
    let root = cJSON_Parse(content)
    if root == nil:
        print "gltf: failed to parse JSON"
        return nil
    let data = cJSON_ToSage(root)
    return data

# ============================================================================
# Extract mesh data from glTF
# ============================================================================
proc gltf_extract_mesh(gltf, mesh_index):
    if gltf == nil:
        return nil
    if dict_has(gltf, "meshes") == false:
        return nil

    let meshes = gltf["meshes"]
    if mesh_index >= len(meshes):
        return nil

    let mesh = meshes[mesh_index]
    let result = {}
    result["name"] = ""
    if dict_has(mesh, "name"):
        result["name"] = mesh["name"]

    # Get primitive 0
    if dict_has(mesh, "primitives") == false:
        return nil
    let prim = mesh["primitives"][0]

    result["has_indices"] = dict_has(prim, "indices")
    result["attributes"] = {}
    if dict_has(prim, "attributes"):
        result["attributes"] = prim["attributes"]

    # Material index
    result["material_index"] = -1
    if dict_has(prim, "material"):
        result["material_index"] = prim["material"]

    return result

# ============================================================================
# Extract material data from glTF
# ============================================================================
proc gltf_extract_material(gltf, material_index):
    if gltf == nil:
        return nil
    if dict_has(gltf, "materials") == false:
        return nil

    let materials = gltf["materials"]
    if material_index >= len(materials):
        return nil

    let mat = materials[material_index]
    let result = {}
    result["name"] = ""
    if dict_has(mat, "name"):
        result["name"] = mat["name"]

    # PBR metallic roughness
    result["base_color"] = [1.0, 1.0, 1.0, 1.0]
    result["metallic"] = 1.0
    result["roughness"] = 1.0

    if dict_has(mat, "pbrMetallicRoughness"):
        let pbr = mat["pbrMetallicRoughness"]
        if dict_has(pbr, "baseColorFactor"):
            result["base_color"] = pbr["baseColorFactor"]
        if dict_has(pbr, "metallicFactor"):
            result["metallic"] = pbr["metallicFactor"]
        if dict_has(pbr, "roughnessFactor"):
            result["roughness"] = pbr["roughnessFactor"]

    # Emissive
    result["emissive"] = [0.0, 0.0, 0.0]
    if dict_has(mat, "emissiveFactor"):
        result["emissive"] = mat["emissiveFactor"]

    return result

# ============================================================================
# Count meshes and materials in a glTF file
# ============================================================================
proc gltf_mesh_count(gltf):
    if gltf == nil:
        return 0
    if dict_has(gltf, "meshes") == false:
        return 0
    return len(gltf["meshes"])

proc gltf_material_count(gltf):
    if gltf == nil:
        return 0
    if dict_has(gltf, "materials") == false:
        return 0
    return len(gltf["materials"])

# ============================================================================
# Scene info
# ============================================================================
proc gltf_info(gltf):
    if gltf == nil:
        print "gltf: nil"
        return nil
    print "glTF Scene:"
    if dict_has(gltf, "asset"):
        let asset = gltf["asset"]
        if dict_has(asset, "generator"):
            print "  Generator: " + str(asset["generator"])
        if dict_has(asset, "version"):
            print "  Version: " + str(asset["version"])
    print "  Meshes: " + str(gltf_mesh_count(gltf))
    print "  Materials: " + str(gltf_material_count(gltf))
    if dict_has(gltf, "nodes"):
        print "  Nodes: " + str(len(gltf["nodes"]))
    if dict_has(gltf, "textures"):
        print "  Textures: " + str(len(gltf["textures"]))
