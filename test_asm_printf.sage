let lib = ffi_open("")
let printf_addr = ffi_sym_addr(lib, "printf")
let fmt = "Hello %g %g %g\n"
let fmt_addr = addressof(fmt)

print "Printf addr: " + str(printf_addr)
print "Fmt addr: " + str(fmt_addr)

let arch = asm_arch()
if arch == "aarch64":
    asm_exec("
        stp x29, x30, [sp, #-16]!
        mov x29, sp
        fcvtzs x4, d2
        fcvtzs x0, d3
        blr x4
        ldp x29, x30, [sp], #16
        ret
    ", "void", 1.0, 2.0, printf_addr, fmt_addr)
