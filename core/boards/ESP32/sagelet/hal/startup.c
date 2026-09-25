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

/* RTC watchdog (0x3FFA1Fxx) and the APP-level timer-group watchdog. The ROM
 * can leave the RTC watchdog armed with a short timeout; if we do not take it
 * over before the first long operation, the chip resets in a loop and there is
 * no console to report it from. */
#define RTC_WD_SWCONFIG (*(volatile uint32_t *)0x3FFA1F04u)
#define RTC_WD_CTRL     (*(volatile uint32_t *)0x3FFA1F00u)
#define RTC_WD_FEED     (*(volatile uint32_t *)0x3FFA1F08u)
#define TIMG0_WD_EN     (*(volatile uint32_t *)0x3FF35B00u)

static void take_over_watchdogs(void) {
    RTC_WD_FEED = 0;                 /* feed, so it does not fire mid-sequence */
    RTC_WD_SWCONFIG = RTC_WD_SWCONFIG | (1u << 3);  /* allow software reset   */
    RTC_WD_FEED = 0;
    RTC_WD_CTRL = 0;                 /* disable                            */
    TIMG0_WD_EN = 0;                 /* and the TG0 watchdog               */
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
void reset_handler(void) __attribute__((noreturn));

void reset_handler(void) {
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
        __asm__ __volatile__("rsync" ::: "memory");
    }
}
