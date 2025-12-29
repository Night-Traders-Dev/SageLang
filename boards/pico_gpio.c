
// boards/pico_gpio.c

// Basic GPIO Hardware Bindings for Pico RP2040
// Thread-safe GPIO operations for multicore support

#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/gpio.h"
#include "hardware/sync.h"

// Initialize a specific GPIO pin
void pico_gpio_init(uint pin, bool out) {
    gpio_init(pin);
    if (out) {
        gpio_set_dir(pin, GPIO_OUT);
    } else {
        gpio_set_dir(pin, GPIO_IN);
    }
}

// Set pin output value
void pico_gpio_write(uint pin, bool value) {
    gpio_put(pin, value);
}

// Read pin input value
bool pico_gpio_read(uint pin) {
    return gpio_get(pin);
}

// Toggle an output pin (thread-safe)
void pico_gpio_toggle(uint pin) {
    // gpio_xor_mask is safe within same core with interrupts
    // For multicore safety, use atomic operation
    uint32_t save = save_and_disable_interrupts();
    gpio_xor_mask(1u << pin);
    restore_interrupts(save);
}

// Set pin pull up/down
void pico_gpio_pull(uint pin, bool up) {
    if (up) {
        gpio_pull_up(pin);
    } else {
        gpio_pull_down(pin);
    }
}

// Heartbeat LED function for core monitoring
// Use different pins for each core to visualize activity
#define CORE0_LED_PIN 25  // Onboard LED
#define CORE1_LED_PIN 16  // External LED (optional)

volatile bool core1_running = false;

// Core 1 entry point - heartbeat on GPIO 16
void core1_entry() {
    // Initialize core 1 LED
    pico_gpio_init(CORE1_LED_PIN, true);
    core1_running = true;

    while (true) {
        pico_gpio_toggle(CORE1_LED_PIN);
        sleep_ms(500);  // 0.5 second heartbeat
    }
}

// Core 0 heartbeat function
void core0_heartbeat() {
    static bool led_state = false;
    static absolute_time_t last_toggle = {0};

    absolute_time_t now = get_absolute_time();
    int64_t elapsed = absolute_time_diff_us(last_toggle, now);

    // Toggle every 250ms (faster than core 1)
    if (elapsed >= 250000) {
        led_state = !led_state;
        pico_gpio_write(CORE0_LED_PIN, led_state);
        last_toggle = now;
    }
}

// Initialize multicore heartbeat system
void pico_gpio_heartbeat_init() {
    // Initialize core 0 LED
    pico_gpio_init(CORE0_LED_PIN, true);

    // Launch core 1 with heartbeat
    multicore_launch_core1(core1_entry);

    // Wait for core 1 to initialize
    while (!core1_running) {
        tight_loop_contents();
    }
}

// Call this periodically from core 0 main loop
void pico_gpio_heartbeat_update() {
    core0_heartbeat();
}

// Status check function
bool pico_gpio_core1_alive() {
    return core1_running;
}

// Alternative: Heartbeat with FIFO communication
// This allows core 0 to verify core 1 is actually responding
#define HEARTBEAT_MAGIC 0xBEEF

volatile uint32_t core1_heartbeat_count = 0;

void core1_entry_with_fifo() {
    pico_gpio_init(CORE1_LED_PIN, true);
    core1_running = true;

    while (true) {
        // Toggle LED
        pico_gpio_toggle(CORE1_LED_PIN);

        // Increment heartbeat counter
        core1_heartbeat_count++;

        // Send heartbeat to core 0 via FIFO
        multicore_fifo_push_blocking(HEARTBEAT_MAGIC);
        multicore_fifo_push_blocking(core1_heartbeat_count);

        sleep_ms(500);
    }
}

// Initialize FIFO-based heartbeat
void pico_gpio_heartbeat_fifo_init() {
    pico_gpio_init(CORE0_LED_PIN, true);

    // Clear any stale FIFO data
    multicore_fifo_drain();

    // Launch core 1 with FIFO heartbeat
    multicore_launch_core1(core1_entry_with_fifo);
}

// Check core 1 heartbeat via FIFO (non-blocking)
bool pico_gpio_check_core1_heartbeat(uint32_t *count) {
    if (multicore_fifo_rvalid()) {
        uint32_t magic = multicore_fifo_pop_blocking();
        if (magic == HEARTBEAT_MAGIC) {
            *count = multicore_fifo_pop_blocking();
            return true;
        }
    }
    return false;
}

// Debug: Reset core 1 if it hangs
void pico_gpio_reset_core1() {
    multicore_reset_core1();
    core1_running = false;
    sleep_ms(100);
}