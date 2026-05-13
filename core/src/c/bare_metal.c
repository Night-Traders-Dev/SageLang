/*
 * bare_metal.c — Freestanding C runtime for bare-metal Sage kernels
 *
 * This file replaces libc when compiling with --compile-bare.
 * It provides essential memory/string functions, x86 I/O port access,
 * CPU control primitives, and a minimal _start entry point that calls kmain().
 *
 * Compile with: -ffreestanding -nostdlib -DSAGE_BARE_METAL
 */

#ifdef SAGE_BARE_METAL

#ifndef BARE_METAL_H
#define BARE_METAL_H

/* Prevent compiler from optimizing away bare-metal primitives */
#define BM_USED __attribute__((used))
#define BM_NORETURN __attribute__((noreturn))

/* Forward declaration: user provides kmain() */
extern void kmain(void);

/*==========================================================================
 * Memory functions
 *==========================================================================*/

BM_USED
void *memset(void *s, int c, unsigned long n) {
    unsigned char *p = (unsigned char *)s;
    unsigned long i;
    for (i = 0; i < n; i++) {
        p[i] = (unsigned char)c;
    }
    return s;
}

BM_USED
void *memcpy(void *dest, const void *src, unsigned long n) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *sr = (const unsigned char *)src;
    unsigned long i;
    for (i = 0; i < n; i++) {
        d[i] = sr[i];
    }
    return dest;
}

BM_USED
void *memmove(void *dest, const void *src, unsigned long n) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *sr = (const unsigned char *)src;
    if (d < sr) {
        unsigned long i;
        for (i = 0; i < n; i++) {
            d[i] = sr[i];
        }
    } else if (d > sr) {
        unsigned long i = n;
        while (i > 0) {
            i--;
            d[i] = sr[i];
        }
    }
    return dest;
}

BM_USED
int memcmp(const void *s1, const void *s2, unsigned long n) {
    const unsigned char *a = (const unsigned char *)s1;
    const unsigned char *b = (const unsigned char *)s2;
    unsigned long i;
    for (i = 0; i < n; i++) {
        if (a[i] != b[i]) {
            return (int)a[i] - (int)b[i];
        }
    }
    return 0;
}

/*==========================================================================
 * String functions
 *==========================================================================*/

BM_USED
unsigned long strlen(const char *s) {
    unsigned long n = 0;
    while (s[n]) {
        n++;
    }
    return n;
}

BM_USED
int strcmp(const char *s1, const char *s2) {
    while (*s1 && *s1 == *s2) {
        s1++;
        s2++;
    }
    return (int)(unsigned char)*s1 - (int)(unsigned char)*s2;
}

BM_USED
char *strcpy(char *dest, const char *src) {
    char *d = dest;
    while (*src) {
        *d++ = *src++;
    }
    *d = '\0';
    return dest;
}

/*==========================================================================
 * x86 I/O port access
 *==========================================================================*/

BM_USED
void outb(unsigned short port, unsigned char val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

BM_USED
unsigned char inb(unsigned short port) {
    unsigned char ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

BM_USED
void outw(unsigned short port, unsigned short val) {
    __asm__ volatile ("outw %0, %1" : : "a"(val), "Nd"(port));
}

BM_USED
unsigned short inw(unsigned short port) {
    unsigned short ret;
    __asm__ volatile ("inw %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

BM_USED
void outl(unsigned short port, unsigned int val) {
    __asm__ volatile ("outl %0, %1" : : "a"(val), "Nd"(port));
}

BM_USED
unsigned int inl(unsigned short port) {
    unsigned int ret;
    __asm__ volatile ("inl %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

/*==========================================================================
 * CPU control primitives
 *==========================================================================*/

BM_USED
void cli(void) {
    __asm__ volatile ("cli");
}

BM_USED
void sti(void) {
    __asm__ volatile ("sti");
}

BM_USED
void hlt(void) {
    __asm__ volatile ("hlt");
}

BM_USED
void io_wait(void) {
    /* Write to unused port 0x80 to introduce a small delay */
    __asm__ volatile ("outb %%al, $0x80" : : "a"(0));
}

/*==========================================================================
 * Model-Specific Registers (MSR)
 *==========================================================================*/

BM_USED
unsigned long long rdmsr(unsigned int msr) {
    unsigned int lo, hi;
    __asm__ volatile ("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return ((unsigned long long)hi << 32) | lo;
}

BM_USED
void wrmsr(unsigned int msr, unsigned long long val) {
    unsigned int lo = (unsigned int)(val & 0xFFFFFFFF);
    unsigned int hi = (unsigned int)(val >> 32);
    __asm__ volatile ("wrmsr" : : "a"(lo), "d"(hi), "c"(msr));
}

/*==========================================================================
 * Paging / TLB
 *==========================================================================*/

BM_USED
void invlpg(void *addr) {
    __asm__ volatile ("invlpg (%0)" : : "r"(addr) : "memory");
}

BM_USED
unsigned long long read_cr3(void) {
    unsigned long long val;
    __asm__ volatile ("mov %%cr3, %0" : "=r"(val));
    return val;
}

BM_USED
void write_cr3(unsigned long long val) {
    __asm__ volatile ("mov %0, %%cr3" : : "r"(val) : "memory");
}

/*==========================================================================
 * Entry point
 *==========================================================================*/

BM_USED BM_NORETURN
void _start(void) {
    /* Clear BSS would go here if linker script defines __bss_start/__bss_end */
    kmain();
    /* If kmain returns, halt the CPU in a loop */
    for (;;) {
        __asm__ volatile ("cli; hlt");
    }
}

#endif /* BARE_METAL_H */
#endif /* SAGE_BARE_METAL */
