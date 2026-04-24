#include <stdint.h>
#include <stddef.h>

#define SAGEOS_BOOT_MAGIC 0x534147454F534249ULL

#define VGA_W 80
#define VGA_H 25
#define VGA_MEM ((volatile uint16_t*)0xB8000)

#define COM1 0x3F8

typedef struct {
    uint64_t magic;
    uint64_t framebuffer_base;
    uint64_t framebuffer_size;
    uint32_t width;
    uint32_t height;
    uint32_t pixels_per_scanline;
    uint32_t pixel_format;
    uint32_t reserved;
} SageOSBootInfo;

static SageOSBootInfo *boot_info = 0;

static uint32_t term_row = 0;
static uint32_t term_col = 0;
static uint32_t term_cols = VGA_W;
static uint32_t term_rows = VGA_H;

static uint32_t fb_char_w = 12;
static uint32_t fb_char_h = 16;
static uint32_t fb_scale = 2;

static uint32_t fg_rgb = 0xE8E8E8;
static uint32_t bg_rgb = 0x05070A;
static int have_fb = 0;

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static void serial_init(void) {
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x80);
    outb(COM1 + 0, 0x03);
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);
    outb(COM1 + 2, 0xC7);
    outb(COM1 + 4, 0x0B);
}

static int serial_ready(void) {
    return inb(COM1 + 5) & 0x20;
}

static void serial_putc(char c) {
    while (!serial_ready()) {}
    outb(COM1, (uint8_t)c);
}

static uint32_t fb_pack(uint32_t rgb) {
    uint8_t r = (rgb >> 16) & 0xFF;
    uint8_t g = (rgb >> 8) & 0xFF;
    uint8_t b = rgb & 0xFF;

    if (!boot_info) {
        return rgb;
    }

    /*
     * UEFI GOP pixel formats:
     * 0 = PixelRedGreenBlueReserved8BitPerColor
     * 1 = PixelBlueGreenRedReserved8BitPerColor
     */
    if (boot_info->pixel_format == 0) {
        return ((uint32_t)r) | ((uint32_t)g << 8) | ((uint32_t)b << 16);
    }

    return ((uint32_t)b) | ((uint32_t)g << 8) | ((uint32_t)r << 16);
}

static void fb_putpixel(uint32_t x, uint32_t y, uint32_t rgb) {
    if (!have_fb || !boot_info) {
        return;
    }

    if (x >= boot_info->width || y >= boot_info->height) {
        return;
    }

    volatile uint32_t *fb = (volatile uint32_t *)(uintptr_t)boot_info->framebuffer_base;
    fb[(uint64_t)y * boot_info->pixels_per_scanline + x] = fb_pack(rgb);
}

static void fb_fill_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t rgb) {
    for (uint32_t yy = 0; yy < h; yy++) {
        for (uint32_t xx = 0; xx < w; xx++) {
            fb_putpixel(x + xx, y + yy, rgb);
        }
    }
}

static void fb_clear(void) {
    if (!have_fb || !boot_info) {
        return;
    }

    fb_fill_rect(0, 0, boot_info->width, boot_info->height, bg_rgb);
}

static const uint8_t *glyph_for(char ch) {
    static const uint8_t SPACE[7] = {0,0,0,0,0,0,0};
    static const uint8_t UNKNOWN[7] = {14,17,1,2,4,0,4};

    if (ch >= 'a' && ch <= 'z') {
        ch = (char)(ch - 'a' + 'A');
    }

    switch (ch) {
        case ' ': return SPACE;
        case 'A': { static const uint8_t g[7]={14,17,17,31,17,17,17}; return g; }
        case 'B': { static const uint8_t g[7]={30,17,17,30,17,17,30}; return g; }
        case 'C': { static const uint8_t g[7]={14,17,16,16,16,17,14}; return g; }
        case 'D': { static const uint8_t g[7]={30,17,17,17,17,17,30}; return g; }
        case 'E': { static const uint8_t g[7]={31,16,16,30,16,16,31}; return g; }
        case 'F': { static const uint8_t g[7]={31,16,16,30,16,16,16}; return g; }
        case 'G': { static const uint8_t g[7]={14,17,16,23,17,17,15}; return g; }
        case 'H': { static const uint8_t g[7]={17,17,17,31,17,17,17}; return g; }
        case 'I': { static const uint8_t g[7]={14,4,4,4,4,4,14}; return g; }
        case 'J': { static const uint8_t g[7]={7,2,2,2,18,18,12}; return g; }
        case 'K': { static const uint8_t g[7]={17,18,20,24,20,18,17}; return g; }
        case 'L': { static const uint8_t g[7]={16,16,16,16,16,16,31}; return g; }
        case 'M': { static const uint8_t g[7]={17,27,21,21,17,17,17}; return g; }
        case 'N': { static const uint8_t g[7]={17,25,21,19,17,17,17}; return g; }
        case 'O': { static const uint8_t g[7]={14,17,17,17,17,17,14}; return g; }
        case 'P': { static const uint8_t g[7]={30,17,17,30,16,16,16}; return g; }
        case 'Q': { static const uint8_t g[7]={14,17,17,17,21,18,13}; return g; }
        case 'R': { static const uint8_t g[7]={30,17,17,30,20,18,17}; return g; }
        case 'S': { static const uint8_t g[7]={15,16,16,14,1,1,30}; return g; }
        case 'T': { static const uint8_t g[7]={31,4,4,4,4,4,4}; return g; }
        case 'U': { static const uint8_t g[7]={17,17,17,17,17,17,14}; return g; }
        case 'V': { static const uint8_t g[7]={17,17,17,17,17,10,4}; return g; }
        case 'W': { static const uint8_t g[7]={17,17,17,21,21,21,10}; return g; }
        case 'X': { static const uint8_t g[7]={17,17,10,4,10,17,17}; return g; }
        case 'Y': { static const uint8_t g[7]={17,17,10,4,4,4,4}; return g; }
        case 'Z': { static const uint8_t g[7]={31,1,2,4,8,16,31}; return g; }

        case '0': { static const uint8_t g[7]={14,17,19,21,25,17,14}; return g; }
        case '1': { static const uint8_t g[7]={4,12,4,4,4,4,14}; return g; }
        case '2': { static const uint8_t g[7]={14,17,1,2,4,8,31}; return g; }
        case '3': { static const uint8_t g[7]={30,1,1,14,1,1,30}; return g; }
        case '4': { static const uint8_t g[7]={2,6,10,18,31,2,2}; return g; }
        case '5': { static const uint8_t g[7]={31,16,16,30,1,1,30}; return g; }
        case '6': { static const uint8_t g[7]={14,16,16,30,17,17,14}; return g; }
        case '7': { static const uint8_t g[7]={31,1,2,4,8,8,8}; return g; }
        case '8': { static const uint8_t g[7]={14,17,17,14,17,17,14}; return g; }
        case '9': { static const uint8_t g[7]={14,17,17,15,1,1,14}; return g; }

        case '.': { static const uint8_t g[7]={0,0,0,0,0,12,12}; return g; }
        case ',': { static const uint8_t g[7]={0,0,0,0,0,12,8}; return g; }
        case ':': { static const uint8_t g[7]={0,12,12,0,12,12,0}; return g; }
        case ';': { static const uint8_t g[7]={0,12,12,0,12,8,16}; return g; }
        case '-': { static const uint8_t g[7]={0,0,0,31,0,0,0}; return g; }
        case '_': { static const uint8_t g[7]={0,0,0,0,0,0,31}; return g; }
        case '/': { static const uint8_t g[7]={1,2,2,4,8,8,16}; return g; }
        case '\\': { static const uint8_t g[7]={16,8,8,4,2,2,1}; return g; }
        case '#': { static const uint8_t g[7]={10,10,31,10,31,10,10}; return g; }
        case '@': { static const uint8_t g[7]={14,17,23,21,23,16,14}; return g; }
        case '=': { static const uint8_t g[7]={0,0,31,0,31,0,0}; return g; }
        case '+': { static const uint8_t g[7]={0,4,4,31,4,4,0}; return g; }
        case '*': { static const uint8_t g[7]={0,21,14,31,14,21,0}; return g; }
        case '\'': { static const uint8_t g[7]={4,4,8,0,0,0,0}; return g; }
        case '"': { static const uint8_t g[7]={10,10,0,0,0,0,0}; return g; }
        case '!': { static const uint8_t g[7]={4,4,4,4,4,0,4}; return g; }
        case '?': return UNKNOWN;
        case '[': { static const uint8_t g[7]={14,8,8,8,8,8,14}; return g; }
        case ']': { static const uint8_t g[7]={14,2,2,2,2,2,14}; return g; }
        case '(': { static const uint8_t g[7]={2,4,8,8,8,4,2}; return g; }
        case ')': { static const uint8_t g[7]={8,4,2,2,2,4,8}; return g; }
        case '<': { static const uint8_t g[7]={2,4,8,16,8,4,2}; return g; }
        case '>': { static const uint8_t g[7]={8,4,2,1,2,4,8}; return g; }
        default: return UNKNOWN;
    }
}

static void fb_draw_char_cell(uint32_t cx, uint32_t cy, char ch) {
    uint32_t px = cx * fb_char_w;
    uint32_t py = cy * fb_char_h;

    fb_fill_rect(px, py, fb_char_w, fb_char_h, bg_rgb);

    const uint8_t *g = glyph_for(ch);

    for (uint32_t row = 0; row < 7; row++) {
        for (uint32_t col = 0; col < 5; col++) {
            if (g[row] & (1U << (4 - col))) {
                fb_fill_rect(
                    px + col * fb_scale + fb_scale,
                    py + row * fb_scale + fb_scale,
                    fb_scale,
                    fb_scale,
                    fg_rgb
                );
            }
        }
    }
}

static void fb_scroll(void) {
    if (!have_fb || !boot_info) {
        return;
    }

    volatile uint32_t *fb = (volatile uint32_t *)(uintptr_t)boot_info->framebuffer_base;
    uint32_t pitch = boot_info->pixels_per_scanline;
    uint32_t h = boot_info->height;
    uint32_t w = boot_info->width;
    uint32_t rows_to_move = h - fb_char_h;

    for (uint32_t y = 0; y < rows_to_move; y++) {
        for (uint32_t x = 0; x < w; x++) {
            fb[(uint64_t)y * pitch + x] = fb[(uint64_t)(y + fb_char_h) * pitch + x];
        }
    }

    for (uint32_t y = rows_to_move; y < h; y++) {
        for (uint32_t x = 0; x < w; x++) {
            fb[(uint64_t)y * pitch + x] = fb_pack(bg_rgb);
        }
    }

    if (term_row > 0) {
        term_row--;
    }
}

static void vga_clear(void) {
    for (size_t y = 0; y < VGA_H; y++) {
        for (size_t x = 0; x < VGA_W; x++) {
            VGA_MEM[y * VGA_W + x] = ((uint16_t)0x0F << 8) | ' ';
        }
    }

    term_row = 0;
    term_col = 0;
}

static void vga_scroll(void) {
    for (size_t y = 1; y < VGA_H; y++) {
        for (size_t x = 0; x < VGA_W; x++) {
            VGA_MEM[(y - 1) * VGA_W + x] = VGA_MEM[y * VGA_W + x];
        }
    }

    for (size_t x = 0; x < VGA_W; x++) {
        VGA_MEM[(VGA_H - 1) * VGA_W + x] = ((uint16_t)0x0F << 8) | ' ';
    }

    if (term_row > 0) {
        term_row--;
    }
}

static void term_screen_putc(char c) {
    if (c == '\r') {
        term_col = 0;
        return;
    }

    if (c == '\n') {
        term_col = 0;
        term_row++;

        if (term_row >= term_rows) {
            if (have_fb) {
                fb_scroll();
            } else {
                vga_scroll();
            }
        }

        return;
    }

    if (c == '\b') {
        if (term_col > 0) {
            term_col--;

            if (have_fb) {
                fb_draw_char_cell(term_col, term_row, ' ');
            } else {
                VGA_MEM[term_row * VGA_W + term_col] = ((uint16_t)0x0F << 8) | ' ';
            }
        }

        return;
    }

    if (have_fb) {
        fb_draw_char_cell(term_col, term_row, c);
    } else {
        VGA_MEM[term_row * VGA_W + term_col] = ((uint16_t)0x0F << 8) | (uint8_t)c;
    }

    term_col++;

    if (term_col >= term_cols) {
        term_col = 0;
        term_row++;

        if (term_row >= term_rows) {
            if (have_fb) {
                fb_scroll();
            } else {
                vga_scroll();
            }
        }
    }
}

static void term_putc(char c) {
    serial_putc(c);
    term_screen_putc(c);
}

static void term_write(const char *s) {
    while (*s) {
        term_putc(*s++);
    }
}

static void term_init(SageOSBootInfo *info) {
    boot_info = info;

    have_fb =
        info &&
        info->magic == SAGEOS_BOOT_MAGIC &&
        info->framebuffer_base != 0 &&
        info->width >= 320 &&
        info->height >= 200 &&
        info->pixels_per_scanline >= info->width;

    if (have_fb) {
        fb_scale = 2;
        fb_char_w = 6 * fb_scale;
        fb_char_h = 8 * fb_scale;

        term_cols = info->width / fb_char_w;
        term_rows = info->height / fb_char_h;

        if (term_cols == 0) term_cols = 1;
        if (term_rows == 0) term_rows = 1;

        term_row = 0;
        term_col = 0;

        fb_clear();

        fg_rgb = 0x79FFB0;
        term_write("SAGEOS FRAMEBUFFER CONSOLE ONLINE\n");
        fg_rgb = 0xE8E8E8;
        return;
    }

    term_cols = VGA_W;
    term_rows = VGA_H;
    vga_clear();
}

static int streq(const char *a, const char *b) {
    while (*a && *b) {
        if (*a != *b) {
            return 0;
        }

        a++;
        b++;
    }

    return *a == 0 && *b == 0;
}

static void reboot(void) {
    uint8_t good = 0x02;

    while (good & 0x02) {
        good = inb(0x64);
    }

    outb(0x64, 0xFE);
}

static char keymap[128] = {
    0,  27, '1','2','3','4','5','6','7','8','9','0','-','=', '\b',
    '\t','q','w','e','r','t','y','u','i','o','p','[',']','\n', 0,
    'a','s','d','f','g','h','j','k','l',';','\'','`', 0, '\\',
    'z','x','c','v','b','n','m',',','.','/', 0, '*', 0, ' ',
};

static char kbd_getchar(void) {
    for (;;) {
        if (inb(0x64) & 1) {
            uint8_t sc = inb(0x60);

            if (sc & 0x80) {
                continue;
            }

            if (sc < sizeof(keymap)) {
                char c = keymap[sc];

                if (c) {
                    return c;
                }
            }
        }
    }
}

static void shell_prompt(void) {
    fg_rgb = 0x80C8FF;
    term_write("\nroot@sageos:/# ");
    fg_rgb = 0xE8E8E8;
}

static void shell_exec(const char *cmd) {
    if (streq(cmd, "")) {
        return;
    }

    if (streq(cmd, "help")) {
        term_write("\nCommands:");
        term_write("\n  help      show this help");
        term_write("\n  clear     clear the terminal");
        term_write("\n  version   show kernel version");
        term_write("\n  mem       show framebuffer and static memory info");
        term_write("\n  halt      stop the CPU");
        term_write("\n  reboot    reboot through keyboard controller");
        return;
    }

    if (streq(cmd, "clear")) {
        if (have_fb) {
            fb_clear();
        } else {
            vga_clear();
        }

        return;
    }

    if (streq(cmd, "version")) {
        term_write("\nSageOS kernel 0.0.2 x86_64");
        term_write("\nUEFI GOP framebuffer console");
        return;
    }

    if (streq(cmd, "mem")) {
        term_write("\nKernel linked and loaded at physical 0x00100000");
        term_write("\nFramebuffer console: ");

        if (have_fb) {
            term_write("enabled");
        } else {
            term_write("disabled, using VGA fallback");
        }

        return;
    }

    if (streq(cmd, "halt")) {
        term_write("\nHalting.");
        for (;;) {
            __asm__ volatile ("hlt");
        }
    }

    if (streq(cmd, "reboot")) {
        term_write("\nRebooting.");
        reboot();
        return;
    }

    term_write("\nUnknown command: ");
    term_write(cmd);
}

static void shell_run(void) {
    char line[128];
    size_t len = 0;

    shell_prompt();

    for (;;) {
        char c = kbd_getchar();

        if (c == '\n') {
            line[len] = 0;
            shell_exec(line);
            len = 0;
            shell_prompt();
            continue;
        }

        if (c == '\b') {
            if (len > 0) {
                len--;
                term_putc('\b');
            }

            continue;
        }

        if (len + 1 < sizeof(line)) {
            line[len++] = c;
            term_putc(c);
        }
    }
}

void kmain(SageOSBootInfo *info) {
    serial_init();
    term_init(info);

    term_write("SageOS kernel entered.\n");
    term_write("Terminal shell online.\n");
    term_write("Type 'help'.\n");

    if (have_fb) {
        term_write("Framebuffer: active.\n");
    } else {
        term_write("Framebuffer: unavailable, VGA fallback active.\n");
    }

    shell_run();
}
