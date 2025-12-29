// src/heartbeat.c
// Cross-platform heartbeat implementation
// Pico: Uses GPIO and multicore
// Linux: Uses pthread and console output

#ifdef PICO_BUILD
// ============================================================================
// Raspberry Pi Pico Implementation
// ============================================================================
#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/gpio.h"
#include "hardware/sync.h"
#include <stdio.h>

#define CORE0_LED_PIN 25  // Onboard LED
#define CORE1_LED_PIN 16  // External LED

volatile bool core1_running = false;

// Core 1 entry point - heartbeat on GPIO 16
void core1_entry() {
    gpio_init(CORE1_LED_PIN);
    gpio_set_dir(CORE1_LED_PIN, GPIO_OUT);
    core1_running = true;

    while (true) {
        gpio_put(CORE1_LED_PIN, 1);
        sleep_ms(250);
        gpio_put(CORE1_LED_PIN, 0);
        sleep_ms(250);
    }
}

// Initialize heartbeat system
void heartbeat_init(void) {
    // Initialize core 0 LED
    gpio_init(CORE0_LED_PIN);
    gpio_set_dir(CORE0_LED_PIN, GPIO_OUT);

    // Launch core 1 with heartbeat
    multicore_launch_core1(core1_entry);

    // Wait for core 1 to initialize
    while (!core1_running) {
        tight_loop_contents();
    }

    printf("Heartbeat initialized: Core 0 (GPIO %d), Core 1 (GPIO %d)\n", 
           CORE0_LED_PIN, CORE1_LED_PIN);
}

// Update core 0 heartbeat (call from main loop)
void heartbeat_update(void) {
    static bool led_state = false;
    static absolute_time_t last_toggle = {0};

    absolute_time_t now = get_absolute_time();
    int64_t elapsed = absolute_time_diff_us(last_toggle, now);

    // Toggle every 500ms
    if (elapsed >= 500000) {
        led_state = !led_state;
        gpio_put(CORE0_LED_PIN, led_state);
        last_toggle = now;
    }
}

// Check if core 1 is alive
bool heartbeat_core1_alive(void) {
    return core1_running;
}

#else
// ============================================================================
// Linux/Desktop Implementation
// ============================================================================
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <time.h>
#include <pthread.h>
#include <unistd.h>

static volatile bool thread_running = false;
static volatile bool should_exit = false;
static pthread_t heartbeat_thread;

// Thread function for background heartbeat
static void* heartbeat_thread_func(void* arg) {
    (void)arg;  // Unused parameter

    thread_running = true;
    int count = 0;

    while (!should_exit) {
        printf("💓 Thread heartbeat: %d\n", count++);
        usleep(1000000);  // 1 second
    }

    thread_running = false;
    return NULL;
}

// Initialize heartbeat system (desktop)
void heartbeat_init(void) {
    printf("Initializing desktop heartbeat system...\n");

    // Create background thread
    if (pthread_create(&heartbeat_thread, NULL, heartbeat_thread_func, NULL) != 0) {
        fprintf(stderr, "Error: Failed to create heartbeat thread\n");
        return;
    }

    // Wait for thread to start
    while (!thread_running) {
        usleep(1000);
    }

    printf("✅ Heartbeat system initialized (thread-based)\n");
}

// Update heartbeat (desktop version - just prints occasionally)
void heartbeat_update(void) {
    static int call_count = 0;
    static time_t last_print = 0;

    call_count++;
    time_t now = time(NULL);

    // Print status every 5 seconds
    if (now - last_print >= 5) {
        printf("💙 Main loop heartbeat: %d calls\n", call_count);
        last_print = now;
        call_count = 0;
    }
}

// Check if background thread is alive
bool heartbeat_core1_alive(void) {
    return thread_running;
}

// Cleanup (call before exit)
void heartbeat_cleanup(void) {
    if (thread_running) {
        printf("Stopping heartbeat thread...\n");
        should_exit = true;
        pthread_join(heartbeat_thread, NULL);
        printf("✅ Heartbeat thread stopped\n");
    }
}

#endif

// ============================================================================
// Common API (works on both platforms)
// ============================================================================

// Get heartbeat statistics
void heartbeat_stats(void) {
    #ifdef PICO_BUILD
    printf("Platform: Raspberry Pi Pico (RP2040)\n");
    printf("Core 0 LED: GPIO %d\n", CORE0_LED_PIN);
    printf("Core 1 LED: GPIO %d\n", CORE1_LED_PIN);
    printf("Core 1 Status: %s\n", core1_running ? "Running" : "Stopped");
    #else
    printf("Platform: Linux/Desktop\n");
    printf("Thread Status: %s\n", thread_running ? "Running" : "Stopped");
    #endif
}

// Example usage (for testing)
#ifdef HEARTBEAT_TEST_MAIN
int main(void) {
    #ifdef PICO_BUILD
    stdio_init_all();
    #endif

    printf("=== Heartbeat Test ===\n");
    heartbeat_init();

    // Main loop
    for (int i = 0; i < 100; i++) {
        heartbeat_update();

        #ifdef PICO_BUILD
        sleep_ms(100);
        #else
        usleep(100000);  // 100ms
        #endif

        // Print status every 10 iterations
        if (i % 10 == 0) {
            heartbeat_stats();
        }
    }

    #ifndef PICO_BUILD
    heartbeat_cleanup();
    #endif

    printf("=== Test Complete ===\n");
    return 0;
}
#endif