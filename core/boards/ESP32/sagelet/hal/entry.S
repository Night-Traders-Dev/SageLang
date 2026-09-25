/* entry.S — ESP32 second-stage entry stub.
 *
 * Two things make this necessary.
 *
 * 1. Stack. The ROM jumps to the image entry with no ABI contract in place.
 *    In the Xtensa windowed ABI a15 is the callee-saved stack pointer, and the
 *    ROM does not establish it, so entering C directly runs with whatever a15
 *    was left holding — a pointer into the ROM's own small stack. The first
 *    call would then corrupt memory before main() is reached. The entry
 *    establishes the stack before calling anything.
 *
 * 2. Literal placement. l32r on this toolchain only encodes a *backward*
 *    (negative) offset: the literal pool has to precede the instruction that
 *    loads it. A forward label — which is how l32r is usually written — is
 *    rejected with "operand 2 of 'l32r' has out of range value", even for a
 *    literal 8 bytes away. GCC gets this right by emitting the pool first (see
 *    the compiler's own output, offsets like 0xfffc0004), so this file follows
 *    the same convention.
 *
 * The pool also has to be within l32r's +/-256 KiB reach, which is why the
 * stack is linked immediately after the code rather than down in DRAM.
 *
 * a0 is pointed at a safe non-null address rather than argc: a0 is scratch on
 * this ABI and the emitted main keeps argc/argv in its own globals.
 */

    .section .iram0.text.entry, "ax", @progbits
    .align  4

/* literal pool first: l32r reaches backwards only */
L_stack_top:
    .word   _stack_top
L_boot_arg:
    .word   0x40080000            /* a safe non-null address */
L_reset:
    .word   reset_handler

    .global boot_entry
    .type   boot_entry, @function
boot_entry:
    l32r    a15, L_stack_top      /* stack pointer                    */
    l32r    a0,  L_boot_arg       /* scratch, not argc                */
    mov     a1,  a15
    l32r    a2,  L_reset
    mov     a3, a2
    jx      a3                    /* call reset_handler(a0, a1)       */
    .size   boot_entry, . - boot_entry
