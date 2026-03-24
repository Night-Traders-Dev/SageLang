# Virtual Filesystem (VFS) abstraction layer
# Provides a uniform file/directory API that filesystem backends plug into.
# Each backend implements: open, read, readdir, stat, close

# File type constants
let VFS_FILE = 1
let VFS_DIR = 2
let VFS_SYMLINK = 3

# Open mode constants
let VFS_READ = 1
let VFS_WRITE = 2
let VFS_APPEND = 4
let VFS_CREATE = 8

# Seek origin constants
let SEEK_SET = 0
let SEEK_CUR = 1
let SEEK_END = 2

# Error constants
let VFS_OK = 0
let VFS_ENOENT = 2
let VFS_EIO = 5
let VFS_EACCES = 13
let VFS_EEXIST = 17
let VFS_ENOTDIR = 20
let VFS_EISDIR = 21
let VFS_ENOSPC = 28
let VFS_EROFS = 30

proc error_name(code):
    if code == 0:
        return "OK"
    if code == 2:
        return "ENOENT"
    if code == 5:
        return "EIO"
    if code == 13:
        return "EACCES"
    if code == 17:
        return "EEXIST"
    if code == 20:
        return "ENOTDIR"
    if code == 21:
        return "EISDIR"
    if code == 28:
        return "ENOSPC"
    if code == 30:
        return "EROFS"
    return "EUNKNOWN"

# Create a VFS mount table
proc create_vfs():
    let vfs = {}
    vfs["mounts"] = []
    vfs["cwd"] = "/"
    return vfs

# Register a filesystem backend at a mount point
# backend is a dict with: open, read, readdir, stat, close procs
proc mount(vfs, path, backend):
    let entry = {}
    entry["path"] = path
    entry["backend"] = backend
    push(vfs["mounts"], entry)
    return 0

# Unmount a filesystem
proc umount(vfs, path):
    let mounts = vfs["mounts"]
    let new_mounts = []
    for i in range(len(mounts)):
        if mounts[i]["path"] != path:
            push(new_mounts, mounts[i])
    vfs["mounts"] = new_mounts
    return 0

# Find the backend for a given path (longest prefix match)
proc resolve_mount(vfs, path):
    let best = nil
    let best_len = 0
    let mounts = vfs["mounts"]
    for i in range(len(mounts)):
        let mp = mounts[i]["path"]
        let mp_len = len(mp)
        if mp_len <= len(path):
            let is_match = true
            for j in range(mp_len):
                if path[j] != mp[j]:
                    is_match = false
                    j = mp_len
            if is_match and mp_len > best_len:
                best = mounts[i]
                best_len = mp_len
    return best

# Get the path relative to the mount point
proc relative_path(mount_path, full_path):
    let mp_len = len(mount_path)
    if mp_len >= len(full_path):
        return "/"
    let rel = ""
    for i in range(len(full_path) - mp_len):
        rel = rel + full_path[mp_len + i]
    if len(rel) == 0:
        return "/"
    if rel[0] != "/":
        rel = "/" + rel
    return rel

# Normalize a path (remove double slashes, resolve . and ..)
proc normalize_path(path):
    if len(path) == 0:
        return "/"
    # Split by /
    let parts = []
    let current = ""
    for i in range(len(path)):
        if path[i] == "/":
            if len(current) > 0:
                push(parts, current)
            current = ""
        else:
            current = current + path[i]
    if len(current) > 0:
        push(parts, current)
    # Resolve . and ..
    let resolved = []
    for i in range(len(parts)):
        if parts[i] == ".":
            let skip = true
        if parts[i] == "..":
            if len(resolved) > 0:
                pop(resolved)
        if parts[i] != "." and parts[i] != "..":
            push(resolved, parts[i])
    # Rebuild
    if len(resolved) == 0:
        return "/"
    let result = ""
    for i in range(len(resolved)):
        result = result + "/" + resolved[i]
    return result

# Join two paths
proc join_path(base, rel):
    if len(rel) > 0 and rel[0] == "/":
        return normalize_path(rel)
    if base == "/":
        return normalize_path("/" + rel)
    return normalize_path(base + "/" + rel)

# Get parent directory path
proc dirname(path):
    let norm = normalize_path(path)
    if norm == "/":
        return "/"
    let last_slash = 0
    for i in range(len(norm)):
        if norm[i] == "/":
            last_slash = i
    if last_slash == 0:
        return "/"
    let result = ""
    for i in range(last_slash):
        result = result + norm[i]
    return result

# Get filename component
proc basename(path):
    let norm = normalize_path(path)
    if norm == "/":
        return "/"
    let last_slash = 0
    for i in range(len(norm)):
        if norm[i] == "/":
            last_slash = i
    let result = ""
    for i in range(len(norm) - last_slash - 1):
        result = result + norm[last_slash + 1 + i]
    return result

# Split path into directory and filename
proc split_path(path):
    let result = {}
    result["dir"] = dirname(path)
    result["name"] = basename(path)
    return result

# Get file extension
proc extension(path):
    let name = basename(path)
    let last_dot = -1
    for i in range(len(name)):
        if name[i] == ".":
            last_dot = i
    if last_dot < 1:
        return ""
    let ext = ""
    for i in range(len(name) - last_dot - 1):
        ext = ext + name[last_dot + 1 + i]
    return ext

# Create a stat result
proc make_stat(file_type, size, name):
    let st = {}
    st["type"] = file_type
    st["size"] = size
    st["name"] = name
    st["is_file"] = file_type == 1
    st["is_dir"] = file_type == 2
    return st

# Create a directory entry
proc make_dirent(name, file_type, size):
    let de = {}
    de["name"] = name
    de["type"] = file_type
    de["size"] = size
    return de

# Create a file handle
proc make_handle(backend, internal, path, mode):
    let fh = {}
    fh["backend"] = backend
    fh["internal"] = internal
    fh["path"] = path
    fh["mode"] = mode
    fh["position"] = 0
    fh["closed"] = false
    return fh

# VFS open
proc vfs_open(vfs, path, mode):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return nil
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "open"):
        return nil
    let internal = backend["open"](rel, mode)
    if internal == nil:
        return nil
    return make_handle(backend, internal, norm, mode)

# VFS read
proc vfs_read(handle, size):
    if handle["closed"]:
        return nil
    let backend = handle["backend"]
    if not dict_has(backend, "read"):
        return nil
    let data = backend["read"](handle["internal"], handle["position"], size)
    if data != nil:
        handle["position"] = handle["position"] + len(data)
    return data

# VFS seek
proc vfs_seek(handle, offset, whence):
    if whence == 0:
        handle["position"] = offset
    if whence == 1:
        handle["position"] = handle["position"] + offset
    if whence == 2:
        let st = handle["backend"]["stat"](handle["internal"])
        if st != nil:
            handle["position"] = st["size"] + offset
    return handle["position"]

# VFS tell
proc vfs_tell(handle):
    return handle["position"]

# VFS close
proc vfs_close(handle):
    handle["closed"] = true
    let backend = handle["backend"]
    if dict_has(backend, "close"):
        backend["close"](handle["internal"])
    return 0

# VFS stat
proc vfs_stat(vfs, path):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return nil
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "stat"):
        return nil
    return backend["stat"](rel)

# VFS readdir
proc vfs_readdir(vfs, path):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return nil
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "readdir"):
        return nil
    return backend["readdir"](rel)

# Create a simple in-memory filesystem backend for testing
proc create_memfs():
    let fs = {}
    fs["files"] = {}
    fs["dirs"] = {}
    fs["dirs"]["/"] = []

    proc memfs_open(path, mode):
        if dict_has(fs["files"], path):
            return path
        if (mode & 8) != 0:
            fs["files"][path] = []
            return path
        return nil

    proc memfs_read(handle, pos, size):
        if not dict_has(fs["files"], handle):
            return nil
        let data = fs["files"][handle]
        let result = []
        let i = pos
        while i < pos + size and i < len(data):
            push(result, data[i])
            i = i + 1
        return result

    proc memfs_stat(path):
        if dict_has(fs["files"], path):
            let st = {}
            st["type"] = 1
            st["size"] = len(fs["files"][path])
            st["name"] = path
            st["is_file"] = true
            st["is_dir"] = false
            return st
        if dict_has(fs["dirs"], path):
            let st = {}
            st["type"] = 2
            st["size"] = 0
            st["name"] = path
            st["is_file"] = false
            st["is_dir"] = true
            return st
        return nil

    proc memfs_readdir(path):
        if not dict_has(fs["dirs"], path):
            return nil
        return fs["dirs"][path]

    proc memfs_close(handle):
        return 0

    let backend = {}
    backend["open"] = memfs_open
    backend["read"] = memfs_read
    backend["stat"] = memfs_stat
    backend["readdir"] = memfs_readdir
    backend["close"] = memfs_close
    backend["_fs"] = fs
    return backend

# Helper: write bytes to a memfs file
proc memfs_write(backend, path, data):
    backend["_fs"]["files"][path] = data
    # Update parent dir listing
    let dirs = backend["_fs"]["dirs"]
    if not dict_has(dirs, "/"):
        dirs["/"] = []

# Helper: create a directory in memfs
proc memfs_mkdir(backend, path):
    let dirs = backend["_fs"]["dirs"]
    dirs[path] = []
