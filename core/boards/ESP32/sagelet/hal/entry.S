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
 *    literal 8 bytes away.
 *
 *    Those two requirements collide at the very first instruction. The image
 *    entry has to be the first thing in the loaded segment, but a pool-first
 *    layout puts 12 bytes of constants there, and the ROM's handoff appears to
 *    land on the start of the loaded segment rather than in the middle of it.
 *    Executing 0x3ff49040 as an instruction is not survivable, which matches
 *    every symptom: the ROM logs the correct load and entry addresses, the CPU
 *    then resets before a single side effect, and a 160-byte image full of
 *    nothing but direct register writes fails exactly like a 58 KB one.
 *
 *    So the entry is a single j that steps over the pool, and the real code
 *    follows it. j is PC-relative and needs no literal, so the stub is
 *    literal-free and the pool still sits behind every l32r that reads it.
 *
 * The pool also has to be within l32r's +/-256 KiB reach, which is why the
 * stack is linked immediately after the code rather than down in DRAM.
 *
 * a0 is pointed at a safe non-null address rather than argc: a0 is scratch on
 * this ABI and the emitted main keeps argc/argv in its own globals.
 *
 * Both stack registers have to be established. a15 is the callee-saved stack
 * pointer, but a1 is the *call stack* pointer, and every prologue's
 * `entry a1, N` pushes a window increment there. Setting only a15 leaves a1
 * pointing into whatever the ROM was using, so nested calls walk off the end of
 * it: leaf code that only stores to peripherals works fine, and the first
 * genuinely nested call sequence quietly corrupts memory. Both start at the
 * same top, which is how a normal ESP-IDF application is laid out.
 */

#if !defined(SAGE_ENTRY_LED) && !defined(SAGE_ENTRY_UART)
    .section .iram0.text.entry, "ax", @progbits
    .align  4

    .global boot_entry
    .type   boot_entry, @function
boot_entry:
    /* First instruction of the image, and the only one before the pool.
     * Nothing here needs a literal, so the entry is a clean jump. */
    j       entry_body
    .align  4                      /* keep the pool 4-byte aligned: the j above
                                    * is 3 bytes, and an l32r whose target sits
                                    * at an unaligned offset is rejected as
                                    * "out of range" (e.g. -13 vs -12) */

/* literal pool: reachable only backwards, hence placed here, behind the j */
L_stack_top:
    .word   _stack_top
L_boot_arg:
    .word   0x40080000            /* a safe non-null address */
L_reset:
    .word   reset_handler
    .align  4

entry_body:
    l32r    a15, L_stack_top      /* callee-saved stack pointer       */
    mov     a1,  a15              /* call-stack pointer               */
    l32r    a0,  L_boot_arg       /* scratch, not argc                */
    mov     a1,  a15
    l32r    a2,  L_reset
    mov     a3, a2
    jx      a3                    /* call reset_handler(a0, a1)       */
    .size   boot_entry, . - boot_entry
#endif /* !SAGE_ENTRY_LED && !SAGE_ENTRY_UART */

/* --- SAGE_ENTRY_LED -------------------------------------------------------
 *
 * A diagnostic that does not depend on the UART at all, built with:
 *
 *   SAGET_EXTRA_CFLAGS=-DSAGE_ENTRY_LED build.sh app
 *
 * It drives the DevKitC's onboard LED (GPIO2) with a long, deliberate
 * on/off pattern instead of a fast blink. The distinction matters: the ROM
 * reset-loops roughly ten times a second, so if the entry never takes over,
 * the LED either stays dark or appears to flicker. A clearly *solid* two
 * seconds on, two seconds off can only mean the entry ran and parked, which
 * would move the fault out of the stub and into the C startup that follows.
 *
 * All addresses below are taken from the installed IDF headers rather than
 * recalled:
 *   gpio_reg.h : DR_REG_GPIO_BASE 0x3ff44000
 *                GPIO_OUT_W1TS   base + 0x08   (set level high)
 *                GPIO_OUT_W1TC   base + 0x0c   (set level low)
 *                GPIO_ENABLE_W1TS base + 0x24   (enable output driver)
 *   io_mux_reg.h: DR_REG_IO_MUX_BASE 0x3ff49000, GPIO2 at + 0x40
 *                PIN_FUNC_GPIO = 2, FUNCSEL in bits [2:0]
 */
#if defined(SAGE_ENTRY_LED) && !defined(SAGE_ENTRY_UART)
    .section .iram0.text.entry, "ax", @progbits
    .align  4
    .global boot_entry
    .type   boot_entry, @function
boot_entry:
    /* Same reasoning as the C entry: a literal-free j, so the image's first
     * instruction is real code and the pool never sits at the load address. */
    j       led_body
    .align  4

L_wdt_prot:    .word 0x3ff480a4        /* RTC_CNTL_WDTWPROTECT    */
L_wdt_key:     .word 0x50d83aa1        /* RTC_CNTL_WDT_WKEY       */
L_wdt_cfg0:    .word 0x3ff4808c        /* RTC_CNTL_WDTCONFIG0     */
L_tg0_prot:    .word 0x3ff5f064        /* TIMG_WDTWPROTECT(0)     */
L_tg0_cfg0:    .word 0x3ff5f048        /* TIMG_WDTCONFIG0(0)      */
L_tg1_prot:    .word 0x3ff60064        /* TIMG_WDTWPROTECT(1)     */
L_tg1_cfg0:    .word 0x3ff60048        /* TIMG_WDTCONFIG0(1)      */
L_led_iomux:   .word 0x3ff49040        /* IO_MUX_GPIO2            */
L_led_out_hi:  .word 0x3ff44008        /* GPIO_OUT_W1TS           */
L_led_out_lo:  .word 0x3ff4400c        /* GPIO_OUT_W1TC           */
L_led_enable:  .word 0x3ff44024        /* GPIO_ENABLE_W1TS        */
L_led_count:   .word 60000000          /* ~0.75 s at 240 MHz     */
    .align  4

led_body:
    /* Take over the RTC watchdog FIRST. The ROM leaves it armed, so an entry
     * that merely spins gets killed before it can finish anything -- which is
     * exactly what every previous image did. Addresses and the unlock key come
     * from the installed IDF headers (rtc_cntl_reg.h):
     *   WDTWPROTECT  base + 0xa4, key 0x50d83aa1
     *   WDTCONFIG0   base + 0x8c, WDT_EN bit 31, STG0 bits [30:28]
     * with DR_REG_RTCCNTL_BASE = 0x3ff48000. Note that is NOT the 0x3ffa1060
     * block: the earlier startup.c wrote there, which is why the watchdog was
     * never actually disarmed and every image kept resetting. */
    l32r    a0, L_wdt_prot
    l32r    a1, L_wdt_key
    s32i    a1, a0, 0                  /* unlock                    */
    l32r    a0, L_wdt_cfg0
    movi    a1, 0
    s32i    a1, a0, 0                  /* clear WDT_EN and STG0    */
    l32r    a0, L_wdt_prot
    s32i    a1, a0, 0                  /* re-lock                  */

    /* Now the timer-group watchdogs. With the RTC one disarmed the reset
     * reason changed from RTCWDT_RTC_RESET to TG0WDT_SYS_RESET, so these are
     * the next ones in the chain. Offsets from timer_group_reg.h with
     * DR_REG_TIMERGROUP0_BASE = 0x3ff5f000, REG_TIMG_BASE(i) = base + i*0x1000:
     *   WPROTECT  + 0x64, unlock key TIMG_WDT_WKEY_VALUE = 0x50d83aa1
     *   WDTCONFIG0 + 0x48, WDT_EN = bit 31, STG0 = bits [30:29]
     * Both groups are disarmed: TG0 first, then TG1 at base + 0x1000. */
    l32r    a0, L_tg0_prot
    l32r    a1, L_wdt_key
    s32i    a1, a0, 0
    l32r    a0, L_tg0_cfg0
    movi    a1, 0
    s32i    a1, a0, 0
    l32r    a0, L_tg0_prot
    s32i    a1, a0, 0

    l32r    a0, L_tg1_prot
    l32r    a1, L_wdt_key
    s32i    a1, a0, 0
    l32r    a0, L_tg1_cfg0
    movi    a1, 0
    s32i    a1, a0, 0
    l32r    a0, L_tg1_prot
    s32i    a1, a0, 0

    /* GPIO2 function select <- PIN_FUNC_GPIO. FUNCSEL is bits [2:0], so
     * clear them and set the field rather than OR-ing blindly. */
    l32r    a0, L_led_iomux
    l32i    a2, a0, 0
    movi    a3, -8
    and     a2, a2, a3
    movi    a3, 2
    or      a2, a2, a3
    s32i    a2, a0, 0

    movi    a3, 4                      /* bit 2 */

led_on:
    l32r    a0, L_led_enable
    or      a2, a0, a3
    s32i    a2, a0, 0
    l32r    a0, L_led_out_hi
    or      a2, a0, a3
    s32i    a2, a0, 0
    l32r    a0, L_led_count
    mov     a1, a0
1:  addi    a1, a1, -1
    bnez    a1, 1b
    nop

    l32r    a0, L_led_out_lo
    or      a2, a0, a3
    s32i    a2, a0, 0
    l32r    a0, L_led_count
    mov     a1, a0
2:  addi    a1, a1, -1
    bnez    a1, 2b
    nop
    j       led_on
    .size   boot_entry, . - boot_entry
#endif /* SAGE_ENTRY_LED */

/* --- SAGE_ENTRY_UART -----------------------------------------------------
 *
 * The decisive test for the console, and the only one that does not depend on
 * any C code: disarm the RTC watchdog, make sure the UART0 module clock is
 * enabled, then push a literal string into the FIFO byte by byte and park.
 *
 * Built with:
 *   SAGET_EXTRA_CFLAGS=-DSAGE_ENTRY_UART build.sh app
 *
 * If the string appears, the FIFO is writable and any silence in the C path is
 * a bug above this file. If it does not, the FIFO is gated or the console is
 * not where we think it is. Addresses from uart_reg.h: FIFO +0x00,
 * STATUS +0x1c, CONF0 +0x20 with clk_en at bit 25; txfifo_cnt is bits [23:16]
 * of STATUS.
 */
#if defined(SAGE_ENTRY_UART)
    .section .iram0.text.entry, "ax", @progbits
    .align  4
    .global boot_entry
boot_entry:
    j       uart_body
    .align  4
L_wdt_prot:  .word 0x3ff480a4        /* RTC_CNTL_WDTWPROTECT  */
L_wdt_key:   .word 0x50d83aa1        /* RTC_CNTL_WDT_WKEY     */
L_wdt_cfg0:  .word 0x3ff4808c        /* RTC_CNTL_WDTCONFIG0   */
L_uart_conf: .word 0x3ff40020        /* UART0 CONF0           */
L_uart_stat: .word 0x3ff4001c        /* UART0 STATUS          */
L_uart_fifo: .word 0x3ff40000        /* UART0 FIFO            */
    .align  4
uart_body:
    l32r    a0, L_wdt_prot
    l32r    a1, L_wdt_key
    s32i    a1, a0, 0
    l32r    a0, L_wdt_cfg0
    movi    a1, 0
    s32i    a1, a0, 0
    l32r    a0, L_wdt_prot
    s32i    a1, a0, 0

    /* conf0 |= (1 << 25) to enable the module clock, leaving the ROM's
     * routing, clock source and divisor untouched. */
    l32r    a0, L_uart_conf
    l32i    a1, a0, 0
    /* Bit 25 has to be built with shifts: movi's immediate field is 12 bits,
     * so writing the literal 0x2000000 makes the assembler spill it into a
     * .literal subsection placed after the code, turning this into a forward
     * l32r and failing the link with "literal placed after use". */
    movi    a2, 1
    slli    a2, a2, 12
    slli    a2, a2, 12
    slli    a2, a2, 1               /* 1 << 25 */
    or      a1, a1, a2
    s32i    a1, a0, 0

    l32r    a3, L_uart_stat
    l32r    a4, L_uart_fifo
    /* Emit 'X' forever. Deliberately not a string from memory: mixing .byte
     * data into the same section makes the assembler split out a
     * .literal subsection that the linker places after the code, which turns
     * the l32r into a forward reference and fails the build. A single
     * immediate answers the same question -- is the FIFO writable at the baud
     * the ROM left configured? -- with no data reference at all. */
    movi    a5, 'X'
uart_next:
1:  l32i    a6, a3, 0                /* wait for the FIFO to drain */
    srli    a6, a6, 16
    slli    a6, a6, 24
    srli    a6, a6, 24               /* a6 = txfifo_cnt */
    bnez    a6, 1b
    s32i    a5, a4, 0
    j       uart_next
uart_park:
    j       uart_park
    .size   boot_entry, . - boot_entry
#endif /* SAGE_ENTRY_UART */
