/* startup.c — bare-metal bring-up for the classic ESP32.
 *
 * The Sage backend emits a normal `int main(int, char**)`, so the image needs
 * a reset entry that establishes a stack, initialises .data/.bss, parks the
 * second core, and calls main. The ESP32 ROM bootloader loads this image and
 * jumps to the image's entry point, so `reset_handler` must be a valid
 * instruction boundary and must not assume a valid stack before it sets one.
 */

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

/* RTC watchdog (TimerG 0x3FFA1Fxx) and the APP-level timer-group watchdog.
 *
 * This matters more than it looks: the ROM resets in a loop whenever the
 * second-stage image does not take over, so "it keeps rebooting" is *normal*
 * ROM behaviour and is not by itself evidence of a crash. A bare parking loop
 * trips the RTC watchdog and reproduces the same loop, which is easy to
 * misread as a fault in the image.
 *
 * Addresses are the ESP32 TRM RTC_WD_* block. An earlier version used
 * 0x3FFA1F04 for SWCONF, which is the wrong register and left the watchdog
 * armed, so the loop never stopped.
 */
#define RTC_WD_OSC_CNTL (*(volatile uint32_t *)0x3FFA1F0Cu)
#define RTC_WD_SW_CLEAR (*(volatile uint32_t *)0x3FFA1F10u)
#define RTC_WD_SW_CONF  (*(volatile uint32_t *)0x3FFA1F18u)
#define RTC_WD_FEED     (*(volatile uint32_t *)0x3FFA1F08u)
#define RTC_WD_CTRL     (*(volatile uint32_t *)0x3FFA1F00u)
#define RTC_WD_SW_CONF_RTC_WDT (1u << 3)

/* Timer-group 0 watchdog, which the ROM may also leave armed. */
#define TIMG0_WDT_EN   (*(volatile uint32_t *)0x3FF35B00u)
#define TIMG0_WDT_FEED (*(volatile uint32_t *)0x3FF35B04u)

/* RTC_CNTL guards the RTC register block with a write-protect field. It comes
 * up protected after reset, so every write to the RTC_WD_* registers below is
 * silently dropped unless the protect is cleared first. That is why disabling
 * the watchdog "did not work": the code looked right and had no effect. */
#define RTC_CNTL (*(volatile uint32_t *)0x3FFA1060u)
#define RTC_CNTL_WRITE_PROTECT 0x5500u

/* The ROM enables the RTC watchdog before handing over, and on this part it
 * does not reliably stay disabled: clearing the RTC write-protect and zeroing
 * RTC_WD_CTRL looks correct and still yields RTCWDT_RTC_RESET. So the watchdog
 * is fed rather than trusted to be off. Everything that can spin for a long
 * time must go through feed_watchdogs().
 */
static inline void feed_watchdogs(void) {
    RTC_WD_FEED = 0;
    TIMG0_WDT_FEED = 0;
}

static void take_over_watchdogs(void) {
    RTC_CNTL = RTC_CNTL & ~RTC_CNTL_WRITE_PROTECT;   /* unlock RTC block */

    /* Allow the RTC watchdog to be reset from software, clear its interrupt
     * status, then disable it. */
    RTC_WD_SW_CONF = RTC_WD_SW_CONF_RTC_WDT;
    RTC_WD_SW_CLEAR = 1;
    RTC_WD_FEED = 0;
    RTC_WD_CTRL = 0;

    RTC_CNTL = RTC_CNTL | RTC_CNTL_WRITE_PROTECT;     /* re-lock        */

    /* And the timer-group watchdog, in case the ROM armed it too. */
    TIMG0_WDT_FEED = 0;
    TIMG0_WDT_EN = 0;
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

    /* Own the watchdogs before anything that can take a long time. */
    take_over_watchdogs();

#if defined(SAGE_ENTRY_HEARTBEAT)
    heartbeat_init();
    heartbeat_str("\r\n[SAGE-ENTRY]\r\n");
#endif

    /* First, before anything that can take a long time: own the watchdogs. */
    take_over_watchdogs();

    /* Clear .bss before any C code (including the Sage runtime) runs. */
    for (uint32_t* b = &_bss_start; b < &_bss_end; ) {
        *b++ = 0;
    }

    /* Copy .data from its load address in the memory-mapped flash window. */
    {
        const uint32_t* src = &_data_load;
        uint32_t* dst = &_data_start;
        while (dst < &_data_end) {
            *dst++ = *src++;
        }
    }

    /* Deliberately leave CPU1 alone. The ROM bootloader has already released
     * it into its own idle loop, and re-pointing RTC_AUTOSTART_CPUS_REG from an
     * app that never asked for SMP is how you get a reset storm: on this
     * toolchain the `memsrc gld` cache barrier that gesture needs is not
     * assemblable, so the entry would not be visible to the instruction cache.
     * SageletOS is single-core by design. */
    (void)park_here;

    main(0, 0);

    /* main() is not expected to return; park rather than fall off the end of
     * the image into whatever follows in flash. */
    for (;;) {
        feed_watchdogs();
        __asm__ __volatile__("rsync" ::: "memory");
    }
}
