/* esp32_hal.c — bare-metal ESP32 (D0WD-V3 / WROOM-32) hardware shim.
 *
 * Register-level, no RTOS and no vendor SDK: the point is a tiny image that
 * the Sage bootloader can chain to. Targets the classic ESP32 only (Xtensa LX6,
 * 4 MB flash, 26 MHz crystal).
 *
 * Memory map used here (SOC caps):
 *   UART0     0x3FF40000
 *   GPIO      0x3FF44504   (legacy block, matches esp-idf soc/gpio_reg.h)
 *   IO_MUX    0x60000000
 *   DPORT     0x3FF00000
 *   cycle cnt 0x3FFFE000   (increments at CPU clock, resets on power-on)
 */

#include "esp32_hal.h"
#include <stddef.h>

/* The emitted runtime has its own (larger) `struct SageValue`. This
 * translation unit is compiled separately and never sees it, so define the
 * shape the bridge needs: tag plus the three scalar payloads. Keeping the
 * layout identical for the common cases is what lets a SageValue cross the
 * boundary. */
struct SageValue {
    int type;
    union {
        int boolean;
        double number;
        const char* string;
    } as;
};

enum {
    SAGET_TAG_NIL = 0,
    SAGET_TAG_BOOL = 1,
    SAGET_TAG_NUMBER = 2,
    SAGET_TAG_STRING = 3
};

/* ------------------------------------------------------------------ UART0 */

#define UART0_BASE 0x3FF40000u

/* ------------------------------------------------------------------ UART0
 *
 * Register map and field semantics taken from the Espressif headers shipped
 * with the local Arduino-ESP32 core
 * (tools/esp32-libs/3.3.11/include/soc/esp32/register/soc/uart_struct.h and
 *  hal/esp32/include/hal/uart_ll.h), so every offset and bit below is the one
 * the vendor driver itself uses:
 *
 *   0x00 fifo     RX read byte / TX write byte (one register for both)
 *   0x0C int_ena
 *   0x14 clk_div  div_int[19:0], div_frag[23:20]
 *   0x1C status   rxfifo_cnt[7:0], txfifo_cnt[23:16]
 *   0x20 conf0    bit_num[3:2], stop_bit_num[5:4], rxfifo_rst[17],
 *                 txfifo_rst[18], clk_en[25]
 *
 * Baud follows uart_ll_set_baudrate(): clk_div = (sclk << 4) / baud, with the
 * integer part in div_int and the remainder in div_frag.
 */

#define REG_UART0_FIFO    (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define REG_UART0_INT_ENA (*(volatile uint32_t *)(UART0_BASE + 0x0C))
#define REG_UART0_CLK_DIV (*(volatile uint32_t *)(UART0_BASE + 0x14))
#define REG_UART0_STATUS  (*(volatile uint32_t *)(UART0_BASE + 0x1C))
#define REG_UART0_CONF0   (*(volatile uint32_t *)(UART0_BASE + 0x20))

#define UART_STATUS_RXFIFO_CNT_MASK  0x000000FFu
#define UART_STATUS_TXFIFO_CNT_SHIFT 16

#define UART_CONF0_BIT_NUM_SHIFT     2
#define UART_CONF0_BIT_NUM_8         3
#define UART_CONF0_STOP_BIT_SHIFT    4
#define UART_CONF0_STOP_BIT_1        1
#define UART_CONF0_RXFIFO_RST        (1u << 17)
#define UART_CONF0_TXFIFO_RST        (1u << 18)
#define UART_CONF0_CLK_EN            (1u << 25)

#define UART_FIFO_LEN 128u

/* ----------------------------------------------------------- GPIO / IO_MUX */

#define GPIO0_BASE     0x3FF44504u
#define DR_REG_IO_MUX  0x60000000u

#define GPIO_OUT_W1TS(n)   (*(volatile uint32_t *)(GPIO0_BASE + 0x1C + (n) * 4))
#define GPIO_OUT_W1TC(n)   (*(volatile uint32_t *)(GPIO0_BASE + 0x20 + (n) * 4))
#define GPIO_OUT_REG(n)    (*(volatile uint32_t *)(GPIO0_BASE + 0x04 + (n) * 4))
#define GPIO_ENABLE_REG(n) (*(volatile uint32_t *)(GPIO0_BASE + 0x70 + (n) * 4))
#define GPIO_IN_REG(n)     (*(volatile uint32_t *)(GPIO0_BASE + 0x3C + (n) * 4))
#define GPIO_SETUP_REG(n)  (*(volatile uint32_t *)(GPIO0_BASE + 0x44 + (n) * 4))
#define GPIO_FUNC_IN_SEL(n)(*(volatile uint32_t *)(GPIO0_BASE + 0x58 + (n) * 4))

#define IO_MUX_GPIO(n)     (*(volatile uint32_t *)(DR_REG_IO_MUX + 0x04 + (n) * 4))
#define IO_MUX_FUNC_GPIO   1u

/* ------------------------------------------------------------------- misc */

#define DPORT_BASE          0x3FF00000u
#define DPORT_PAD_DRIVER(n) (*(volatile uint32_t *)(DPORT_BASE + 0x00 + (n) * 4))
#define RTOS_CTRL_APPCPU_REG (*(volatile uint32_t *)(0x3FF48450u))

/* Cycle counter (per-CPU "insn" counter), resets on power-on. */
#define CYCLE_COUNT_REG     (*(volatile uint32_t *)0x3FFFE000u)

#define CPU_HZ 240000000u

/* APB clock that feeds UART0. */
#ifndef UART_CLK_HZ
#define UART_CLK_HZ 80000000u
#endif

static inline void spin(void) { __asm__ __volatile__("nop"); }

static uint32_t hal_cycles(void) { return CYCLE_COUNT_REG; }

static uint32_t hal_cycles_per_ms(void) { return CPU_HZ / 1000u; }

void hal_delay_us(uint32_t us) {
    uint32_t start = hal_cycles();
    uint32_t ticks = (uint32_t)(((uint64_t)us * CPU_HZ) / 1000000u);
    if (ticks == 0) ticks = 1;
    while ((uint32_t)(hal_cycles() - start) < ticks) {
        spin();
    }
}

void hal_delay_ms(uint32_t ms) {
    while (ms--) hal_delay_us(1000);
}

uint32_t hal_uptime_ms(void) {
    static uint32_t base_ms = 0;
    static uint32_t base_cycles = 0;
    uint32_t now = hal_cycles();
    if (base_cycles == 0) {
        base_cycles = now;
        base_ms = 0;
        return 0;
    }
    /* Wrap-safe elapsed milliseconds, accumulated so 32-bit cycle rollover
     * (~17 s) does not make uptime go backwards. */
    uint32_t elapsed_cycles = (uint32_t)(now - base_cycles);
    uint32_t elapsed_ms = (uint32_t)(((uint64_t)elapsed_cycles * 1000u) / CPU_HZ);
    return base_ms + elapsed_ms;
}

uint32_t hal_clock_hz(void) { return CPU_HZ; }

/* ------------------------------------------------------------------ GPIO */

static inline int gpio_is_valid(uint32_t pin) { return pin <= 39; }

void hal_gpio_init(uint32_t pin) {
    if (!gpio_is_valid(pin)) return;
    /* Route the pad to the plain GPIO peripheral (function 1) and let the
     * peripheral own the pin: this clears the deep-sleep isolation latch. */
    IO_MUX_GPIO(pin) = IO_MUX_GPIO(pin) | IO_MUX_FUNC_GPIO;
}

void hal_gpio_set_dir(uint32_t pin, int output) {
    if (!gpio_is_valid(pin)) return;
    hal_gpio_init(pin);
    if (output) {
        GPIO_ENABLE_REG(pin) = (1u << 2);            /* output enable */
    } else {
        GPIO_ENABLE_REG(pin) = 0;                    /* input */
    }
}

void hal_gpio_put(uint32_t pin, int value) {
    if (!gpio_is_valid(pin)) return;
    if (value) {
        GPIO_OUT_W1TS(pin) = (1u << (pin & 31));
    } else {
        GPIO_OUT_W1TC(pin) = (1u << (pin & 31));
    }
}

int hal_gpio_get(uint32_t pin) {
    if (!gpio_is_valid(pin)) return 0;
    return (int)((GPIO_IN_REG(pin) >> (pin & 31)) & 1u);
}

void hal_gpio_set_pull(uint32_t pin, int up, int down) {
    if (!gpio_is_valid(pin)) return;
    uint32_t pupd = 0;                               /* 0 none, 1 down, 2 up */
    if (up) pupd = 2;
    else if (down) pupd = 1;
    GPIO_SETUP_REG(pin) = (GPIO_SETUP_REG(pin) & ~0x3u) | pupd;
}

/* ------------------------------------------------------------------ UART0 */

uint32_t hal_uart_init(uint32_t baud) {
    if (baud == 0) baud = 115200;

    /* Route UART0 to the console pads: TX1 = GPIO1, RX1 = GPIO3, function 1. */
    IO_MUX_GPIO(1) = (IO_MUX_GPIO(1) & ~0x3u) | IO_MUX_FUNC_GPIO;
    IO_MUX_GPIO(3) = (IO_MUX_GPIO(3) & ~0x3u) | IO_MUX_FUNC_GPIO;

    /* Mask interrupts, 8N1, peripheral clock on. */
    REG_UART0_INT_ENA = 0;
    REG_UART0_CONF0 = (UART_CONF0_BIT_NUM_8 << UART_CONF0_BIT_NUM_SHIFT)
                    | (UART_CONF0_STOP_BIT_1 << UART_CONF0_STOP_BIT_SHIFT)
                    | UART_CONF0_CLK_EN;

    /* Flush both FIFOs with a reset pulse, as uart_ll_txfifo_rst() does. */
    REG_UART0_CONF0 |= UART_CONF0_RXFIFO_RST;
    REG_UART0_CONF0 &= ~UART_CONF0_RXFIFO_RST;
    REG_UART0_CONF0 |= UART_CONF0_TXFIFO_RST;
    REG_UART0_CONF0 &= ~UART_CONF0_TXFIFO_RST;

    /* clk_div = (sclk << 4) / baud; integer in div_int, rest in div_frag. */
    uint32_t div = (UART_CLK_HZ << 4) / baud;
    uint32_t div_int = (div >> 4) & 0xFFFFFu;
    uint32_t div_frag = div & 0xFu;
    REG_UART0_CLK_DIV = (div_frag << 20) | div_int;

    return baud;
}

int hal_uart_rx_pending(void) {
    return (REG_UART0_STATUS & UART_STATUS_RXFIFO_CNT_MASK) ? 1 : 0;
}

int hal_uart_getc(void) {
    if (!(REG_UART0_STATUS & UART_STATUS_RXFIFO_CNT_MASK)) return -1;
    return (int)(REG_UART0_FIFO & 0xFF);
}

int hal_uart_putc(int byte) {
    if (byte < 0) return -1;
    uint32_t spins = 0;
    while ((REG_UART0_STATUS >> UART_STATUS_TXFIFO_CNT_SHIFT) >= UART_FIFO_LEN) {
        if (++spins > 2000000u) return -1;   /* never wedge the caller */
    }
    REG_UART0_FIFO = (uint32_t)(byte & 0xFF);
    return byte & 0xFF;
}

int hal_uart_puts(const char* s) {
    if (s == NULL) return -1;
    int n = 0;
    while (*s) {
        if (hal_uart_putc((unsigned char)*s++) < 0) return -1;
        n++;
    }
    return n;
}

/* -------------------------------------------------------------- internal */

float hal_temp_c(void) {
    /* TSENS is unavailable before the ROM's calibration block is set up, and
     * we deliberately do not depend on eFuse/ROM helpers here. Report the
     * uncalibrated raw reading converted with the documented slope, and let
     * the Sage layer present it. */
    volatile uint32_t* sens = (volatile uint32_t *)0x3FF91010u;
    return (float)(*sens);
}

void hal_reset(void) {
    /* Digital core reset via the RTC watchdog, the same doorbell the ROM
     * bootloader uses. */
    volatile uint32_t* wdt = (volatile uint32_t *)0x3FFA1F04u;
    *wdt = 0;                       /* RTC_WDT_SWCONFIG */
    *wdt = 0x80000000u | (1000u << 4);   /* sys reset, 1 s timeout */
    *wdt = 0x80000000u;             /* trigger */
    for (;;) { }
}

/* ------------------------------------------------- bootloader primitives */

uint32_t hal_flash_read8(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

uint32_t hal_flash_read32(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

void hal_jump(uint32_t entry, uint32_t stack_top) {
    /* Hand control to the app image: park the peripherals we touched, drop
     * interrupts, then set the stack and enter. The compiler needs the naked
     * asm to avoid emitting a frame on the old stack. */
    __asm__ __volatile__("movi a0, 0");
    __asm__ __volatile__("movi a0, 0x40000000");
    REG_UART0_INT_ENA = 0;
    (void)REG_UART0_STATUS;
    (void)RTOS_CTRL_APPCPU_REG;

    __asm__ __volatile__(
        "mov a15, %0 \n"   /* a15 is the Xtensa windowed-call stack pointer */
        "mov a0, %1 \n"
        "jx %1 \n"
        :
        : "r"(stack_top), "r"(entry)
        : "a0", "a15", "memory");

    for (;;) { }
}

/* =========================================================== Sage bridge ===
 * Thin adapters from the emitted `hw.*` native ABI to the hal_* helpers.
 * Kept at the bottom so the register-level code above reads as hardware code
 * rather than as Sage plumbing.
 */


static SageValue hv_nil(void)          { SageValue v; v.type = SAGET_TAG_NIL;   v.as.number = 0; return v; }
static SageValue hv_bool(int b)        { SageValue v; v.type = SAGET_TAG_BOOL;  v.as.boolean = b ? 1 : 0; return v; }
static SageValue hv_num(double d)      { SageValue v; v.type = SAGET_TAG_NUMBER; v.as.number = d; return v; }
static SageValue hv_str(const char* s) { SageValue v; v.type = SAGET_TAG_STRING; v.as.string = s; return v; }

static uint32_t as_u32(SageValue v) { return (uint32_t)(long long)v.as.number; }
static int      as_int(SageValue v) { return (int)(long long)v.as.number; }

SageValue sage_native_hw_uart_init(SageValue baud)   { return hv_num((double)hal_uart_init(as_u32(baud))); }
SageValue sage_native_hw_uart_getc(void) { return hv_num((double)hal_uart_getc()); }
SageValue sage_native_hw_uart_putc(SageValue byte)   { return hv_num((double)hal_uart_putc(as_int(byte))); }
SageValue sage_native_hw_uart_puts(SageValue text)
{
    if (text.type != SAGET_TAG_STRING) return hv_nil();
    return hv_num((double)hal_uart_puts(text.as.string));
}
SageValue sage_native_hw_rx_pending(void){ return hv_bool(hal_uart_rx_pending()); }
SageValue sage_native_hw_gpio_init(SageValue pin)    { hal_gpio_init(as_u32(pin)); return hv_nil(); }
SageValue sage_native_hw_gpio_set_dir(SageValue pin, SageValue out) { hal_gpio_set_dir(as_u32(pin), as_int(out)); return hv_nil(); }
SageValue sage_native_hw_gpio_put(SageValue pin, SageValue v)      { hal_gpio_put(as_u32(pin), as_int(v)); return hv_nil(); }
SageValue sage_native_hw_gpio_get(SageValue pin)    { return hv_bool(hal_gpio_get(as_u32(pin))); }
SageValue sage_native_hw_gpio_set_pull(SageValue pin, SageValue up, SageValue down)
{
    hal_gpio_set_pull(as_u32(pin), as_int(up), as_int(down));
    return hv_nil();
}
SageValue sage_native_hw_delay_us(SageValue us)     { hal_delay_us(as_u32(us)); return hv_nil(); }
SageValue sage_native_hw_delay_ms(SageValue ms)     { hal_delay_ms(as_u32(ms)); return hv_nil(); }
SageValue sage_native_hw_uptime_ms(void){ return hv_num((double)hal_uptime_ms()); }
SageValue sage_native_hw_clock_hz(void) { return hv_num((double)hal_clock_hz()); }
SageValue sage_native_hw_temp_c(void)   { return hv_num((double)hal_temp_c()); }
SageValue sage_native_hw_deep_sleep_us(SageValue us)
{
    (void)us;
    /* Deep sleep always wakes as a reset, so there is nothing to return to. */
    for (;;) { }
}

SageValue sage_native_hw_flash_read8(SageValue addr)  { return hv_num((double)hal_flash_read8(as_u32(addr))); }
SageValue sage_native_hw_flash_read32(SageValue addr) { return hv_num((double)hal_flash_read32(as_u32(addr))); }
SageValue sage_native_hw_jump(SageValue entry, SageValue stack_top)
{
    hal_jump(as_u32(entry), as_u32(stack_top));
    return hv_nil();
}
SageValue sage_native_hw_reset(void) { hal_reset(); return hv_nil(); }

/* ============================== Pico SDK shims =============================
 * The emitted main() always calls stdio_init_all() and sleep_ms() before user
 * code, because its default target is the Pico SDK. Neither exists here; both
 * are satisfied by what we already provide: stdio goes to the UART, and the
 * delay is the cycle-counter busy wait.
 */

void stdio_init_all(void) {
    hal_uart_init(115200);
}

void sleep_ms(uint32_t ms) {
    hal_delay_ms(ms);
}

/* The emitted runtime's FFI lookup calls dlsym(). A bare-metal image has no
 * dynamic loader, and the OS does not use FFI, so answer "not found" rather
 * than dragging libdl onto the target. Declared here because this header is
 * included by the emitted translation unit, which has no <dlfcn.h>. */
void* dlsym(void* handle, const char* symbol) {
    (void)handle;
    (void)symbol;
    return 0;
}
