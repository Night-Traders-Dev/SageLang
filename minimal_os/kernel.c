#include <stdint.h>

void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

void serial_init() {
    outb(0x3F9, 0x00);
    outb(0x3FB, 0x80);
    outb(0x3F8, 0x01);
    outb(0x3F9, 0x00);
    outb(0x3FB, 0x03);
    outb(0x3FC, 0x03);
}

void serial_putchar(char c) {
    while ((inb(0x3FD) & 0x20) == 0);
    outb(0x3F8, c);
}

void serial_print(const char* s) {
    while (*s) {
        serial_putchar(*s++);
    }
}

void kmain() {
    serial_init();
    serial_print("SageLang Minimal OS Kernel Loaded (C-Gen)\n");
    while (1) {
        __asm__ volatile ("cli; hlt");
    }
}
