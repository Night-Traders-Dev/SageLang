gc_disable()
# EXPECT: cgroup_created
# EXPECT: controllers
# EXPECT: cpu_limits
# EXPECT: memory_limits
# EXPECT: io_limits
# EXPECT: pids_limits
# EXPECT: child_cgroup
# EXPECT: setup_commands
# EXPECT: container_cgroup
# EXPECT: PASS

# Test cgroup creation
let CGROUP_ROOT = "/sys/fs/cgroup"

proc create_cgroup(name):
    let cg = {}
    cg["name"] = name
    cg["path"] = CGROUP_ROOT + "/" + name
    cg["controllers"] = []
    cg["limits"] = {}
    cg["children"] = []
    return cg

let cg = create_cgroup("sage_app")
if cg["name"] == "sage_app":
    if cg["path"] == "/sys/fs/cgroup/sage_app":
        print "cgroup_created"

# Test controllers
push(cg["controllers"], "cpu")
push(cg["controllers"], "memory")
push(cg["controllers"], "pids")
if len(cg["controllers"]) == 3:
    if cg["controllers"][0] == "cpu":
        print "controllers"

# Test CPU limits
cg["limits"]["cpu.max"] = "50000 100000"
cg["limits"]["cpu.weight"] = "100"
if cg["limits"]["cpu.max"] == "50000 100000":
    if cg["limits"]["cpu.weight"] == "100":
        print "cpu_limits"

# Test memory limits
cg["limits"]["memory.max"] = "536870912"
cg["limits"]["memory.high"] = "402653184"
if cg["limits"]["memory.max"] == "536870912":
    print "memory_limits"

# Test IO limits
cg["limits"]["io.max"] = "8:0 rbps=1048576 wbps=524288"
if contains(cg["limits"]["io.max"], "rbps=1048576"):
    print "io_limits"

# Test PID limits
cg["limits"]["pids.max"] = "100"
if cg["limits"]["pids.max"] == "100":
    print "pids_limits"

# Test child cgroup
let child = create_cgroup("sage_app/worker1")
child["path"] = cg["path"] + "/worker1"
push(cg["children"], child)
if len(cg["children"]) == 1:
    if child["path"] == "/sys/fs/cgroup/sage_app/worker1":
        print "child_cgroup"

# Test setup command generation
let nl = chr(10)
let q = chr(34)
let cmds = ""
cmds = cmds + "mkdir -p " + cg["path"] + nl
# Controller enabling
let ctrl_str = ""
let ci = 0
while ci < len(cg["controllers"]):
    if ci > 0:
        ctrl_str = ctrl_str + " "
    ctrl_str = ctrl_str + "+" + cg["controllers"][ci]
    ci = ci + 1
cmds = cmds + "echo " + q + ctrl_str + q + " > " + cg["path"] + "/cgroup.subtree_control" + nl
if contains(cmds, "mkdir -p /sys/fs/cgroup/sage_app"):
    if contains(cmds, "+cpu +memory +pids"):
        print "setup_commands"

# Test container cgroup convenience
proc container_cgroup(name, cpu_pct, mem_mb, max_pids):
    let c = create_cgroup(name)
    push(c["controllers"], "cpu")
    push(c["controllers"], "memory")
    push(c["controllers"], "pids")
    let quota = cpu_pct * 1000
    c["limits"]["cpu.max"] = str(quota) + " 100000"
    let mem_bytes = mem_mb * 1048576
    c["limits"]["memory.max"] = str(mem_bytes)
    c["limits"]["pids.max"] = str(max_pids)
    return c

let container = container_cgroup("web", 50, 512, 200)
if container["limits"]["cpu.max"] == "50000 100000":
    if container["limits"]["memory.max"] == "536870912":
        if container["limits"]["pids.max"] == "200":
            print "container_cgroup"

print "PASS"
