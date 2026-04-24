gc_disable()

# procfs.sage — /proc filesystem interface for Linux
#
# Read and parse common /proc entries for system information.
# Works in userspace (reads actual /proc files) and kernel space (generates proc entries).

# ========== /proc readers (userspace) ==========

proc read_proc_file(path):
    let result = {}
    result["path"] = path
    result["content"] = readfile(path)
    result["lines"] = []
    # Split content into lines
    let content = result["content"]
    let line = ""
    let i = 0
    while i < len(content):
        if content[i] == chr(10):
            append(result["lines"], line)
            line = ""
        else:
            line = line + content[i]
        end
        i = i + 1
    end
    if line != "":
        append(result["lines"], line)
    end
    return result
end

# Parse /proc/cpuinfo
proc read_cpuinfo():
    let info = {}
    info["processors"] = []
    let proc_file = read_proc_file("/proc/cpuinfo")
    let current_cpu = {}
    let i = 0
    while i < len(proc_file["lines"]):
        let line = proc_file["lines"][i]
        if len(line) == 0:
            if dict_has(current_cpu, "processor"):
                append(info["processors"], current_cpu)
                current_cpu = {}
            end
        else:
            # Parse "key : value" lines
            let colon_pos = -1
            let j = 0
            while j < len(line):
                if line[j] == ":":
                    colon_pos = j
                    break
                end
                j = j + 1
            end
            if colon_pos > 0:
                # Extract key (trim trailing whitespace)
                let key = ""
                let k = 0
                while k < colon_pos:
                    if line[k] != " ":
                        key = key + line[k]
                    end
                    if line[k] == " ":
                        if k + 1 < colon_pos:
                            if line[k + 1] != " ":
                                if line[k + 1] != ":":
                                    key = key + "_"
                                end
                            end
                        end
                    end
                    k = k + 1
                end
                # Extract value (skip ": ")
                let val = ""
                let v = colon_pos + 1
                # Skip leading spaces
                while v < len(line):
                    if line[v] != " ":
                        break
                    end
                    v = v + 1
                end
                while v < len(line):
                    val = val + line[v]
                    v = v + 1
                end
                current_cpu[key] = val
            end
        end
        i = i + 1
    end
    if dict_has(current_cpu, "processor"):
        append(info["processors"], current_cpu)
    end
    info["count"] = len(info["processors"])
    return info
end

# Parse /proc/meminfo
proc read_meminfo():
    let info = {}
    let proc_file = read_proc_file("/proc/meminfo")
    let i = 0
    while i < len(proc_file["lines"]):
        let line = proc_file["lines"][i]
        let colon_pos = -1
        let j = 0
        while j < len(line):
            if line[j] == ":":
                colon_pos = j
                break
            end
            j = j + 1
        end
        if colon_pos > 0:
            let key = ""
            let k = 0
            while k < colon_pos:
                key = key + line[k]
                k = k + 1
            end
            let val = ""
            let v = colon_pos + 1
            while v < len(line):
                if line[v] != " ":
                    val = val + line[v]
                end
                v = v + 1
            end
            info[key] = val
        end
        i = i + 1
    end
    return info
end

# Parse /proc/loadavg
proc read_loadavg():
    let info = {}
    let proc_file = read_proc_file("/proc/loadavg")
    if len(proc_file["lines"]) > 0:
        let line = proc_file["lines"][0]
        let parts = []
        let part = ""
        let i = 0
        while i < len(line):
            if line[i] == " ":
                append(parts, part)
                part = ""
            else:
                part = part + line[i]
            end
            i = i + 1
        end
        if part != "":
            append(parts, part)
        end
        if len(parts) >= 3:
            info["load1"] = parts[0]
            info["load5"] = parts[1]
            info["load15"] = parts[2]
        end
        if len(parts) >= 4:
            info["running_total"] = parts[3]
        end
        if len(parts) >= 5:
            info["last_pid"] = parts[4]
        end
    end
    return info
end

# Parse /proc/uptime
proc read_uptime():
    let info = {}
    let proc_file = read_proc_file("/proc/uptime")
    if len(proc_file["lines"]) > 0:
        let line = proc_file["lines"][0]
        let parts = []
        let part = ""
        let i = 0
        while i < len(line):
            if line[i] == " ":
                append(parts, part)
                part = ""
            else:
                part = part + line[i]
            end
            i = i + 1
        end
        if part != "":
            append(parts, part)
        end
        if len(parts) >= 1:
            info["uptime"] = parts[0]
        end
        if len(parts) >= 2:
            info["idle"] = parts[1]
        end
    end
    return info
end

# Parse /proc/version
proc read_version():
    let info = {}
    let proc_file = read_proc_file("/proc/version")
    if len(proc_file["lines"]) > 0:
        info["version_string"] = proc_file["lines"][0]
    end
    return info
end

# Read /proc/self/status for current process
proc read_self_status():
    return read_proc_file("/proc/self/status")
end

# Read /proc/[pid]/status
proc read_pid_status(pid):
    return read_proc_file("/proc/" + str(pid) + "/status")
end

# Read /proc/[pid]/cmdline
proc read_pid_cmdline(pid):
    let info = {}
    let proc_file = read_proc_file("/proc/" + str(pid) + "/cmdline")
    info["raw"] = proc_file["content"]
    # cmdline separates args with null bytes (chr(0))
    let args = []
    let arg = ""
    let i = 0
    while i < len(proc_file["content"]):
        if proc_file["content"][i] == chr(0):
            if arg != "":
                append(args, arg)
            end
            arg = ""
        else:
            arg = arg + proc_file["content"][i]
        end
        i = i + 1
    end
    if arg != "":
        append(args, arg)
    end
    info["args"] = args
    return info
end

# List /proc/[pid] directories (process list)
proc list_processes():
    let pids = []
    # This would use readdir in a real implementation
    # For now return empty — requires native readdir support
    return pids
end

# ========== /proc entry generators (kernel space) ==========

proc create_proc_entry(name, read_body_lines):
    let entry = {}
    entry["name"] = name
    entry["read_body"] = read_body_lines
    entry["permissions"] = 292
    return entry
end

proc set_proc_permissions(entry, perms):
    entry["permissions"] = perms
    return entry
end

proc emit_proc_entry_c(entry):
    let nl = chr(10)
    let q = chr(34)
    let code = ""
    let name = entry["name"]
    let safe_name = ""
    let i = 0
    while i < len(name):
        if name[i] == "/":
            safe_name = safe_name + "_"
        else:
            safe_name = safe_name + name[i]
        end
        i = i + 1
    end

    code = code + "static int " + safe_name + "_show(struct seq_file *sf, void *v) {" + nl
    let bi = 0
    while bi < len(entry["read_body"]):
        code = code + "    " + entry["read_body"][bi] + nl
        bi = bi + 1
    end
    code = code + "    return 0;" + nl
    code = code + "}" + nl + nl

    code = code + "static int " + safe_name + "_open(struct inode *inode, struct file *file) {" + nl
    code = code + "    return single_open(file, " + safe_name + "_show, NULL);" + nl
    code = code + "}" + nl + nl

    code = code + "static const struct proc_ops " + safe_name + "_pops = {" + nl
    code = code + "    .proc_open = " + safe_name + "_open," + nl
    code = code + "    .proc_read = seq_read," + nl
    code = code + "    .proc_lseek = seq_lseek," + nl
    code = code + "    .proc_release = single_release," + nl
    code = code + "};" + nl

    return code
end
