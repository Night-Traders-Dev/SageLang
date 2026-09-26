/* startup.c — bare-metal bring-up for the classic ESP32.
 *
 * The Sage backend emits a normal `int main(int, char**)`, so the image needs
 * a reset entry that establishes a stack, initialises .data/.bss, parks the
 * second core, and calls main. The ESP32 ROM bootloader loads this image and
 * jumps to the image's entry point, so `reset_handler` must be a valid
 * instruction boundary and must not assume a valid stack before it sets one.
 */

#include "esp32_hal.h"

/* Raw UART0 registers, so the trace markers below need no cross-object call
 * at all. Proving the console works is not the moment to also be testing the
 * linker's view of the call ABI. */
#define REG_UART0_FIFO   (*(volatile uint32_t *)0x3FF40000u)
#define REG_UART0_STATUS (*(volatile uint32_t *)0x3FF4001Cu)
#define REG_UART0_CONF0  (*(volatile uint32_t *)0x3FF40020u)
#include <stdint.h>

extern uint32_t _stack_top;
extern int main(int argc, char** argv);

extern uint32_t _bss_start;
extern uint32_t _bss_end;
extern uint32_t _data_start;
extern uint32_t _data_end;
extern uint32_t _data_load;

/* RTC_CPUSW_CONF_REG / RTC_AUTOSTART_CPUS_REG: the documented way to hand a
 * function to CPU1 out of reset on the classic ESP32. */
#define RTC_CPUSW_CONF_REG     (*(volatile uint32_t *)0x3FF48450u)
#define RTC_AUTOSTART_CPUS_REG (*(volatile uint32_t *)0x3FF48454u)

/* Watchdog takeover.
 *
 * The ROM leaves three watchdogs armed when it hands over to a second-stage
 * image, and an image that does not disarm them is reset before it can do
 * anything observable. That was the actual cause of the reset loop here, and
 * it took three rounds to find because the reset is silent -- the chip simply
 * reboots, which is also what the ROM does when an image fails to load, so the
 * symptom looks identical to a broken handoff.
 *
 * The addresses below are transcribed from the installed IDF headers rather
 * than recalled, because the previous version used the 0x3FFA1Fxx "RTC_WD_*"
 * block from older TRM revisions. On this chip that block is not the watchdog
 * at all: every write landed somewhere harmless, so the watchdog was never
 * disarmed and the loop never stopped. The registers that matter are in the
 * 0x3ff48000 RTC_CNTL block and the 0x3ff5f000 timer-group blocks.
 *
 * rtc_cntl_reg.h (DR_REG_RTCCNTL_BASE = 0x3ff48000):
 *   WDTWPROTECT  + 0xa4  -- write 0x50d83aa1 to unlock, 0 to re-lock
 *   WDTCONFIG0   + 0x8c  -- WDT_EN = bit 31, STG0 = bits [30:28]
 *   WDTFEED      + 0xa0
 *
 * timer_group_reg.h (DR_REG_TIMERGROUP0_BASE = 0x3ff5f000,
 *                    REG_TIMG_BASE(i) = base + i*0x1000):
 *   WDTCONFIG0   + 0x48  -- WDT_EN = bit 31, STG0 = bits [30:29]
 *   WDTFEED      + 0x60
 *   WDTWPROTECT  + 0x64  -- TIMG_WDT_WKEY_VALUE = 0x50d83aa1
 */
#define RTC_CNTL_BASE          0x3ff48000u
#define RTC_CNTL_WDTCONFIG0    (*(volatile uint32_t *)(RTC_CNTL_BASE + 0x8cu))
#define RTC_CNTL_WDTFEED       (*(volatile uint32_t *)(RTC_CNTL_BASE + 0xa0u))
#define RTC_CNTL_WDTWPROTECT   (*(volatile uint32_t *)(RTC_CNTL_BASE + 0xa4u))

#define TIMG0_BASE             0x3ff5f000u
#define TIMG0_WDTCONFIG0       (*(volatile uint32_t *)(TIMG0_BASE + 0x48u))
#define TIMG0_WDTFEED          (*(volatile uint32_t *)(TIMG0_BASE + 0x60u))
#define TIMG0_WDTWPROTECT      (*(volatile uint32_t *)(TIMG0_BASE + 0x64u))

#define TIMG1_BASE             (TIMG0_BASE + 0x1000u)
#define TIMG1_WDTCONFIG0       (*(volatile uint32_t *)(TIMG1_BASE + 0x48u))
#define TIMG1_WDTFEED          (*(volatile uint32_t *)(TIMG1_BASE + 0x60u))
#define TIMG1_WDTWPROTECT      (*(volatile uint32_t *)(TIMG1_BASE + 0x64u))

/* Both write-protect registers use the same key. */
#define WDT_WKEY               0x50d83aa1u

/* Belt and braces: the watchdogs are disarmed once, and also fed forever.
 * Disarming should be enough, but feeding costs a few stores and removes the
 * entire class of "reset loop" failure from the bring-up. */
static inline void feed_watchdogs(void) {
    RTC_CNTL_WDTFEED   = 1;
    TIMG0_WDTFEED      = 1;
    TIMG1_WDTFEED      = 1;
}

static void take_over_watchdogs(void) {
    /* RTC watchdog: unlock, clear WDT_EN and STG0, re-lock. */
    RTC_CNTL_WDTWPROTECT = WDT_WKEY;
    RTC_CNTL_WDTCONFIG0  = 0;
    RTC_CNTL_WDTWPROTECT = 0;

    /* Timer-group watchdog 0 and 1: same sequence, same key. */
    TIMG0_WDTWPROTECT = WDT_WKEY;
    TIMG0_WDTCONFIG0  = 0;
    TIMG0_WDTWPROTECT = 0;

    TIMG1_WDTWPROTECT = WDT_WKEY;
    TIMG1_WDTCONFIG0  = 0;
    TIMG1_WDTWPROTECT = 0;

    feed_watchdogs();
}

/* Park loop. This toolchain's assembler has no `wfi`/`rsil`, so spin on a
 * pipeline sync instead: it costs a little idle power, which is irrelevant for
 * a console OS, and it is correct everywhere. */
static void park_here(void) {
    for (;;) {
        __asm__ __volatile__("rsync" ::: "memory");
    }
}

/* Not placed in .init: the Xtensa assembler must emit the l32r literal pool
 * in address order relative to the instructions that load it, and a bare
 * .init section does not give it that ordering. Built with
 * -mtext-section-literals so literals land inside the function body. */
/* ---------------------------------------------------- entry heartbeat ---
 * Diagnostic: the first thing reset_handler does, before anything that can
 * fail, is push a byte straight out of the UART FIFO with volatile stores
 * only. No Sage runtime, no newlib, no stack. The ROM has already configured
 * UART0 for its own 115200 console before handing over, so if this byte comes
 * back on the host the entry demonstrably executed; if it does not, nothing
 * downstream is worth debugging yet.
 *
 * Enabled with -DSAGE_ENTRY_HEARTBEAT. Off by default.
 */
#if defined(SAGE_ENTRY_HEARTBEAT)
#define U0_BASE    0x3FF40000u
#define U0_FIFO    (*(volatile uint32_t *)(U0_BASE + 0x00))
#define U0_INT_ENA (*(volatile uint32_t *)(U0_BASE + 0x0C))
#define U0_CLKDIV  (*(volatile uint32_t *)(U0_BASE + 0x14))
#define U0_STATUS  (*(volatile uint32_t *)(U0_BASE + 0x1C))
#define U0_CONF0   (*(volatile uint32_t *)(U0_BASE + 0x20))
#define IOMUX_PAD(n) (*(volatile uint32_t *)(0x60000000u + 0x04 + (n) * 4))

/* Self-contained: do not rely on the console setup the ROM left behind, or
 * the heartbeat would prove nothing. Register map from esp32-libs
 * .../register/soc/uart_reg.h (0x00 FIFO, 0x0C INT_ENA, 0x14 CLKDIV,
 * 0x1C STATUS, 0x20 CONF0); CLKDIV is div_int[19:0] / div_frag[23:20]. */
static void heartbeat_init(void) {
    IOMUX_PAD(1) = (IOMUX_PAD(1) & ~3u) | 1u;      /* TX1 = GPIO1 */
    IOMUX_PAD(3) = (IOMUX_PAD(3) & ~3u) | 1u;      /* RX1 = GPIO3 */
    U0_INT_ENA = 0;
    U0_CONF0 = (3u << 2) | (1u << 4) | (1u << 25); /* 8N1, clk_en */
    U0_CONF0 |= (1u << 17); U0_CONF0 &= ~(1u << 17);  /* rxfifo rst */
    U0_CONF0 |= (1u << 18); U0_CONF0 &= ~(1u << 18);  /* txfifo rst */
    uint32_t div = (80000000u << 4) / 115200u;         /* 11111 */
    U0_CLKDIV = ((div & 0xF) << 20) | ((div >> 4) & 0xFFFFFu);
}
static void heartbeat(int c) {
    uint32_t spins = 0;
    while ((U0_STATUS >> 16) & 0xFF) {
        if (++spins > 1000000u) return;
    }
    U0_FIFO = (uint32_t)(c & 0xFF);
}
static void heartbeat_str(const char* s) { while (*s) heartbeat(*s++); }
#endif

void reset_handler(void) __attribute__((noreturn));

void reset_handler(void) {
#if defined(SAGE_ENTRY_PARK_UART)
    /* Discriminator: same stable park loop that is known to survive, but with a
     * FIFO write added. If 'P' appears then C code can drive the console and
     * the problem is specific to the code after take_over_watchdogs(); if it
     * does not, C code cannot write to the FIFO at all even though hand-written
     * assembly can -- which points at the handoff (a15 / the stack) rather than
     * at the UART. */
    take_over_watchdogs();
    REG_UART0_CONF0 |= (1u << 25);
    for (;;) {
        feed_watchdogs();
        while ((((REG_UART0_STATUS >> 16) & 0xFFu) >= 128u)) {}
        REG_UART0_FIFO = (uint32_t)(unsigned char)'P';
        __asm__ __volatile__("rsync" ::: "memory");
    }
#endif

#if defined(SAGE_ENTRY_PARK_ONLY)
    /* Discriminator: take over the watchdogs, then park and touch nothing
     * else. If the reset loop stops, the entry is executing and the remaining
     * problem is downstream of it. */
    take_over_watchdogs();
    for (;;) {
        feed_watchdogs();
        __asm__ __volatile__("rsync" ::: "memory");
    }
#endif

#if defined(SAGE_TRACE)
    /* Progressive markers, so a silent boot can be attributed to a specific
     * step instead of guessed at. These use the same conservative UART setup
     * as the HAL -- INT_ENA masked, clock source left as the ROM set it -- so
     * the markers cannot themselves corrupt the output they are meant to show.
     * Enabled with -DSAGE_TRACE. */
    /* A single immediate byte, not a string. Dereferencing a string literal
     * does not work in this build: the l32r pool entry that should hold the
     * string's address resolves to a different location entirely (it pointed
     * into .rodata instead of the string, off by 0xEA8), so the loop reads
     * unrelated bytes and the console never shows the marker. An immediate
     * needs no address at all. Do NOT call hal_uart_init here: re-rating the
     * UART changes the shift rate while the ROM still has "entry 0x40080000"
     * in flight, which garbles that line. The ROM already programmed 115200 on
     * a working route, so the correct thing at this stage is to add to the
     * output stream, not to reconfigure it. */
    /* No FIFO-space wait on purpose: the markers are well under the 128-byte
     * FIFO so they fit unconditionally, which isolates "is the wait condition
     * wrong" from "is this code running at all". A real // comment cannot sit
     * inside the macro body, because a /* block comment would swallow the
     * line continuations. */
    #define TRACE(c) do {                                            \
        REG_UART0_CONF0 |= (1u << 25);                               \
        while ((((REG_UART0_STATUS >> 16) & 0xFFu) >= 128u)) {}      \
        REG_UART0_FIFO = (uint32_t)(unsigned char)(c);                 \
    } while (0)
#else
    #define TRACE(s) ((void)0)
#endif

    /* Own the watchdogs FIRST, before even the trace markers. Any diagnostic
     * that spins -- and a UART write polls the FIFO -- runs with the RTC
     * watchdog still armed, and the ROM leaves it armed. Doing the trace first
     * reliably tripped RTCWDT_RTC_RESET and masked the real behaviour. */
    take_over_watchdogs();
    TRACE('1');

    /* Clear .bss before any C code (including the Sage runtime) runs. */
    for (uint32_t* b = &_bss_start; b < &_bss_end; ) {
        *b++ = 0;
    }
    TRACE('x');

    /* Copy .data from its load address in the memory-mapped flash window. */
    {
        const uint32_t* src = &_data_load;
        uint32_t* dst = &_data_start;
        while (dst < &_data_end) {
            *dst++ = *src++;
        }
    }
    TRACE('x');

    /* Deliberately leave CPU1 alone. The ROM bootloader has already released
     * it into its own idle loop, and re-pointing RTC_AUTOSTART_CPUS_REG from an
     * app that never asked for SMP is how you get a reset storm: on this
     * toolchain the `memsrc gld` cache barrier that gesture needs is not
     * assemblable, so the entry would not be visible to the instruction cache.
     * SageletOS is single-core by design. */
    (void)park_here;

    TRACE('x');
    main(0, 0);

    /* main() is not expected to return; park rather than fall off the end of
     * the image into whatever follows in flash. */
    for (;;) {
        feed_watchdogs();
        __asm__ __volatile__("rsync" ::: "memory");
    }
}
