gc_disable()

# tmpfs.sage — In-memory filesystem
#
# Fully functional RAM-based filesystem with directories, files, symlinks,
# permissions, timestamps, and size limits. No backing store.

# File types
let T_FILE = 1
let T_DIR = 2
let T_SYMLINK = 3
let T_DEVICE = 4

# Default permissions
let PERM_FILE = 420
let PERM_DIR = 493
let PERM_EXEC = 493

# ========== Inode ==========

proc _next_ino(fs):
    fs["next_ino"] = fs["next_ino"] + 1
    return fs["next_ino"]
end

proc _create_inode(fs, ftype, mode, uid, gid):
    let ino = _next_ino(fs)
    let node = {}
    node["ino"] = ino
    node["type"] = ftype
    node["mode"] = mode
    node["uid"] = uid
    node["gid"] = gid
    node["size"] = 0
    node["data"] = ""
    node["children"] = {}
    node["target"] = ""
    node["nlinks"] = 1
    node["ctime"] = 0
    node["mtime"] = 0
    node["atime"] = 0
    node["dev_major"] = 0
    node["dev_minor"] = 0
    fs["inodes"][str(ino)] = node
    return node
end

# ========== Filesystem ==========

proc create_tmpfs(max_size):
    let fs = {}
    fs["max_size"] = max_size
    fs["used_size"] = 0
    fs["next_ino"] = 0
    fs["inodes"] = {}
    # Create root directory
    let root = _create_inode(fs, T_DIR, PERM_DIR, 0, 0)
    root["children"]["."] = root["ino"]
    root["children"][".."] = root["ino"]
    root["nlinks"] = 2
    fs["root_ino"] = root["ino"]
    return fs
end

# ========== Path Resolution ==========

proc _split_path(path):
    let parts = []
    let current = ""
    for i in range(len(path)):
        if path[i] == "/":
            if len(current) > 0:
                push(parts, current)
                current = ""
            end
        else:
            current = current + path[i]
        end
    end
    if len(current) > 0:
        push(parts, current)
    end
    return parts
end

proc _resolve(fs, path):
    let parts = _split_path(path)
    let current = fs["inodes"][str(fs["root_ino"])]
    for i in range(len(parts)):
        if current["type"] != T_DIR:
            return nil
        end
        if not dict_has(current["children"], parts[i]):
            return nil
        end
        let child_ino = current["children"][parts[i]]
        current = fs["inodes"][str(child_ino)]
        # Follow symlinks
        if current["type"] == T_SYMLINK:
            current = _resolve(fs, current["target"])
            if current == nil:
                return nil
            end
        end
    end
    return current
end

proc _resolve_parent(fs, path):
    let parts = _split_path(path)
    if len(parts) == 0:
        return nil
    end
    let parent_parts = []
    for i in range(len(parts) - 1):
        push(parent_parts, parts[i])
    end
    let parent_path = "/"
    for i in range(len(parent_parts)):
        parent_path = parent_path + parent_parts[i] + "/"
    end
    let parent = _resolve(fs, parent_path)
    let name = parts[len(parts) - 1]
    let result = {}
    result["parent"] = parent
    result["name"] = name
    return result
end

# ========== File Operations ==========

proc create_file(fs, path, data, mode):
    let r = _resolve_parent(fs, path)
    if r == nil:
        return nil
    end
    let parent = r["parent"]
    let name = r["name"]
    if parent == nil or parent["type"] != T_DIR:
        return nil
    end
    if dict_has(parent["children"], name):
        return nil
    end
    # Check size limit
    if fs["used_size"] + len(data) > fs["max_size"]:
        return nil
    end
    let node = _create_inode(fs, T_FILE, mode, 0, 0)
    node["data"] = data
    node["size"] = len(data)
    parent["children"][name] = node["ino"]
    fs["used_size"] = fs["used_size"] + len(data)
    return node
end

proc mkdir(fs, path, mode):
    let r = _resolve_parent(fs, path)
    if r == nil:
        return nil
    end
    let parent = r["parent"]
    let name = r["name"]
    if parent == nil or parent["type"] != T_DIR:
        return nil
    end
    if dict_has(parent["children"], name):
        return nil
    end
    let node = _create_inode(fs, T_DIR, mode, 0, 0)
    node["children"]["."] = node["ino"]
    node["children"][".."] = parent["ino"]
    node["nlinks"] = 2
    parent["children"][name] = node["ino"]
    parent["nlinks"] = parent["nlinks"] + 1
    return node
end

proc symlink(fs, path, target):
    let r = _resolve_parent(fs, path)
    if r == nil:
        return nil
    end
    let parent = r["parent"]
    let name = r["name"]
    if parent == nil:
        return nil
    end
    let node = _create_inode(fs, T_SYMLINK, 511, 0, 0)
    node["target"] = target
    node["size"] = len(target)
    parent["children"][name] = node["ino"]
    return node
end

proc read_file(fs, path):
    let node = _resolve(fs, path)
    if node == nil:
        return nil
    end
    if node["type"] != T_FILE:
        return nil
    end
    return node["data"]
end

proc write_file(fs, path, data):
    let node = _resolve(fs, path)
    if node == nil:
        # Create file
        return create_file(fs, path, data, PERM_FILE)
    end
    if node["type"] != T_FILE:
        return nil
    end
    let old_size = node["size"]
    if fs["used_size"] - old_size + len(data) > fs["max_size"]:
        return nil
    end
    fs["used_size"] = fs["used_size"] - old_size + len(data)
    node["data"] = data
    node["size"] = len(data)
    return node
end

proc delete(fs, path):
    let r = _resolve_parent(fs, path)
    if r == nil:
        return false
    end
    let parent = r["parent"]
    let name = r["name"]
    if not dict_has(parent["children"], name):
        return false
    end
    let ino = parent["children"][name]
    let node = fs["inodes"][str(ino)]
    if node["type"] == T_DIR:
        # Only delete empty dirs
        let child_count = 0
        let keys = dict_keys(node["children"])
        for i in range(len(keys)):
            if keys[i] != "." and keys[i] != "..":
                child_count = child_count + 1
            end
        end
        if child_count > 0:
            return false
        end
        parent["nlinks"] = parent["nlinks"] - 1
    end
    if node["type"] == T_FILE:
        fs["used_size"] = fs["used_size"] - node["size"]
    end
    dict_delete(parent["children"], name)
    dict_delete(fs["inodes"], str(ino))
    return true
end

proc rename(fs, old_path, new_path):
    let node = _resolve(fs, old_path)
    if node == nil:
        return false
    end
    let old_r = _resolve_parent(fs, old_path)
    let new_r = _resolve_parent(fs, new_path)
    if old_r == nil or new_r == nil:
        return false
    end
    let old_parent = old_r["parent"]
    let new_parent = new_r["parent"]
    if new_parent == nil or new_parent["type"] != T_DIR:
        return false
    end
    new_parent["children"][new_r["name"]] = node["ino"]
    dict_delete(old_parent["children"], old_r["name"])
    if node["type"] == T_DIR:
        node["children"][".."] = new_parent["ino"]
    end
    return true
end

# ========== Directory Listing ==========

proc listdir(fs, path):
    let node = _resolve(fs, path)
    if node == nil:
        return nil
    end
    if node["type"] != T_DIR:
        return nil
    end
    let entries = []
    let keys = dict_keys(node["children"])
    for i in range(len(keys)):
        if keys[i] != "." and keys[i] != "..":
            let child_ino = node["children"][keys[i]]
            let child = fs["inodes"][str(child_ino)]
            let e = {}
            e["name"] = keys[i]
            e["type"] = child["type"]
            e["size"] = child["size"]
            e["ino"] = child["ino"]
            push(entries, e)
        end
    end
    return entries
end

proc stat(fs, path):
    let node = _resolve(fs, path)
    if node == nil:
        return nil
    end
    let info = {}
    info["ino"] = node["ino"]
    info["type"] = node["type"]
    info["mode"] = node["mode"]
    info["size"] = node["size"]
    info["uid"] = node["uid"]
    info["gid"] = node["gid"]
    info["nlinks"] = node["nlinks"]
    if node["type"] == T_FILE:
        info["type_name"] = "file"
    end
    if node["type"] == T_DIR:
        info["type_name"] = "directory"
    end
    if node["type"] == T_SYMLINK:
        info["type_name"] = "symlink"
        info["target"] = node["target"]
    end
    return info
end

proc exists(fs, path):
    return _resolve(fs, path) != nil
end

# ========== Filesystem Info ==========

proc df(fs):
    let info = {}
    info["total"] = fs["max_size"]
    info["used"] = fs["used_size"]
    info["free"] = fs["max_size"] - fs["used_size"]
    info["inodes"] = len(dict_keys(fs["inodes"]))
    return info
end

# ========== Recursive Operations ==========

proc mkdir_p(fs, path):
    let parts = _split_path(path)
    let current_path = ""
    for i in range(len(parts)):
        current_path = current_path + "/" + parts[i]
        if not exists(fs, current_path):
            mkdir(fs, current_path, PERM_DIR)
        end
    end
    return exists(fs, path)
end

proc tree(fs, path, indent):
    let entries = listdir(fs, path)
    if entries == nil:
        return ""
    end
    let result = ""
    let nl = chr(10)
    for i in range(len(entries)):
        let e = entries[i]
        let prefix = ""
        for j in range(indent):
            prefix = prefix + "  "
        end
        if e["type"] == T_DIR:
            result = result + prefix + e["name"] + "/" + nl
            let subpath = path
            if not endswith(path, "/"):
                subpath = subpath + "/"
            end
            result = result + tree(fs, subpath + e["name"], indent + 1)
        else:
            result = result + prefix + e["name"] + " (" + str(e["size"]) + ")" + nl
        end
    end
    return result
end
