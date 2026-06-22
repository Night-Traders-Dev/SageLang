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

#define BARE_METAL_HEAP_SIZE (32 * 1024 * 1024) // 32MB static heap
static unsigned char bm_heap[BARE_METAL_HEAP_SIZE] __attribute__((aligned(16)));
static unsigned long bm_heap_used = 0;

typedef struct Block {
    unsigned long size;
    int is_free;
    struct Block* next;
} Block;

static Block* block_list_head = 0;

BM_USED
void* malloc(unsigned long size) {
    if (size == 0) return 0;
    // Align to 16 bytes
    unsigned long aligned_size = (size + 15) & ~15UL;
    
    // 1. Search free list
    Block* curr = block_list_head;
    Block* best_fit = 0;
    while (curr) {
        if (curr->is_free && curr->size >= aligned_size) {
            if (!best_fit || curr->size < best_fit->size) {
                best_fit = curr;
            }
        }
        curr = curr->next;
    }
    
    if (best_fit) {
        // If the block is significantly larger, split it
        if (best_fit->size >= aligned_size + sizeof(Block) + 16) {
            Block* new_block = (Block*)((unsigned char*)best_fit + sizeof(Block) + aligned_size);
            new_block->size = best_fit->size - aligned_size - sizeof(Block);
            new_block->is_free = 1;
            new_block->next = best_fit->next;
            
            best_fit->size = aligned_size;
            best_fit->next = new_block;
        }
        best_fit->is_free = 0;
        return (void*)((unsigned char*)best_fit + sizeof(Block));
    }
    
    // 2. Allocate new block at the end of the heap
    unsigned long required = sizeof(Block) + aligned_size;
    if (bm_heap_used + required > BARE_METAL_HEAP_SIZE) {
        return 0; // Out of memory
    }
    
    Block* new_block = (Block*)&bm_heap[bm_heap_used];
    new_block->size = aligned_size;
    new_block->is_free = 0;
    new_block->next = 0;
    
    bm_heap_used += required;
    
    // Append to list
    if (!block_list_head) {
        block_list_head = new_block;
    } else {
        Block* temp = block_list_head;
        while (temp->next) {
            temp = temp->next;
        }
        temp->next = new_block;
    }
    
    return (void*)((unsigned char*)new_block + sizeof(Block));
}

BM_USED
void free(void* ptr) {
    if (!ptr) return;
    Block* block = (Block*)((unsigned char*)ptr - sizeof(Block));
    block->is_free = 1;
    
    // Coalesce adjacent free blocks
    Block* curr = block_list_head;
    while (curr) {
        if (curr->is_free && curr->next && curr->next->is_free) {
            curr->size += sizeof(Block) + curr->next->size;
            curr->next = curr->next->next;
        } else {
            curr = curr->next;
        }
    }
}

BM_USED
void* calloc(unsigned long nmemb, unsigned long size) {
    unsigned long total = nmemb * size;
    void* ptr = malloc(total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

BM_USED
void* realloc(void* ptr, unsigned long size) {
    if (!ptr) return malloc(size);
    if (size == 0) {
        free(ptr);
        return 0;
    }
    Block* block = (Block*)((unsigned char*)ptr - sizeof(Block));
    if (block->size >= size) {
        return ptr; // Keep current block if it fits
    }
    void* new_ptr = malloc(size);
    if (new_ptr) {
        memcpy(new_ptr, ptr, block->size);
        free(ptr);
    }
    return new_ptr;
}

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

/* Ensure this translation unit is never empty (ISO C requirement) */
typedef int bare_metal_unit_not_empty;
