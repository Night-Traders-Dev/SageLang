gc_disable()
# Build configuration and project management
# Provides project metadata, dependency declaration, and build task definitions

# ============================================================================
# Project definition
# ============================================================================

proc create_project(name, version):
    let proj = {}
    proj["name"] = name
    proj["version"] = version
    proj["description"] = ""
    proj["author"] = ""
    proj["license"] = ""
    proj["dependencies"] = []
    proj["dev_dependencies"] = []
    proj["scripts"] = {}
    proj["sources"] = []
    proj["entry_point"] = ""
    proj["build_dir"] = "build"
    proj["targets"] = {}
    return proj

proc set_description(proj, desc):
    proj["description"] = desc

proc set_author(proj, author):
    proj["author"] = author

proc set_license(proj, license):
    proj["license"] = license

proc set_entry(proj, entry):
    proj["entry_point"] = entry

# ============================================================================
# Dependencies
# ============================================================================

proc add_dep(proj, name, version):
    let dep = {}
    dep["name"] = name
    dep["version"] = version
    push(proj["dependencies"], dep)

proc add_dev_dep(proj, name, version):
    let dep = {}
    dep["name"] = name
    dep["version"] = version
    push(proj["dev_dependencies"], dep)

# ============================================================================
# Build targets
# ============================================================================

proc add_target(proj, name, target_type, sources):
    let target = {}
    target["name"] = name
    target["type"] = target_type
    target["sources"] = sources
    target["flags"] = []
    target["deps"] = []
    proj["targets"][name] = target

proc add_script(proj, name, command):
    proj["scripts"][name] = command

# ============================================================================
# Version parsing (semver)
# ============================================================================

proc parse_version(version_str):
    let parts = []
    let current = ""
    for i in range(len(version_str)):
        if version_str[i] == ".":
            push(parts, tonumber(current))
            current = ""
        else:
            current = current + version_str[i]
    if len(current) > 0:
        push(parts, tonumber(current))
    let ver = {}
    ver["major"] = 0
    ver["minor"] = 0
    ver["patch"] = 0
    if len(parts) >= 1:
        ver["major"] = parts[0]
    if len(parts) >= 2:
        ver["minor"] = parts[1]
    if len(parts) >= 3:
        ver["patch"] = parts[2]
    ver["string"] = version_str
    return ver

proc version_compare(a, b):
    if a["major"] != b["major"]:
        return a["major"] - b["major"]
    if a["minor"] != b["minor"]:
        return a["minor"] - b["minor"]
    return a["patch"] - b["patch"]

proc version_gte(a, b):
    return version_compare(a, b) >= 0

proc bump_major(ver):
    return parse_version(str(ver["major"] + 1) + ".0.0")

proc bump_minor(ver):
    return parse_version(str(ver["major"]) + "." + str(ver["minor"] + 1) + ".0")

proc bump_patch(ver):
    return parse_version(str(ver["major"]) + "." + str(ver["minor"]) + "." + str(ver["patch"] + 1))

# ============================================================================
# Project serialization
# ============================================================================

proc to_string(proj):
    let nl = chr(10)
    let out = "[project]" + nl
    out = out + "name = " + chr(34) + proj["name"] + chr(34) + nl
    out = out + "version = " + chr(34) + proj["version"] + chr(34) + nl
    if len(proj["description"]) > 0:
        out = out + "description = " + chr(34) + proj["description"] + chr(34) + nl
    if len(proj["author"]) > 0:
        out = out + "author = " + chr(34) + proj["author"] + chr(34) + nl
    if len(proj["entry_point"]) > 0:
        out = out + "entry = " + chr(34) + proj["entry_point"] + chr(34) + nl
    if len(proj["dependencies"]) > 0:
        out = out + nl + "[dependencies]" + nl
        let deps = proj["dependencies"]
        for i in range(len(deps)):
            out = out + deps[i]["name"] + " = " + chr(34) + deps[i]["version"] + chr(34) + nl
    return out
