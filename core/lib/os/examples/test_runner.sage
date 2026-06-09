gc_disable()
# SageOS Example Test Runner

import sys
import io
import os.examples.common as common

let NL = chr(10)
let PASS = "[PASS]"
let FAIL = "[FAIL]"

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

proc string_contains(haystack, needle):
    let hlen = len(haystack)
    let nlen = len(needle)
    if nlen == 0:
        return true
    end
    if hlen < nlen:
        return false
    end
    let i = 0
    while i <= hlen - nlen:
        let j = 0
        while j < nlen:
            if haystack[i + j] != needle[j]:
                break
            end
            j = j + 1
        end
        if j == nlen:
            return true
        end
        i = i + 1
    end
    return false
end

proc string_prefix(s, n):
    let r = ""
    let i = 0
    let m = n
    if m > len(s):
        m = len(s)
    end
    while i < m:
        r = r + s[i]
        i = i + 1
    end
    return r
end

proc run_qemu_and_check(qemu_cmd, expect, timeout_sec):
    let out_file = "/tmp/sageos_test_output.txt"
    let full_cmd = "timeout " + str(timeout_sec) + " " + qemu_cmd + " > " + out_file + " 2>&1"
    print "  Running QEMU..."
    sys.exec(full_cmd)
    let content = io.readfile(out_file)
    if content == nil:
        print "  " + FAIL + " No output captured"
        return false
    end
    if string_contains(content, expect):
        print "  " + PASS + " Found: " + expect
        return true
    else:
        print "  " + FAIL + " Expected '" + expect + "' not found"
        print "  Output preview: " + string_prefix(content, 200)
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

    return run_qemu_and_check(result["qemu"], "SageOS Kernel v0.2.0", 5)
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

    return run_qemu_and_check(result["qemu"], "SageOS Shell " + arch, 5)
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
