// boards/pico_gpio.c
// Basic GPIO Hardware Bindings for Pico RP2040
#include "pico/stdlib.h"
#include "hardware/gpio.h"

// Initialize a specific GPIO pin
void pico_gpio_init(uint pin, bool out) {
    gpio_init(pin);
    if(out) {
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

// Toggle an output pin
void pico_gpio_toggle(uint pin) {
    gpio_xor_mask(1u << pin);
}

// Set pin pull up/down
void pico_gpio_pull(uint pin, bool up) {
    if(up) gpio_pull_up(pin);
    else gpio_pull_down(pin);
}
