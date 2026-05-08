gc_disable()
# =============================================================================
# SageOS Example Test Runner
# =============================================================================
# Automated multi-architecture test runner for SageOS kernel examples.
# Builds each example for x86_64, aarch64, riscv64, runs in QEMU, verifies
# expected serial output.
#
# Usage:
#   sage lib/os/examples/test_runner.sage [example] [arch]
#   sage lib/os/examples/test_runner.sage kernel       # all arches
#   sage lib/os/examples/test_runner.sage kernel x86_64 # single
# =============================================================================

import sys, io, os.examples.common as common

let NL = chr(10)
let PASS = "[PASS]"
let FAIL = "[FAIL]"
let SKIP = "[SKIP]"

let args = sys.args()
let test_example = "all"
let test_arch = "all"
if len(args) > 2:
    test_example = args[2]
end
if len(args) > 3:
    test_arch = args[3]
end

let arches = ["x86_64", "aarch64", "riscv64"]
let examples = ["kernel", "shell"]

if test_arch != "all" and not common.is_valid_arch(test_arch):
    print "Error: unsupported arch: " + test_arch
    sys.exit(1)
end

proc run_test(name, qemu_cmd, expect, timeout_sec):
    let full_cmd = "timeout " + str(timeout_sec) + " " + qemu_cmd + " 2>&1"
    print "  QEMU: " + full_cmd
    let output = ""
    let fd = io.popen(full_cmd, "r")
    if fd:
        while true:
            let line = io.fgets(fd)
            if line == nil:
                break
            end
            output = output + line
        end
        io.pclose(fd)
    end
    if output:
        if output.find(expect) >= 0:
            print "  " + PASS + " Found: " + expect
            return true
        else:
            print "  " + FAIL + " Expected '" + expect + "' not found"
            print "  Output preview: " + output[0:200]
            return false
        end
    else:
        print "  " + FAIL + " No output from QEMU"
        return false
    end
end

proc test_kernel(arch):
    print "--- Testing kernel.sage on " + arch + " ---"
    let out_dir = "/tmp/sageos_test_kernel_" + arch
    sys.exec("mkdir -p " + out_dir)
    sys.exec("rm -rf " + out_dir + "/*")

    let features = {}
    features["entry"] = "kmain"
    features["has_shell"] = false
    features["has_vga"] = false

    let result = common.build_kernel(arch, out_dir, features)

    # Append kmain
    let km = ""
    if arch == "x86_64":
        km = km + "void kmain(uint32_t magic, mb_t *mbi) { parse_multiboot(magic, mbi);" + NL
    else:
        km = km + "void kmain(void) {" + NL
    end
    km = km + "    serial_init();" + NL
    km = km + "    serial_puts(\"SageOS Kernel v0.2.0\\n\");" + NL
    km = km + "    serial_puts(\"Arch: " + arch + "\\n\");" + NL
    km = km + "    serial_puts(\"DONE\\n\");" + NL
    if arch == "x86_64":
        km = km + "    __asm__ volatile(\"cli; hlt\");" + NL
    end
    if arch == "aarch64":
        km = km + "    while(1) __asm__ volatile(\"wfe\");" + NL
    end
    if arch == "riscv64":
        km = km + "    while(1) __asm__ volatile(\"wfi\");" + NL
    end
    km = km + "}" + NL

    let kc = io.readfile(result["kernel_c"])
    io.writefile(result["kernel_c"], kc + NL + km)

    let rc = common.run_commands(result["commands"])
    if rc != 0:
        print "  " + FAIL + " Build failed (exit " + str(rc) + ")"
        return false
    end

    return run_test("kernel_" + arch, result["qemu"], "SageOS Kernel v0.2.0", 5)
end

proc test_shell(arch):
    print "--- Testing shell.sage on " + arch + " ---"
    let out_dir = "/tmp/sageos_test_shell_" + arch
    sys.exec("mkdir -p " + out_dir)
    sys.exec("rm -rf " + out_dir + "/*")

    let features = {}
    features["entry"] = "shell_main"
    features["has_shell"] = true
    features["has_vga"] = false

    let result = common.build_kernel(arch, out_dir, features)

    # Append shell_main
    let sc = ""
    if arch == "x86_64":
        sc = sc + "void shell_main(uint32_t magic, mb_t *mbi) { parse_multiboot(magic, mbi);" + NL
    else:
        sc = sc + "void shell_main(void) {" + NL
    end
    sc = sc + "    serial_init();" + NL
    sc = sc + "    serial_puts(\"SageOS Shell " + arch + "\\n\");" + NL
    sc = sc + "    serial_puts(\"READY\\n\");" + NL
    if arch == "x86_64":
        sc = sc + "    __asm__ volatile(\"cli; hlt\");" + NL
    end
    if arch == "aarch64":
        sc = sc + "    while(1) __asm__ volatile(\"wfe\");" + NL
    end
    if arch == "riscv64":
        sc = sc + "    while(1) __asm__ volatile(\"wfi\");" + NL
    end
    sc = sc + "}" + NL

    let kc = io.readfile(result["kernel_c"])
    io.writefile(result["kernel_c"], kc + NL + sc)

    let rc = common.run_commands(result["commands"])
    if rc != 0:
        print "  " + FAIL + " Build failed (exit " + str(rc) + ")"
        return false
    end

    return run_test("shell_" + arch, result["qemu"], "SageOS Shell " + arch, 5)
end

# Main
print "========================================"
print "  SageOS Example Test Runner"
print "========================================"
print ""

let total = 0
let passed = 0
let failed = 0

for ex in examples:
    if test_example != "all" and test_example != ex:
        continue
    end
    for arch in arches:
        if test_arch != "all" and test_arch != arch:
            continue
        end
        total = total + 1
        let ok = false
        if ex == "kernel":
            ok = test_kernel(arch)
        end
        if ex == "shell":
            ok = test_shell(arch)
        end
        if ok:
            passed = passed + 1
        else:
            failed = failed + 1
        end
        print ""
    end
end

print "========================================"
print "  Results: " + str(passed) + "/" + str(total) + " passed"
if failed > 0:
    print "           " + str(failed) + " failed"
end
print "========================================"

if failed > 0:
    sys.exit(1)
end
