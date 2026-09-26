/* esp32_hal.h — minimal bare-metal HAL for the classic ESP32 (Xtensa LX6).
 *
 * The Sage C backend emits `static` stubs for every `hw.*` native, documented
 * as "implementation defined per target". build.sh rewrites that stub block
 * into an include of this header, so the Sage-side program links against the
 * real implementations here.
 *
 * These are C shims, not the OS: all boot and OS logic lives in SageLang
 * (boot.sage / os.sage). What genuinely cannot be expressed in Sage today is
 * memory-mapped I/O, because `mem_read`/`mem_write` are intentionally confined
 * to `mem_alloc` regions by sage_mem_range_valid(), and the emitter's `hw.*`
 * hook has no flash-read or jump primitive. Those two are the only real gaps.
 *
 * Signatures match the emitted stubs: SageValue in, SageValue out. The plain
 * C helpers underneath are `hal_*` and are also handy from startup.c.
 */
#ifndef SAGET_ESP32_HAL_H
#define SAGET_ESP32_HAL_H

#include <stdint.h>

/* Forward declaration only. The emitted runtime defines `struct SageValue`
 * early and includes this header much later, so reopening the struct here
 * would be a conflicting redefinition. esp32_hal.c supplies the full
 * definition for its own translation unit. */
typedef struct SageValue SageValue;

/* --- `hw.*` natives: exactly the names the emitter knows about ---------- */
SageValue sage_native_hw_uart_init(SageValue baud);
SageValue sage_native_hw_uart_getc(void);
SageValue sage_native_hw_uart_putc(SageValue byte);
SageValue sage_native_hw_uart_puts(SageValue text);
SageValue sage_native_hw_gpio_init(SageValue pin);
SageValue sage_native_hw_gpio_set_dir(SageValue pin, SageValue out);
SageValue sage_native_hw_gpio_put(SageValue pin, SageValue value);
SageValue sage_native_hw_gpio_get(SageValue pin);
SageValue sage_native_hw_gpio_set_pull(SageValue pin, SageValue up, SageValue down);
SageValue sage_native_hw_delay_us(SageValue us);
SageValue sage_native_hw_delay_ms(SageValue ms);
SageValue sage_native_hw_uptime_ms(void);
SageValue sage_native_hw_clock_hz(void);
SageValue sage_native_hw_temp_c(void);
SageValue sage_native_hw_deep_sleep_us(SageValue us);

/* --- Bootloader-only primitives (see note above) ----------------------- */
SageValue sage_native_hw_flash_read8(SageValue addr);
SageValue sage_native_hw_flash_read32(SageValue addr);
SageValue sage_native_hw_jump(SageValue entry, SageValue stack_top);
SageValue sage_native_hw_reset(void);
SageValue sage_native_hw_rx_pending(void);

/* --- plain C helpers, also used by startup.c ---------------------------- */
uint32_t hal_uart_init(uint32_t baud);
void     hal_uart_set_baud(uint32_t sclk_hz, uint32_t baud);
uint32_t hal_uart_sclk_hz(void);
int      hal_uart_getc(void);
int      hal_uart_putc(int byte);
int      hal_uart_puts(const char* s);
int      hal_uart_rx_pending(void);
void     hal_gpio_init(uint32_t pin);
void     hal_gpio_set_dir(uint32_t pin, int output);
void     hal_gpio_put(uint32_t pin, int value);
int      hal_gpio_get(uint32_t pin);
void     hal_gpio_set_pull(uint32_t pin, int up, int down);
void     hal_delay_us(uint32_t us);
void     hal_delay_ms(uint32_t ms);
uint32_t hal_uptime_ms(void);
uint32_t hal_clock_hz(void);
float    hal_temp_c(void);
uint32_t hal_flash_read8(uint32_t addr);
uint32_t hal_flash_read32(uint32_t addr);
void     hal_jump(uint32_t entry, uint32_t stack_top);
void     hal_reset(void);

/* The emitted runtime's semaphore helpers and FFI lookup reference POSIX
 * types this newlib does provide, but dlsym needs declaring since there is no
 * <dlfcn.h> here. */
void* dlsym(void* handle, const char* symbol);

/* --- Pico SDK symbols the emitted main() always calls --------------------
 * Its default target is the Pico SDK, so main() opens with stdio_init_all()
 * and sleep_ms(). Neither exists on ESP32; both are declared here so the
 * emitted translation unit sees them, and defined in esp32_hal.c. */
void stdio_init_all(void);
void sleep_ms(uint32_t ms);

#endif /* SAGET_ESP32_HAL_H */
