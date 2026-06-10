let arch = asm_arch()
print "Arch: " + arch

if arch == "x86_64":
    let res = asm_exec("mov $42, %rax", "int")
    print "Result x86_64: " + str(res)
elif arch == "aarch64":
    let res = asm_exec("mov x0, #42", "int")
    print "Result aarch64: " + str(res)
elif arch == "rv64":
    let res = asm_exec("li a0, 42", "int")
    print "Result rv64: " + str(res)
else:
    print "Unsupported arch for asm_exec"
