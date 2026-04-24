gc_disable()

# namespace.sage — Linux namespaces interface
#
# Create and manage Linux namespaces for containerization.
# Generates unshare/nsenter commands and C code for namespace operations.

# ----- Namespace types (clone flags) -----
let CLONE_NEWNS = 131072
let CLONE_NEWUTS = 67108864
let CLONE_NEWIPC = 134217728
let CLONE_NEWPID = 536870912
let CLONE_NEWNET = 1073741824
let CLONE_NEWUSER = 268435456
let CLONE_NEWCGROUP = 33554432

# ----- Namespace names -----
let NS_MNT = "mnt"
let NS_UTS = "uts"
let NS_IPC = "ipc"
let NS_PID = "pid"
let NS_NET = "net"
let NS_USER = "user"
let NS_CGROUP = "cgroup"

# ========== Namespace descriptor ==========

proc create_namespace_config(name):
    let ns = {}
    ns["name"] = name
    ns["namespaces"] = []
    ns["uid_map"] = ""
    ns["gid_map"] = ""
    ns["hostname"] = ""
    ns["rootfs"] = ""
    ns["mounts"] = []
    ns["net_config"] = nil
    return ns
end

proc ns_add(config, ns_type):
    append(config["namespaces"], ns_type)
    return config
end

proc ns_set_hostname(config, hostname):
    config["hostname"] = hostname
    return config
end

proc ns_set_rootfs(config, path):
    config["rootfs"] = path
    return config
end

proc ns_set_uid_map(config, inside_uid, outside_uid, count):
    config["uid_map"] = str(inside_uid) + " " + str(outside_uid) + " " + str(count)
    return config
end

proc ns_set_gid_map(config, inside_gid, outside_gid, count):
    config["gid_map"] = str(inside_gid) + " " + str(outside_gid) + " " + str(count)
    return config
end

proc ns_add_mount(config, source, target, fstype, flags):
    let m = {}
    m["source"] = source
    m["target"] = target
    m["fstype"] = fstype
    m["flags"] = flags
    append(config["mounts"], m)
    return config
end

# ========== Network namespace config ==========

proc ns_set_net_veth(config, veth_host, veth_ns, ip_addr, netmask):
    let net = {}
    net["type"] = "veth"
    net["host_if"] = veth_host
    net["ns_if"] = veth_ns
    net["ip"] = ip_addr
    net["netmask"] = netmask
    config["net_config"] = net
    return config
end

# ========== Command generation ==========

proc ns_emit_unshare_cmd(config):
    let cmd = "unshare"
    let i = 0
    while i < len(config["namespaces"]):
        let ns = config["namespaces"][i]
        if ns == NS_MNT:
            cmd = cmd + " --mount"
        end
        if ns == NS_UTS:
            cmd = cmd + " --uts"
        end
        if ns == NS_IPC:
            cmd = cmd + " --ipc"
        end
        if ns == NS_PID:
            cmd = cmd + " --pid --fork"
        end
        if ns == NS_NET:
            cmd = cmd + " --net"
        end
        if ns == NS_USER:
            cmd = cmd + " --user"
        end
        if ns == NS_CGROUP:
            cmd = cmd + " --cgroup"
        end
        i = i + 1
    end
    if config["rootfs"] != "":
        cmd = cmd + " --root=" + config["rootfs"]
    end
    return cmd
end

proc ns_emit_setup_script(config):
    let nl = chr(10)
    let q = chr(34)
    let script = "#!/bin/sh" + nl
    script = script + "set -e" + nl + nl

    # Hostname
    if config["hostname"] != "":
        script = script + "hostname " + config["hostname"] + nl
    end

    # Mounts
    let mi = 0
    while mi < len(config["mounts"]):
        let m = config["mounts"][mi]
        script = script + "mount -t " + m["fstype"] + " " + m["source"] + " " + m["target"]
        if m["flags"] != "":
            script = script + " -o " + m["flags"]
        end
        script = script + nl
        mi = mi + 1
    end

    # Network
    if config["net_config"] != nil:
        let net = config["net_config"]
        if net["type"] == "veth":
            script = script + nl + "# Network setup" + nl
            script = script + "ip link set lo up" + nl
            script = script + "ip addr add " + net["ip"] + "/" + net["netmask"] + " dev " + net["ns_if"] + nl
            script = script + "ip link set " + net["ns_if"] + " up" + nl
        end
    end

    return script
end

proc ns_emit_host_net_setup(config):
    let nl = chr(10)
    let script = ""
    if config["net_config"] != nil:
        let net = config["net_config"]
        if net["type"] == "veth":
            script = script + "ip link add " + net["host_if"] + " type veth peer name " + net["ns_if"] + nl
            script = script + "ip link set " + net["host_if"] + " up" + nl
        end
    end
    return script
end

# ========== C code generation ==========

proc ns_emit_clone_flags(config):
    let flags = 0
    let i = 0
    while i < len(config["namespaces"]):
        let ns = config["namespaces"][i]
        if ns == NS_MNT:
            flags = flags + CLONE_NEWNS
        end
        if ns == NS_UTS:
            flags = flags + CLONE_NEWUTS
        end
        if ns == NS_IPC:
            flags = flags + CLONE_NEWIPC
        end
        if ns == NS_PID:
            flags = flags + CLONE_NEWPID
        end
        if ns == NS_NET:
            flags = flags + CLONE_NEWNET
        end
        if ns == NS_USER:
            flags = flags + CLONE_NEWUSER
        end
        if ns == NS_CGROUP:
            flags = flags + CLONE_NEWCGROUP
        end
        i = i + 1
    end
    return flags
end

# ========== Convenience ==========

proc minimal_container(name, rootfs):
    let config = create_namespace_config(name)
    config = ns_add(config, NS_MNT)
    config = ns_add(config, NS_UTS)
    config = ns_add(config, NS_PID)
    config = ns_add(config, NS_IPC)
    config = ns_set_hostname(config, name)
    config = ns_set_rootfs(config, rootfs)
    config = ns_add_mount(config, "proc", "/proc", "proc", "")
    config = ns_add_mount(config, "tmpfs", "/tmp", "tmpfs", "")
    config = ns_add_mount(config, "sysfs", "/sys", "sysfs", "")
    return config
end

proc networked_container(name, rootfs, ip):
    let config = minimal_container(name, rootfs)
    config = ns_add(config, NS_NET)
    config = ns_set_net_veth(config, "veth_" + name, "eth0", ip, "24")
    return config
end
