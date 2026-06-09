// boards/pico_gpio.h

#ifndef PICO_GPIO_H
#define PICO_GPIO_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Basic GPIO Functions
// ============================================================================

/**
 * @brief Initialize a GPIO pin
 * @param pin GPIO pin number (0-29)
 * @param out true for output, false for input
 */
void pico_gpio_init(uint pin, bool out);

/**
 * @brief Write to a GPIO output pin
 * @param pin GPIO pin number
 * @param value true for HIGH, false for LOW
 */
void pico_gpio_write(uint pin, bool value);

/**
 * @brief Read from a GPIO input pin
 * @param pin GPIO pin number
 * @return true if HIGH, false if LOW
 */
bool pico_gpio_read(uint pin);

/**
 * @brief Toggle a GPIO output pin (thread-safe)
 * @param pin GPIO pin number
 */
void pico_gpio_toggle(uint pin);

/**
 * @brief Set pull-up or pull-down resistor
 * @param pin GPIO pin number
 * @param up true for pull-up, false for pull-down
 */
void pico_gpio_pull(uint pin, bool up);

// ============================================================================
// Multicore Heartbeat Functions
// ============================================================================

/**
 * @brief Initialize multicore heartbeat system
 * - Core 0: GPIO 25 (onboard LED) @ 250ms
 * - Core 1: GPIO 16 (external LED) @ 500ms
 */
void pico_gpio_heartbeat_init(void);

/**
 * @brief Update core 0 heartbeat (call from main loop)
 */
void pico_gpio_heartbeat_update(void);

/**
 * @brief Check if core 1 is running
 * @return true if core 1 is alive
 */
bool pico_gpio_core1_alive(void);

// ============================================================================
// FIFO-based Heartbeat Functions (Advanced)
// ============================================================================

/**
 * @brief Initialize FIFO-based heartbeat with verification
 */
void pico_gpio_heartbeat_fifo_init(void);

/**
 * @brief Check core 1 heartbeat via FIFO (non-blocking)
 * @param count Pointer to store heartbeat count
 * @return true if heartbeat received
 */
bool pico_gpio_check_core1_heartbeat(uint32_t *count);

/**
 * @brief Reset core 1 (use if core 1 hangs)
 */
void pico_gpio_reset_core1(void);

// ============================================================================
// Pin Definitions
// ============================================================================

#define CORE0_LED_PIN 25  // Onboard LED (GP25)
#define CORE1_LED_PIN 16  // External LED (GP16) - connect with 220Ω resistor

#ifdef __cplusplus
}
#endif

#endif // PICO_GPIO_H