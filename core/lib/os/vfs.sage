gc_disable()
# Virtual Filesystem (VFS) abstraction layer
# Provides a uniform file/directory API that filesystem backends plug into.
# Each backend implements: open, read, readdir, stat, close

import os.errno as errno

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

# Error constants (for backward compatibility)
let VFS_OK = 0
let VFS_ENOENT = 2
let VFS_EIO = 5
let VFS_EACCES = 13
let VFS_EEXIST = 17
let VFS_ENOTDIR = 20
let VFS_EISDIR = 21
let VFS_ENOSPC = 28
let VFS_EROFS = 30

# # Returns a human-readable string for the given VFS error code.

proc error_name(code):
    return errno.strerror(code)
end

# Create a VFS mount table

proc create_vfs():
    let vfs = {}
    vfs["mounts"] = []
    vfs["cwd"] = "/"
    return vfs
end

# Register a filesystem backend at a mount point
# backend is a dict with: open, read, readdir, stat, close procs

proc mount(vfs, path, backend):
    let entry = {}
    entry["path"] = path
    entry["backend"] = backend
    push(vfs["mounts"], entry)
    return 0
end

# Unmount a filesystem

proc umount(vfs, path):
    let mounts = vfs["mounts"]
    let new_mounts = []
    for i in range(len(mounts)):
        if mounts[i]["path"] != path:
            push(new_mounts, mounts[i])
        end
    end
    vfs["mounts"] = new_mounts
    return 0
end

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
                end
            end
            if is_match and mp_len > best_len:
                best = mounts[i]
                best_len = mp_len
            end
        end
    end
    return best
end

# # Returns the path relative to the mount point.

proc relative_path(mount_path, full_path):
    let mp_len = len(mount_path)
    if mp_len >= len(full_path):
        return "/"
    end
    # Ensure prefix match
    let i = 0
    while i < mp_len:
        if mount_path[i] != full_path[i]:
            return full_path
        end
        i = i + 1
    end
    let rel = slice(full_path, mp_len, len(full_path))
    if len(rel) == 0:
        return "/"
    end
    if rel[0] != "/":
        rel = "/" + rel
    end
    return rel
end

# # Normalizes a path (resolves . and ..).

proc normalize_path(path):
    if len(path) == 0:
        return "/"
    end
    # Split by /
    let raw_parts = split(path, "/")
    let parts = []
    for p in raw_parts:
        if p != "":
            push(parts, p)
        end
    end
    # Resolve . and ..
    let resolved = []
    for part in parts:
        if part == "..":
            if len(resolved) > 0:
                pop(resolved)
            end
        elif part != ".":
            push(resolved, part)
        end
    end
    # Rebuild
    if len(resolved) == 0:
        return "/"
    end
    return "/" + join(resolved, "/")
end

# # Joins two path components.

proc join_path(base, rel):
    if len(rel) > 0 and rel[0] == "/":
        return normalize_path(rel)
    end
    if base == "/":
        return normalize_path("/" + rel)
    end
    return normalize_path(base + "/" + rel)
end

# # Returns the parent directory of a path.

proc dirname(path):
    let norm = normalize_path(path)
    if norm == "/":
        return "/"
    end
    let d_parts = split(norm, "/")
    if len(d_parts) <= 2:
        return "/"
    end
    pop(d_parts)
    return join(d_parts, "/")
end

# # Returns the filename component of a path.

proc basename(path):
    let norm = normalize_path(path)
    if norm == "/":
        return "/"
    end
    let b_parts = split(norm, "/")
    return b_parts[len(b_parts) - 1]
end

# Split path into directory and filename

proc split_path(path):
    let result = {}
    result["dir"] = dirname(path)
    result["name"] = basename(path)
    return result
end

# # Returns the file extension.

proc extension(path):
    let name = basename(path)
    let e_parts = split(name, ".")
    if len(e_parts) < 2:
        return ""
    end
    # If it starts with a dot and has only one dot, it's a hidden file without extension
    if len(e_parts) == 2 and name[0] == ".":
        return ""
    end
    return e_parts[len(e_parts) - 1]
end

# Create a stat result

proc make_stat(file_type, size, name):
    let st = {}
    st["type"] = file_type
    st["size"] = size
    st["name"] = name
    st["is_file"] = file_type == 1
    st["is_dir"] = file_type == 2
    return st
end

# Create a directory entry

proc make_dirent(name, file_type, size):
    let de = {}
    de["name"] = name
    de["type"] = file_type
    de["size"] = size
    return de
end

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
end

# VFS open

proc vfs_open(vfs, path, mode):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return nil
    end
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "open"):
        return nil
    end
    let internal = backend["open"](rel, mode)
    if internal == nil:
        return nil
    end
    let h = make_handle(backend, internal, norm, mode)
    if (mode & VFS_APPEND) != 0:
        vfs_seek(h, 0, SEEK_END)
    end
    return h
end

# VFS read

proc vfs_read(handle, size):
    if handle["closed"]:
        return nil
    end
    let backend = handle["backend"]
    if not dict_has(backend, "read"):
        return nil
    end
    let data = backend["read"](handle["internal"], handle["position"], size)
    if data != nil:
        handle["position"] = handle["position"] + len(data)
    end
    return data
end

# VFS write

proc vfs_write(handle, data):
    if handle["closed"]:
        return - 1
    end
    let backend = handle["backend"]
    if not dict_has(backend, "write"):
        return - 1
    end
    let written = backend["write"](handle["internal"], handle["position"], data)
    if written >= 0:
        handle["position"] = handle["position"] + written
    end
    return written
end

# VFS seek

proc vfs_seek(handle, offset, whence):
    if whence == 0:
        handle["position"] = offset
    end
    if whence == 1:
        handle["position"] = handle["position"] + offset
    end
    if whence == 2:
        let st = handle["backend"]["stat"](handle["internal"])
        if st != nil:
            handle["position"] = st["size"] + offset
        end
    end
    return handle["position"]
end

# VFS tell

proc vfs_tell(handle):
    return handle["position"]
end

# VFS close

proc vfs_close(handle):
    handle["closed"] = true
    let backend = handle["backend"]
    if dict_has(backend, "close"):
        backend["close"](handle["internal"])
    end
    return 0
end

# # Checks if a path exists.

proc vfs_exists(vfs, path):
    return vfs_stat(vfs, path) != nil
end

# # Checks if a path is a file.

proc vfs_is_file(vfs, path):
    let vif_st = vfs_stat(vfs, path)
    if vif_st != nil:
        return vif_st["type"] == VFS_FILE
    end
    return false
end

# # Checks if a path is a directory.

proc vfs_is_dir(vfs, path):
    let vid_st = vfs_stat(vfs, path)
    if vid_st != nil:
        return vid_st["type"] == VFS_DIR
    end
    return false
end

# VFS stat

proc vfs_stat(vfs, path):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return nil
    end
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "stat"):
        return nil
    end
    return backend["stat"](rel)
end

# VFS readdir

proc vfs_readdir(vfs, path):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return nil
    end
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "readdir"):
        return nil
    end
    return backend["readdir"](rel)
end

# VFS mkdir

proc vfs_mkdir(vfs, path):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return - 1
    end
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "mkdir"):
        return - 1
    end
    return backend["mkdir"](rel)
end

# VFS unlink

proc vfs_unlink(vfs, path):
    let norm = normalize_path(path)
    let m = resolve_mount(vfs, norm)
    if m == nil:
        return - 1
    end
    let rel = relative_path(m["path"], norm)
    let backend = m["backend"]
    if not dict_has(backend, "unlink"):
        return - 1
    end
    return backend["unlink"](rel)
end

# VFS rmdir

proc vfs_rmdir(vfs, path):
    let vrm_norm = normalize_path(path)
    let vrm_m = resolve_mount(vfs, vrm_norm)
    if vrm_m == nil:
        return - 1
    end
    let vrm_rel = relative_path(vrm_m["path"], vrm_norm)
    let vrm_backend = vrm_m["backend"]
    if not dict_has(vrm_backend, "rmdir"):
        return - 1
    end
    return vrm_backend["rmdir"](vrm_rel)
end

# Create a simple in-memory filesystem backend for testing

proc create_memfs():
    let fs = {}
    fs["files"] = {}
    fs["dirs"] = {}
    fs["dirs"]["/"] = []

    proc memfs_open(path, mode):
        if dict_has(fs["files"], path):
            return path
        end
        if (mode & VFS_CREATE) != 0:
            fs["files"][path] = []
            # Update parent
            let d = dirname(path)
            let n = basename(path)
            if dict_has(fs["dirs"], d):
                push(fs["dirs"][d], make_dirent(n, VFS_FILE, 0))
            end
            return path
        end
        return nil
    end

    proc memfs_read(handle, pos, size):
        if not dict_has(fs["files"], handle):
            return nil
        end
        let data = fs["files"][handle]
        let result = []
        let i = pos
        while i < pos + size and i < len(data):
            push(result, data[i])
            i = i + 1
        end
        return result
    end

    proc memfs_write(handle, pos, data):
        if not dict_has(fs["files"], handle):
            return - 1
        end
        let current = fs["files"][handle]
        # Simplistic implementation: overwrite or append if pos is at end
        if pos == len(current):
            array_extend(current, data)
        else:
            # Overwrite existing
            let i = 0
            while i < len(data):
                if pos + i < len(current):
                    current[pos + i] = data[i]
                else:
                    push(current, data[i])
                end
                i = i + 1
            end
        end
        return len(data)
    end

    proc memfs_stat(path):
        if dict_has(fs["files"], path):
            let st = {}
            st["type"] = 1
            st["size"] = len(fs["files"][path])
            st["name"] = path
            st["is_file"] = true
            st["is_dir"] = false
            return st
        end
        if dict_has(fs["dirs"], path):
            let st = {}
            st["type"] = 2
            st["size"] = 0
            st["name"] = path
            st["is_file"] = false
            st["is_dir"] = true
            return st
        end
        return nil
    end

    proc memfs_readdir(path):
        if not dict_has(fs["dirs"], path):
            return nil
        end
        return fs["dirs"][path]
    end

    proc memfs_mkdir(path):
        if not dict_has(fs["dirs"], path):
            fs["dirs"][path] = []
            # Update parent
            let d = dirname(path)
            let n = basename(path)
            if dict_has(fs["dirs"], d):
                push(fs["dirs"][d], make_dirent(n, VFS_DIR, 0))
            end
            return 0
        end
        return - 1
    end

    proc memfs_unlink(path):
        if dict_has(fs["files"], path):
            dict_delete(fs["files"], path)
            # Update parent
            let d_un = dirname(path)
            let n_un = basename(path)
            if dict_has(fs["dirs"], d_un):
                let entries_un = fs["dirs"][d_un]
                let new_entries_un = []
                for e_un in entries_un:
                    if e_un["name"] != n_un:
                        push(new_entries_un, e_un)
                    end
                end
                fs["dirs"][d_un] = new_entries_un
            end
            return 0
        end
        return - 1
    end

    proc memfs_rmdir(path):
        if dict_has(fs["dirs"], path):
            if path == "/":
                return - 1
            end

            let prefix = path + "/"
            let prefix_len = len(prefix)

            let f_keys = dict_keys(fs["files"])
            for k in f_keys:
                if len(k) >= prefix_len:
                    if slice(k, 0, prefix_len) == prefix:
                        return - 1
                    end
                end
            end

            let d_keys = dict_keys(fs["dirs"])
            for k in d_keys:
                if k != path and len(k) >= prefix_len:
                    if slice(k, 0, prefix_len) == prefix:
                        return - 1
                    end
                end
            end

            dict_delete(fs["dirs"], path)
            # Update parent
            let d_rm = dirname(path)
            let n_rm = basename(path)
            if dict_has(fs["dirs"], d_rm):
                let entries_p_rm = fs["dirs"][d_rm]
                let new_entries_p_rm = []
                for e_p_rm in entries_p_rm:
                    if e_p_rm["name"] != n_rm:
                        push(new_entries_p_rm, e_p_rm)
                    end
                end
                fs["dirs"][d_rm] = new_entries_p_rm
            end
            return 0
        end
        return - 1
    end

    proc memfs_close(handle):
        return 0
    end

    let backend = {}
    backend["open"] = memfs_open
    backend["read"] = memfs_read
    backend["write"] = memfs_write
    backend["stat"] = memfs_stat
    backend["readdir"] = memfs_readdir
    backend["mkdir"] = memfs_mkdir
    backend["rmdir"] = memfs_rmdir
    backend["unlink"] = memfs_unlink
    backend["close"] = memfs_close
    backend["_fs"] = fs
    return backend
end

# Helper: write bytes to a memfs file

proc memfs_write(backend, path, data):
    backend["_fs"]["files"][path] = data
    # Update parent dir listing
    let dirs = backend["_fs"]["dirs"]
    if not dict_has(dirs, "/"):
        dirs["/"] = []
    end
end

# Helper: create a directory in memfs

proc memfs_mkdir(backend, path):
    let dirs = backend["_fs"]["dirs"]
    dirs[path] = []
end
