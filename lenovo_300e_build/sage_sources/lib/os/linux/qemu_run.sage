gc_disable()

# qemu_run.sage — QEMU integration for Linux kernel development
#
# Automated kernel module testing, device emulation, and CI/CD pipelines.
# Ties together the Linux syscalls, driver, kmodule, and namespace libraries
# with QEMU for test-driven kernel development.

# ----- Test result codes -----
let TEST_PASS = 0
let TEST_FAIL = 1
let TEST_SKIP = 2
let TEST_TIMEOUT = 3

# ========== Kernel test runner ==========

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
    runner["serial_log"] = ""
    runner["results"] = []
    runner["kvm"] = true
    runner["verbose"] = false
    return runner

proc runner_set_kernel(runner, kernel_path):
    runner["kernel"] = kernel_path
    return runner

proc runner_set_rootfs(runner, rootfs_path):
    runner["rootfs"] = rootfs_path
    return runner

proc runner_set_timeout(runner, seconds):
    runner["timeout"] = seconds
    return runner

proc runner_set_arch(runner, arch):
    runner["arch"] = arch
    return runner

proc runner_set_memory(runner, mem):
    runner["memory"] = mem
    return runner

# ========== Module testing ==========

proc runner_add_module(runner, mod_path, mod_name):
    let m = {}
    m["path"] = mod_path
    m["name"] = mod_name
    m["params"] = ""
    push(runner["modules"], m)
    return runner

proc runner_add_module_with_params(runner, mod_path, mod_name, params):
    let m = {}
    m["path"] = mod_path
    m["name"] = mod_name
    m["params"] = params
    push(runner["modules"], m)
    return runner

# ========== Test cases ==========

proc runner_add_test(runner, name, test_cmd, expect_output):
    let t = {}
    t["name"] = name
    t["cmd"] = test_cmd
    t["expect"] = expect_output
    t["result"] = TEST_SKIP
    push(runner["tests"], t)
    return runner

proc runner_add_load_test(runner, mod_name):
    let name = "load_" + mod_name
    let cmd = "insmod /lib/modules/" + mod_name + ".ko"
    runner = runner_add_test(runner, name, cmd, "")
    return runner

proc runner_add_unload_test(runner, mod_name):
    let name = "unload_" + mod_name
    let cmd = "rmmod " + mod_name
    runner = runner_add_test(runner, name, cmd, "")
    return runner

proc runner_add_dmesg_test(runner, name, pattern):
    let cmd = "dmesg | grep -q " + chr(34) + pattern + chr(34)
    runner = runner_add_test(runner, name, cmd, "")
    return runner

proc runner_add_procfs_test(runner, name, proc_path, expect):
    let cmd = "cat " + proc_path
    runner = runner_add_test(runner, name, cmd, expect)
    return runner

proc runner_add_sysfs_test(runner, name, sysfs_path, expect):
    let cmd = "cat " + sysfs_path
    runner = runner_add_test(runner, name, cmd, expect)
    return runner

proc runner_add_device_test(runner, name, dev_path):
    let cmd = "test -e " + dev_path + " && echo exists"
    runner = runner_add_test(runner, name, cmd, "exists")
    return runner

# ========== Init script generation ==========

proc generate_init_script(runner):
    let nl = chr(10)
    let q = chr(34)
    let script = "#!/bin/sh" + nl
    script = script + "set -e" + nl
    script = script + "mount -t proc proc /proc" + nl
    script = script + "mount -t sysfs sysfs /sys" + nl
    script = script + "mount -t devtmpfs devtmpfs /dev" + nl
    script = script + nl

    # Load modules
    let mi = 0
    while mi < len(runner["modules"]):
        let m = runner["modules"][mi]
        script = script + "echo " + q + "Loading module: " + m["name"] + q + nl
        let insmod_cmd = "insmod " + m["path"]
        if m["params"] != "":
            insmod_cmd = insmod_cmd + " " + m["params"]
        script = script + insmod_cmd + " && echo " + q + "MODLOAD_OK:" + m["name"] + q
        script = script + " || echo " + q + "MODLOAD_FAIL:" + m["name"] + q + nl
        mi = mi + 1
    script = script + nl

    # Run tests
    let ti = 0
    while ti < len(runner["tests"]):
        let t = runner["tests"][ti]
        script = script + "echo " + q + "TEST_START:" + t["name"] + q + nl
        script = script + t["cmd"] + " && echo " + q + "TEST_PASS:" + t["name"] + q
        script = script + " || echo " + q + "TEST_FAIL:" + t["name"] + q + nl
        ti = ti + 1
    script = script + nl

    # Shutdown
    script = script + "echo " + q + "ALL_TESTS_DONE" + q + nl
    script = script + "poweroff -f" + nl

    return script

# ========== QEMU command generation ==========

proc generate_qemu_cmd(runner):
    let parts = []
    push(parts, "qemu-system-" + runner["arch"])

    # Machine
    if runner["arch"] == "x86_64":
        push(parts, "-machine")
        if runner["kvm"]:
            push(parts, "q35,accel=kvm")
        else:
            push(parts, "q35")
    if runner["arch"] == "aarch64":
        push(parts, "-machine")
        push(parts, "virt")
        push(parts, "-cpu")
        push(parts, "cortex-a72")
    if runner["arch"] == "riscv64":
        push(parts, "-machine")
        push(parts, "virt")

    push(parts, "-m")
    push(parts, runner["memory"])
    push(parts, "-display")
    push(parts, "none")
    push(parts, "-serial")
    push(parts, "stdio")
    push(parts, "-no-reboot")

    if runner["kernel"] != "":
        push(parts, "-kernel")
        push(parts, runner["kernel"])
    if runner["initrd"] != "":
        push(parts, "-initrd")
        push(parts, runner["initrd"])
    if runner["rootfs"] != "":
        push(parts, "-drive")
        push(parts, "file=" + runner["rootfs"] + ",format=raw,if=virtio")

    # Append console to kernel cmdline
    let append = "console=ttyS0"
    if runner["rootfs"] != "":
        append = append + " root=/dev/vda rw"
    push(parts, "-append")
    push(parts, chr(34) + append + chr(34))

    # Join
    let cmd = ""
    let pi = 0
    while pi < len(parts):
        if pi > 0:
            cmd = cmd + " "
        cmd = cmd + parts[pi]
        pi = pi + 1
    return cmd

# ========== Result parsing ==========

proc parse_test_output(output):
    let results = []
    let lines = []
    let line = ""
    let i = 0
    while i < len(output):
        if output[i] == chr(10):
            push(lines, line)
            line = ""
        else:
            line = line + output[i]
        i = i + 1
    if line != "":
        push(lines, line)

    let li = 0
    while li < len(lines):
        let l = lines[li]
        if startswith(l, "TEST_PASS:"):
            let r = {}
            let name = ""
            let ni = 10
            while ni < len(l):
                name = name + l[ni]
                ni = ni + 1
            r["name"] = name
            r["result"] = TEST_PASS
            push(results, r)
        if startswith(l, "TEST_FAIL:"):
            let r2 = {}
            let name2 = ""
            let ni2 = 10
            while ni2 < len(l):
                name2 = name2 + l[ni2]
                ni2 = ni2 + 1
            r2["name"] = name2
            r2["result"] = TEST_FAIL
            push(results, r2)
        if startswith(l, "MODLOAD_FAIL:"):
            let r3 = {}
            let name3 = ""
            let ni3 = 13
            while ni3 < len(l):
                name3 = name3 + l[ni3]
                ni3 = ni3 + 1
            r3["name"] = "load_" + name3
            r3["result"] = TEST_FAIL
            push(results, r3)
        li = li + 1
    return results

proc count_results(results, code):
    let count = 0
    let i = 0
    while i < len(results):
        if results[i]["result"] == code:
            count = count + 1
        i = i + 1
    return count

proc summarize_results(results):
    let summary = {}
    summary["total"] = len(results)
    summary["pass"] = count_results(results, TEST_PASS)
    summary["fail"] = count_results(results, TEST_FAIL)
    summary["skip"] = count_results(results, TEST_SKIP)
    return summary

# ========== Shell script generation ==========

proc generate_test_script(runner):
    let nl = chr(10)
    let q = chr(34)
    let script = "#!/bin/bash" + nl
    script = script + "# Auto-generated QEMU kernel test script" + nl
    script = script + "set -euo pipefail" + nl + nl

    # Create initramfs with init script
    script = script + "TMPDIR=$(mktemp -d)" + nl
    script = script + "mkdir -p $TMPDIR/{bin,sbin,lib/modules,proc,sys,dev}" + nl
    script = script + "cp /bin/busybox $TMPDIR/bin/ 2>/dev/null || true" + nl + nl

    # Copy modules
    let mi = 0
    while mi < len(runner["modules"]):
        let m = runner["modules"][mi]
        script = script + "cp " + m["path"] + " $TMPDIR/lib/modules/" + nl
        mi = mi + 1

    # Write init script
    script = script + "cat > $TMPDIR/init << " + q + "INIT_EOF" + q + nl
    script = script + generate_init_script(runner)
    script = script + "INIT_EOF" + nl
    script = script + "chmod +x $TMPDIR/init" + nl + nl

    # Create initramfs
    script = script + "(cd $TMPDIR && find . | cpio -o -H newc 2>/dev/null | gzip > /tmp/initramfs.cpio.gz)" + nl + nl

    # Run QEMU with timeout
    script = script + "timeout " + str(runner["timeout"]) + " "
    script = script + generate_qemu_cmd(runner)
    script = script + " -initrd /tmp/initramfs.cpio.gz"
    script = script + " 2>&1 | tee /tmp/qemu_test.log" + nl + nl

    # Check results
    script = script + "PASS=$(grep -c TEST_PASS /tmp/qemu_test.log || true)" + nl
    script = script + "FAIL=$(grep -c TEST_FAIL /tmp/qemu_test.log || true)" + nl
    script = script + "echo " + q + "Results: $PASS passed, $FAIL failed" + q + nl
    script = script + "rm -rf $TMPDIR /tmp/initramfs.cpio.gz" + nl
    script = script + "[ " + q + "$FAIL" + q + " = " + q + "0" + q + " ]" + nl

    return script

# ========== Convenience ==========

proc quick_module_test(mod_path, mod_name, kernel_path):
    let runner = create_test_runner("modtest_" + mod_name)
    runner = runner_set_kernel(runner, kernel_path)
    runner = runner_add_module(runner, mod_path, mod_name)
    runner = runner_add_load_test(runner, mod_name)
    runner = runner_add_dmesg_test(runner, "loaded_" + mod_name, mod_name + ": module loaded")
    runner = runner_add_unload_test(runner, mod_name)
    return runner

proc quick_baremetal_test(kernel_elf, arch):
    let runner = create_test_runner("baremetal_" + arch)
    runner = runner_set_kernel(runner, kernel_elf)
    runner = runner_set_arch(runner, arch)
    runner = runner_set_memory(runner, "32M")
    runner = runner_set_timeout(runner, 10)
    runner["kvm"] = false
    return runner
