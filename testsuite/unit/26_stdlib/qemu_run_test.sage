gc_disable()
# EXPECT: runner_created
# EXPECT: runner_config
# EXPECT: modules_added
# EXPECT: tests_added
# EXPECT: init_script
# EXPECT: qemu_cmd_gen
# EXPECT: result_parsing
# EXPECT: result_summary
# EXPECT: test_script_gen
# EXPECT: quick_module
# EXPECT: quick_baremetal
# EXPECT: PASS

# Test runner creation
proc create_test_runner(name):
    let runner = {}
    runner["name"] = name
    runner["arch"] = "x86_64"
    runner["kernel"] = ""
    runner["initrd"] = ""
    runner["rootfs"] = ""
    runner["modules"] = []
    runner["tests"] = []
    runner["timeout"] = 60
    runner["memory"] = "256M"
    runner["results"] = []
    runner["kvm"] = true
    return runner

let runner = create_test_runner("ktest")
if runner["name"] == "ktest":
    if runner["timeout"] == 60:
        print "runner_created"

# Test configuration
runner["kernel"] = "/boot/vmlinuz"
runner["rootfs"] = "/tmp/rootfs.img"
runner["arch"] = "x86_64"
runner["memory"] = "512M"
runner["kvm"] = false
if runner["kernel"] == "/boot/vmlinuz":
    if runner["memory"] == "512M":
        if runner["kvm"] == false:
            print "runner_config"

# Test module adding
let m1 = {}
m1["path"] = "/tmp/sage_dev.ko"
m1["name"] = "sage_dev"
m1["params"] = ""
push(runner["modules"], m1)

let m2 = {}
m2["path"] = "/tmp/sage_net.ko"
m2["name"] = "sage_net"
m2["params"] = "debug=1 mtu=9000"
push(runner["modules"], m2)

if len(runner["modules"]) == 2:
    if runner["modules"][0]["name"] == "sage_dev":
        if runner["modules"][1]["params"] == "debug=1 mtu=9000":
            print "modules_added"

# Test adding test cases
let t1 = {}
t1["name"] = "load_sage_dev"
t1["cmd"] = "insmod /lib/modules/sage_dev.ko"
t1["expect"] = ""
t1["result"] = 2
push(runner["tests"], t1)

let t2 = {}
t2["name"] = "check_dmesg"
t2["cmd"] = "dmesg | grep -q " + chr(34) + "sage_dev: module loaded" + chr(34)
t2["expect"] = ""
t2["result"] = 2
push(runner["tests"], t2)

let t3 = {}
t3["name"] = "check_dev"
t3["cmd"] = "test -e /dev/sage_dev && echo exists"
t3["expect"] = "exists"
t3["result"] = 2
push(runner["tests"], t3)

if len(runner["tests"]) == 3:
    if runner["tests"][0]["name"] == "load_sage_dev":
        if runner["tests"][2]["expect"] == "exists":
            print "tests_added"

# Test init script generation
let nl = chr(10)
let q = chr(34)
let script = "#!/bin/sh" + nl
script = script + "mount -t proc proc /proc" + nl
script = script + "mount -t sysfs sysfs /sys" + nl
let mi = 0
while mi < len(runner["modules"]):
    let mod = runner["modules"][mi]
    let insmod = "insmod " + mod["path"]
    if mod["params"] != "":
        insmod = insmod + " " + mod["params"]
    script = script + insmod + nl
    mi = mi + 1
let ti = 0
while ti < len(runner["tests"]):
    let t = runner["tests"][ti]
    script = script + t["cmd"] + " && echo TEST_PASS:" + t["name"] + nl
    ti = ti + 1
script = script + "poweroff -f" + nl

if contains(script, "mount -t proc"):
    if contains(script, "insmod /tmp/sage_dev.ko"):
        if contains(script, "insmod /tmp/sage_net.ko debug=1 mtu=9000"):
            if contains(script, "TEST_PASS:load_sage_dev"):
                if contains(script, "poweroff -f"):
                    print "init_script"

# Test QEMU command generation
let parts = []
push(parts, "qemu-system-" + runner["arch"])
push(parts, "-machine")
push(parts, "q35")
push(parts, "-m")
push(parts, runner["memory"])
push(parts, "-display")
push(parts, "none")
push(parts, "-serial")
push(parts, "stdio")
push(parts, "-no-reboot")
push(parts, "-kernel")
push(parts, runner["kernel"])
push(parts, "-drive")
push(parts, "file=" + runner["rootfs"] + ",format=raw,if=virtio")
let cmd = ""
let pi = 0
while pi < len(parts):
    if pi > 0:
        cmd = cmd + " "
    cmd = cmd + parts[pi]
    pi = pi + 1
if contains(cmd, "qemu-system-x86_64"):
    if contains(cmd, "-kernel /boot/vmlinuz"):
        if contains(cmd, "file=/tmp/rootfs.img"):
            if contains(cmd, "-no-reboot"):
                print "qemu_cmd_gen"

# Test result parsing
let test_output = "TEST_START:load" + nl
test_output = test_output + "TEST_PASS:load" + nl
test_output = test_output + "TEST_START:check" + nl
test_output = test_output + "TEST_FAIL:check" + nl
test_output = test_output + "MODLOAD_FAIL:badmod" + nl
test_output = test_output + "ALL_TESTS_DONE" + nl

let results = []
let lines = []
let line = ""
let oi = 0
while oi < len(test_output):
    if test_output[oi] == chr(10):
        push(lines, line)
        line = ""
    else:
        line = line + test_output[oi]
    oi = oi + 1
if line != "":
    push(lines, line)

let li = 0
while li < len(lines):
    let l = lines[li]
    if startswith(l, "TEST_PASS:"):
        let r = {}
        let rn = ""
        let rni = 10
        while rni < len(l):
            rn = rn + l[rni]
            rni = rni + 1
        r["name"] = rn
        r["result"] = 0
        push(results, r)
    if startswith(l, "TEST_FAIL:"):
        let r2 = {}
        let rn2 = ""
        let rni2 = 10
        while rni2 < len(l):
            rn2 = rn2 + l[rni2]
            rni2 = rni2 + 1
        r2["name"] = rn2
        r2["result"] = 1
        push(results, r2)
    if startswith(l, "MODLOAD_FAIL:"):
        let r3 = {}
        let rn3 = ""
        let rni3 = 13
        while rni3 < len(l):
            rn3 = rn3 + l[rni3]
            rni3 = rni3 + 1
        r3["name"] = "load_" + rn3
        r3["result"] = 1
        push(results, r3)
    li = li + 1

if len(results) == 3:
    if results[0]["name"] == "load":
        if results[0]["result"] == 0:
            if results[1]["name"] == "check":
                if results[1]["result"] == 1:
                    if results[2]["name"] == "load_badmod":
                        print "result_parsing"

# Test result summary
proc count_results(res, code):
    let count = 0
    let ci = 0
    while ci < len(res):
        if res[ci]["result"] == code:
            count = count + 1
        ci = ci + 1
    return count

let total = len(results)
let pass_count = count_results(results, 0)
let fail_count = count_results(results, 1)
if total == 3:
    if pass_count == 1:
        if fail_count == 2:
            print "result_summary"

# Test shell script generation
let tscript = "#!/bin/bash" + nl
tscript = tscript + "TMPDIR=$(mktemp -d)" + nl
tscript = tscript + "mkdir -p $TMPDIR/{bin,sbin,lib/modules,proc,sys,dev}" + nl
tscript = tscript + "timeout 60 qemu-system-x86_64" + nl
tscript = tscript + "PASS=$(grep -c TEST_PASS /tmp/qemu_test.log || true)" + nl
tscript = tscript + "FAIL=$(grep -c TEST_FAIL /tmp/qemu_test.log || true)" + nl
if contains(tscript, "#!/bin/bash"):
    if contains(tscript, "mktemp -d"):
        if contains(tscript, "timeout 60"):
            if contains(tscript, "grep -c TEST_PASS"):
                print "test_script_gen"

# Test quick module test
proc quick_module_test(mod_path, mod_name, kernel_path):
    let qr = create_test_runner("modtest_" + mod_name)
    qr["kernel"] = kernel_path
    let qm = {}
    qm["path"] = mod_path
    qm["name"] = mod_name
    qm["params"] = ""
    push(qr["modules"], qm)
    let qt = {}
    qt["name"] = "load_" + mod_name
    qt["cmd"] = "insmod /lib/modules/" + mod_name + ".ko"
    qt["expect"] = ""
    qt["result"] = 2
    push(qr["tests"], qt)
    return qr

let qmt = quick_module_test("/tmp/hello.ko", "hello", "/boot/vmlinuz")
if qmt["name"] == "modtest_hello":
    if len(qmt["modules"]) == 1:
        if len(qmt["tests"]) == 1:
            print "quick_module"

# Test quick baremetal test
proc quick_baremetal_test(kernel_elf, arch):
    let qb = create_test_runner("baremetal_" + arch)
    qb["kernel"] = kernel_elf
    qb["arch"] = arch
    qb["memory"] = "32M"
    qb["timeout"] = 10
    qb["kvm"] = false
    return qb

let qbt = quick_baremetal_test("sage_kernel.elf", "aarch64")
if qbt["arch"] == "aarch64":
    if qbt["memory"] == "32M":
        if qbt["timeout"] == 10:
            if qbt["kvm"] == false:
                print "quick_baremetal"

print "PASS"
