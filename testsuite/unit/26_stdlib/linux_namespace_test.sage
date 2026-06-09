gc_disable()
# EXPECT: ns_config_created
# EXPECT: ns_types_added
# EXPECT: ns_hostname
# EXPECT: ns_mounts
# EXPECT: ns_veth
# EXPECT: unshare_cmd
# EXPECT: setup_script
# EXPECT: clone_flags
# EXPECT: minimal_container
# EXPECT: PASS

# Namespace constants
let CLONE_NEWNS = 131072
let CLONE_NEWUTS = 67108864
let CLONE_NEWIPC = 134217728
let CLONE_NEWPID = 536870912
let CLONE_NEWNET = 1073741824
let CLONE_NEWUSER = 268435456

# Test config creation
proc create_ns_config(name):
    let ns = {}
    ns["name"] = name
    ns["namespaces"] = []
    ns["hostname"] = ""
    ns["rootfs"] = ""
    ns["mounts"] = []
    ns["net_config"] = nil
    return ns

let ns = create_ns_config("test_ns")
if ns["name"] == "test_ns":
    if len(ns["namespaces"]) == 0:
        print "ns_config_created"

# Test adding namespaces
push(ns["namespaces"], "mnt")
push(ns["namespaces"], "uts")
push(ns["namespaces"], "pid")
push(ns["namespaces"], "ipc")
if len(ns["namespaces"]) == 4:
    if ns["namespaces"][0] == "mnt":
        if ns["namespaces"][2] == "pid":
            print "ns_types_added"

# Test hostname
ns["hostname"] = "sage-container"
if ns["hostname"] == "sage-container":
    print "ns_hostname"

# Test mounts
let m1 = {}
m1["source"] = "proc"
m1["target"] = "/proc"
m1["fstype"] = "proc"
m1["flags"] = ""
push(ns["mounts"], m1)
let m2 = {}
m2["source"] = "tmpfs"
m2["target"] = "/tmp"
m2["fstype"] = "tmpfs"
m2["flags"] = "size=64m"
push(ns["mounts"], m2)
if len(ns["mounts"]) == 2:
    if ns["mounts"][0]["fstype"] == "proc":
        if ns["mounts"][1]["flags"] == "size=64m":
            print "ns_mounts"

# Test veth config
let net = {}
net["type"] = "veth"
net["host_if"] = "veth_test"
net["ns_if"] = "eth0"
net["ip"] = "10.0.0.2"
net["netmask"] = "24"
ns["net_config"] = net
if ns["net_config"]["host_if"] == "veth_test":
    if ns["net_config"]["ip"] == "10.0.0.2":
        print "ns_veth"

# Test unshare command generation
let cmd = "unshare"
let ui = 0
while ui < len(ns["namespaces"]):
    let nst = ns["namespaces"][ui]
    if nst == "mnt":
        cmd = cmd + " --mount"
    if nst == "uts":
        cmd = cmd + " --uts"
    if nst == "pid":
        cmd = cmd + " --pid --fork"
    if nst == "ipc":
        cmd = cmd + " --ipc"
    ui = ui + 1
if contains(cmd, "--mount"):
    if contains(cmd, "--uts"):
        if contains(cmd, "--pid --fork"):
            print "unshare_cmd"

# Test setup script
let nl = chr(10)
let script = "#!/bin/sh" + nl
script = script + "hostname " + ns["hostname"] + nl
let mi = 0
while mi < len(ns["mounts"]):
    let mnt = ns["mounts"][mi]
    script = script + "mount -t " + mnt["fstype"] + " " + mnt["source"] + " " + mnt["target"] + nl
    mi = mi + 1
if contains(script, "hostname sage-container"):
    if contains(script, "mount -t proc proc /proc"):
        print "setup_script"

# Test clone flags computation
proc compute_clone_flags(ns_list):
    let flags = 0
    let fi = 0
    while fi < len(ns_list):
        let nst2 = ns_list[fi]
        if nst2 == "mnt":
            flags = flags + CLONE_NEWNS
        if nst2 == "uts":
            flags = flags + CLONE_NEWUTS
        if nst2 == "pid":
            flags = flags + CLONE_NEWPID
        if nst2 == "ipc":
            flags = flags + CLONE_NEWIPC
        fi = fi + 1
    return flags

let flags = compute_clone_flags(ns["namespaces"])
let expected = CLONE_NEWNS + CLONE_NEWUTS + CLONE_NEWPID + CLONE_NEWIPC
if flags == expected:
    print "clone_flags"

# Test minimal container convenience
proc minimal_container(name, rootfs):
    let config = create_ns_config(name)
    push(config["namespaces"], "mnt")
    push(config["namespaces"], "uts")
    push(config["namespaces"], "pid")
    push(config["namespaces"], "ipc")
    config["hostname"] = name
    config["rootfs"] = rootfs
    let pm = {}
    pm["source"] = "proc"
    pm["target"] = "/proc"
    pm["fstype"] = "proc"
    pm["flags"] = ""
    push(config["mounts"], pm)
    return config

let mc = minimal_container("sage-os", "/rootfs")
if mc["hostname"] == "sage-os":
    if mc["rootfs"] == "/rootfs":
        if len(mc["namespaces"]) == 4:
            if len(mc["mounts"]) == 1:
                print "minimal_container"

print "PASS"
