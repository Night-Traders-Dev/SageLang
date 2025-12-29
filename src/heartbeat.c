// Example: Multicore heartbeat monitoring on Raspberry Pi Pico

#include "pico/stdlib.h"
#include "boards/pico_gpio.h"
#include <stdio.h>

// ============================================================================
// Example 1: Simple Heartbeat (Core 0 and Core 1 blink independently)
// ============================================================================

void example_simple_heartbeat() {
    stdio_init_all();

    printf("Starting simple heartbeat...\n");
    printf("Core 0: GPIO 25 (onboard LED) - 250ms\n");
    printf("Core 1: GPIO 16 (external LED) - 500ms\n");

    // Initialize multicore heartbeat
    pico_gpio_heartbeat_init();

    // Main loop - core 0 continues executing
    while (true) {
        // Update core 0 heartbeat
        pico_gpio_heartbeat_update();

        // Check if core 1 is still alive
        if (!pico_gpio_core1_alive()) {
            printf("WARNING: Core 1 not responding!\n");
        }

        // Your main application code here
        sleep_ms(10);
    }
}

// ============================================================================
// Example 2: FIFO Heartbeat with Verification
// ============================================================================

void example_fifo_heartbeat() {
    stdio_init_all();

    printf("Starting FIFO heartbeat with verification...\n");

    // Initialize FIFO-based heartbeat
    pico_gpio_heartbeat_fifo_init();

    uint32_t last_count = 0;
    uint32_t missed_heartbeats = 0;

    while (true) {
        // Update core 0 LED
        pico_gpio_heartbeat_update();

        // Check for core 1 heartbeat
        uint32_t count = 0;
        if (pico_gpio_check_core1_heartbeat(&count)) {
            if (count == last_count + 1) {
                printf("Core 1 heartbeat: %lu (OK)\n", count);
                missed_heartbeats = 0;
            } else {
                printf("Core 1 heartbeat: %lu (SKIPPED %lu)\n", 
                       count, count - last_count - 1);
            }
            last_count = count;
        } else {
            missed_heartbeats++;
            if (missed_heartbeats > 10) {
                printf("ERROR: Core 1 hung! Resetting...\n");
                pico_gpio_reset_core1();
                sleep_ms(100);
                pico_gpio_heartbeat_fifo_init();
                missed_heartbeats = 0;
                last_count = 0;
            }
        }

        sleep_ms(100);
    }
}

// ============================================================================
// Example 3: Custom GPIO Operations
// ============================================================================

void example_custom_gpio() {
    stdio_init_all();

    // Initialize GPIO pins
    const uint BUTTON_PIN = 14;
    const uint LED_PIN = 15;

    pico_gpio_init(BUTTON_PIN, false);  // Input
    pico_gpio_pull(BUTTON_PIN, true);   // Pull-up resistor

    pico_gpio_init(LED_PIN, true);      // Output

    printf("Press button on GPIO 14 to toggle LED on GPIO 15\n");

    while (true) {
        // Read button state (active LOW with pull-up)
        bool button_pressed = !pico_gpio_read(BUTTON_PIN);

        if (button_pressed) {
            pico_gpio_toggle(LED_PIN);
            printf("Button pressed! LED toggled\n");

            // Debounce delay
            sleep_ms(200);
        }

        sleep_ms(10);
    }
}