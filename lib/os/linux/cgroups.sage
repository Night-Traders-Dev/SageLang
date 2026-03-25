gc_disable()

# cgroups.sage — Linux Control Groups (cgroups v2) interface
#
# Manage resource limits, accounting, and process groups via the cgroup filesystem.

# ----- Cgroup controllers -----
let CTRL_CPU = "cpu"
let CTRL_MEMORY = "memory"
let CTRL_IO = "io"
let CTRL_PIDS = "pids"
let CTRL_CPUSET = "cpuset"
let CTRL_RDMA = "rdma"
let CTRL_HUGETLB = "hugetlb"

# ----- Cgroup v2 root -----
let CGROUP_ROOT = "/sys/fs/cgroup"

# ========== Cgroup descriptor ==========

proc create_cgroup(name):
    let cg = {}
    cg["name"] = name
    cg["path"] = CGROUP_ROOT + "/" + name
    cg["controllers"] = []
    cg["limits"] = {}
    cg["children"] = []
    return cg
end

proc cg_add_controller(cg, controller):
    append(cg["controllers"], controller)
    return cg
end

# ========== CPU limits ==========

proc cg_set_cpu_max(cg, quota_us, period_us):
    cg["limits"]["cpu.max"] = str(quota_us) + " " + str(period_us)
    return cg
end

proc cg_set_cpu_weight(cg, weight):
    cg["limits"]["cpu.weight"] = str(weight)
    return cg
end

# ========== Memory limits ==========

proc cg_set_memory_max(cg, bytes):
    cg["limits"]["memory.max"] = str(bytes)
    return cg
end

proc cg_set_memory_high(cg, bytes):
    cg["limits"]["memory.high"] = str(bytes)
    return cg
end

proc cg_set_memory_low(cg, bytes):
    cg["limits"]["memory.low"] = str(bytes)
    return cg
end

proc cg_set_swap_max(cg, bytes):
    cg["limits"]["memory.swap.max"] = str(bytes)
    return cg
end

# ========== IO limits ==========

proc cg_set_io_max(cg, major, minor, rbps, wbps, riops, wiops):
    let line = str(major) + ":" + str(minor)
    if rbps > 0:
        line = line + " rbps=" + str(rbps)
    end
    if wbps > 0:
        line = line + " wbps=" + str(wbps)
    end
    if riops > 0:
        line = line + " riops=" + str(riops)
    end
    if wiops > 0:
        line = line + " wiops=" + str(wiops)
    end
    cg["limits"]["io.max"] = line
    return cg
end

# ========== PID limits ==========

proc cg_set_pids_max(cg, max_pids):
    cg["limits"]["pids.max"] = str(max_pids)
    return cg
end

# ========== Cpuset ==========

proc cg_set_cpus(cg, cpus_str):
    cg["limits"]["cpuset.cpus"] = cpus_str
    return cg
end

proc cg_set_mems(cg, mems_str):
    cg["limits"]["cpuset.mems"] = mems_str
    return cg
end

# ========== Child cgroups ==========

proc cg_add_child(cg, child_name):
    let child = create_cgroup(cg["name"] + "/" + child_name)
    child["path"] = cg["path"] + "/" + child_name
    append(cg["children"], child)
    return child
end

# ========== Shell command generation ==========

proc cg_emit_setup_commands(cg):
    let nl = chr(10)
    let cmds = ""
    cmds = cmds + "mkdir -p " + cg["path"] + nl

    # Enable controllers
    if len(cg["controllers"]) > 0:
        let ctrl_str = ""
        let i = 0
        while i < len(cg["controllers"]):
            if i > 0:
                ctrl_str = ctrl_str + " "
            end
            ctrl_str = ctrl_str + "+" + cg["controllers"][i]
            i = i + 1
        end
        cmds = cmds + "echo " + chr(34) + ctrl_str + chr(34) + " > " + cg["path"] + "/cgroup.subtree_control" + nl
    end

    # Apply limits
    let keys = dict_keys(cg["limits"])
    let ki = 0
    while ki < len(keys):
        cmds = cmds + "echo " + chr(34) + cg["limits"][keys[ki]] + chr(34) + " > " + cg["path"] + "/" + keys[ki] + nl
        ki = ki + 1
    end

    return cmds
end

proc cg_emit_add_pid(cg, pid):
    return "echo " + str(pid) + " > " + cg["path"] + "/cgroup.procs"
end

proc cg_emit_cleanup(cg):
    return "rmdir " + cg["path"]
end

# ========== Reading cgroup stats ==========

proc cg_read_stat(cg_path, stat_file):
    let info = {}
    let content = readfile(cg_path + "/" + stat_file)
    let lines = []
    let line = ""
    let i = 0
    while i < len(content):
        if content[i] == chr(10):
            append(lines, line)
            line = ""
        else:
            line = line + content[i]
        end
        i = i + 1
    end
    if line != "":
        append(lines, line)
    end
    let li = 0
    while li < len(lines):
        let l = lines[li]
        let space = -1
        let j = 0
        while j < len(l):
            if l[j] == " ":
                space = j
                break
            end
            j = j + 1
        end
        if space > 0:
            let key = ""
            let k = 0
            while k < space:
                key = key + l[k]
                k = k + 1
            end
            let val = ""
            let v = space + 1
            while v < len(l):
                val = val + l[v]
                v = v + 1
            end
            info[key] = val
        end
        li = li + 1
    end
    return info
end

proc cg_read_memory_stat(cg_path):
    return cg_read_stat(cg_path, "memory.stat")
end

proc cg_read_cpu_stat(cg_path):
    return cg_read_stat(cg_path, "cpu.stat")
end

proc cg_read_io_stat(cg_path):
    return cg_read_stat(cg_path, "io.stat")
end

proc cg_read_pids_current(cg_path):
    return readfile(cg_path + "/pids.current")
end

# ========== Convenience builders ==========

proc container_cgroup(name, cpu_pct, mem_mb, max_pids):
    let cg = create_cgroup(name)
    cg = cg_add_controller(cg, CTRL_CPU)
    cg = cg_add_controller(cg, CTRL_MEMORY)
    cg = cg_add_controller(cg, CTRL_PIDS)
    # cpu_pct: percentage of one CPU (100 = one full core)
    let quota = cpu_pct * 1000
    cg = cg_set_cpu_max(cg, quota, 100000)
    # mem_mb: memory limit in megabytes
    let mem_bytes = mem_mb * 1048576
    cg = cg_set_memory_max(cg, mem_bytes)
    cg = cg_set_pids_max(cg, max_pids)
    return cg
end
