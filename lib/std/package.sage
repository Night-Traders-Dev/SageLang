# Sage Package Manifest (sage.toml) support
# Provides functions to read and validate project configuration

import io

proc parse_toml_line(line):
    # Simple TOML line parser: key = "value" or key = number or [section]
    let trimmed = line
    if len(trimmed) == 0:
        return nil
    if trimmed[0] == "#":
        return nil
    if trimmed[0] == "[":
        let end = len(trimmed) - 1
        if end > 0:
            let section = ""
            let i = 1
            while i < len(trimmed):
                if trimmed[i] == "]":
                    return {"type": "section", "name": section}
                section = section + trimmed[i]
                i = i + 1
        return nil
    # key = value
    let parts = split(trimmed, "=")
    if len(parts) < 2:
        return nil
    let key = parts[0]
    # Strip whitespace from key (simple trim)
    while len(key) > 0 and key[len(key) - 1] == " ":
        key = slice(key, 0, len(key) - 1)
    while len(key) > 0 and key[0] == " ":
        key = slice(key, 1, len(key))
    let val = parts[1]
    while len(val) > 0 and val[0] == " ":
        val = slice(val, 1, len(val))
    while len(val) > 0 and val[len(val) - 1] == " ":
        val = slice(val, 0, len(val) - 1)
    # Strip quotes
    if len(val) >= 2 and val[0] == chr(34):
        val = slice(val, 1, len(val) - 1)
    return {"type": "kv", "key": key, "value": val}

proc read_manifest(path):
    # Read a sage.toml file and return a dict
    if not io.exists(path):
        return nil
    let content = io.readfile(path)
    let lines = split(content, chr(10))
    let result = {}
    let current_section = "package"
    let i = 0
    while i < len(lines):
        let parsed = parse_toml_line(lines[i])
        if parsed != nil:
            if parsed["type"] == "section":
                current_section = parsed["name"]
            if parsed["type"] == "kv":
                let full_key = current_section + "." + parsed["key"]
                result[full_key] = parsed["value"]
        i = i + 1
    return result

proc init_manifest(name, version, description):
    # Generate a new sage.toml content
    let nl = chr(10)
    let q = chr(34)
    let content = "[package]" + nl
    content = content + "name = " + q + name + q + nl
    content = content + "version = " + q + version + q + nl
    content = content + "description = " + q + description + q + nl
    content = content + nl
    content = content + "[dependencies]" + nl
    return content
