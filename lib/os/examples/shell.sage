gc_disable()
# SageOS Interactive Shell (Multi-Architecture)
# Usage: sage shell.sage [x86_64|aarch64|riscv64]

import sys
import io
import os.examples.common as common

let NL = chr(10)
let arch = common.arch_from_args("x86_64")
if not common.is_valid_arch(arch):
    print "Error: unsupported arch: " + arch
    sys.exit(1)
end

print "=== SageOS Shell ==="
print "Arch: " + arch

let out_dir = "/tmp/sageos_shell_" + arch
sys.exec("mkdir -p " + out_dir)

let features = {}
features["entry"] = "shell_main"
features["has_shell"] = true
features["has_vga"] = false

let result = common.build_kernel(arch, out_dir, features)

# Append shell_main to kernel C
let shell_c = ""
shell_c = shell_c + "#define CMD_MAX 128" + NL
shell_c = shell_c + "static uint32_t cmd_count = 0;" + NL
shell_c = shell_c + "static void cmd_help(void) {" + NL
shell_c = shell_c + "    serial_puts(\"help echo mem regs uptime clear halt\\n\"); }" + NL

if arch == "x86_64":
    shell_c = shell_c + "static void cmd_mem(void) {" + NL
    shell_c = shell_c + "    serial_puts(\"L=\"); serial_putdec(mem_lower_kb);" + NL
    shell_c = shell_c + "    serial_puts(\"KB U=\"); serial_putdec(mem_upper_kb); serial_puts(\"KB\\n\"); }" + NL
else:
    shell_c = shell_c + "static void cmd_mem(void) {" + NL
    shell_c = shell_c + "    serial_puts(\"128MB (QEMU default)\\n\"); }" + NL
end

shell_c = shell_c + "static void cmd_uptime(void) {" + NL
shell_c = shell_c + "    serial_puts(\"cmds=\"); serial_putdec(cmd_count); serial_puts(\"\\n\"); }" + NL

if arch == "x86_64":
    shell_c = shell_c + "void shell_main(uint32_t magic, mb_t *mbi) {" + NL
    shell_c = shell_c + "    parse_multiboot(magic, mbi);" + NL
else:
    shell_c = shell_c + "void shell_main(void) {" + NL
end

shell_c = shell_c + "    serial_init();" + NL
shell_c = shell_c + "    serial_puts(\"SageOS Shell v0.2.0 " + arch + "\\n\");" + NL
shell_c = shell_c + "    char cmd[CMD_MAX];" + NL
shell_c = shell_c + "    while (1) {" + NL
shell_c = shell_c + "        serial_puts(\"sage@os:~$ \");" + NL
shell_c = shell_c + "        int len = 0;" + NL
shell_c = shell_c + "        while (1) {" + NL
shell_c = shell_c + "            char c = serial_getc();" + NL
shell_c = shell_c + "            if (c == '\\r' || c == '\\n') { serial_puts(\"\\n\"); break; }" + NL
shell_c = shell_c + "            if ((c == 127 || c == 8) && len > 0) { len--; serial_puts(\"\\b \\b\"); continue; }" + NL
shell_c = shell_c + "            if (len < CMD_MAX-1) { cmd[len++] = c; serial_putc(c); }" + NL
shell_c = shell_c + "        }" + NL
shell_c = shell_c + "        cmd[len] = 0;" + NL
shell_c = shell_c + "        if (!len) continue;" + NL
shell_c = shell_c + "        cmd_count++;" + NL
shell_c = shell_c + "        if (streq(cmd,\"help\")) cmd_help();" + NL
shell_c = shell_c + "        else if (streq(cmd,\"mem\")) cmd_mem();" + NL
shell_c = shell_c + "        else if (streq(cmd,\"regs\")) dump_regs();" + NL
shell_c = shell_c + "        else if (streq(cmd,\"uptime\")) cmd_uptime();" + NL
shell_c = shell_c + "        else if (streq(cmd,\"clear\")) serial_puts(\"\\033[2J\\033[H\");" + NL
shell_c = shell_c + "        else if (streq(cmd,\"halt\")) {" + NL
shell_c = shell_c + "            serial_puts(\"Halting...\\n\");" + NL
if arch == "x86_64":
    shell_c = shell_c + "            __asm__ volatile(\"cli; hlt\");" + NL
end
if arch == "aarch64":
    shell_c = shell_c + "            while(1) __asm__ volatile(\"wfe\");" + NL
end
if arch == "riscv64":
    shell_c = shell_c + "            while(1) __asm__ volatile(\"wfi\");" + NL
end
shell_c = shell_c + "        }" + NL
shell_c = shell_c + "        else if (startswith(cmd,\"echo \")) {" + NL
shell_c = shell_c + "            serial_puts(cmd+5); serial_puts(\"\\n\"); }" + NL
shell_c = shell_c + "        else { serial_puts(\"Unknown: \"); serial_puts(cmd); serial_puts(\"\\n\"); }" + NL
shell_c = shell_c + "    }" + NL
shell_c = shell_c + "}" + NL

let kernel_c_path = result["kernel_c"]
let existing = io.readfile(kernel_c_path)
io.writefile(kernel_c_path, existing + NL + shell_c)

print "Building..."
let rc = common.run_commands(result["commands"])
if rc != 0:
    print "Build FAILED: " + str(rc)
    sys.exit(1)
end

print "Build OK: " + result["elf"]
print ""
print "Run: " + result["qemu"]
print "Commands: help, echo <text>, mem, regs, uptime, clear, halt"