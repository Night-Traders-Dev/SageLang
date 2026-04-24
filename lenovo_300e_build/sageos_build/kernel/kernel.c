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

    uint64_t system_table;
    uint64_t boot_services;
    uint64_t runtime_services;
    uint64_t con_in;
    uint64_t con_out;
    uint32_t boot_services_active;
    uint32_t input_mode;
    uint64_t acpi_rsdp;
} SageOSBootInfo;

#if defined(__clang__) || defined(__GNUC__)
#define EFIAPI __attribute__((ms_abi))
#else
#define EFIAPI
#endif

typedef uint16_t CHAR16;
typedef uint64_t UINTN;
typedef uint64_t EFI_STATUS;

#define EFI_SUCCESS 0
#define EFI_ERROR_MASK 0x8000000000000000ULL
#define EFI_NOT_READY (EFI_ERROR_MASK | 6)

typedef struct {
    uint16_t ScanCode;
    CHAR16 UnicodeChar;
} EFI_INPUT_KEY;

typedef struct EFI_SIMPLE_TEXT_INPUT_PROTOCOL EFI_SIMPLE_TEXT_INPUT_PROTOCOL;

typedef EFI_STATUS (EFIAPI *EFI_INPUT_RESET)(
    EFI_SIMPLE_TEXT_INPUT_PROTOCOL *self,
    uint8_t extended_verification
);

typedef EFI_STATUS (EFIAPI *EFI_INPUT_READ_KEY)(
    EFI_SIMPLE_TEXT_INPUT_PROTOCOL *self,
    EFI_INPUT_KEY *key
);

struct EFI_SIMPLE_TEXT_INPUT_PROTOCOL {
    EFI_INPUT_RESET Reset;
    EFI_INPUT_READ_KEY ReadKeyStroke;
    void *WaitForKey;
};

typedef void (EFIAPI *EFI_RESET_SYSTEM)(
    uint32_t ResetType,
    EFI_STATUS ResetStatus,
    UINTN DataSize,
    CHAR16 *ResetData
);

typedef struct {
    char Hdr[24];

    void *GetTime;
    void *SetTime;
    void *GetWakeupTime;
    void *SetWakeupTime;
    void *SetVirtualAddressMap;
    void *ConvertPointer;
    void *GetVariable;
    void *GetNextVariableName;
    void *SetVariable;
    void *GetNextHighMonotonicCount;

    EFI_RESET_SYSTEM ResetSystem;
} EFI_RUNTIME_SERVICES;

#define EFI_RESET_COLD 0
#define EFI_RESET_WARM 1
#define EFI_RESET_SHUTDOWN 2
#define EFI_RESET_PLATFORM_SPECIFIC 3

typedef struct {
    const char *path;
    const char *content;
} RamFile;

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

static const RamFile ramfs[] = {
    {
        "/etc/motd",
        "Welcome to SageOS.\n"
        "This is the Lenovo 300e Chromebook UEFI framebuffer build.\n"
        "Type help to list commands.\n"
    },
    {
        "/etc/version",
        "SageOS 0.0.5\n"
        "x86_64 UEFI GOP framebuffer kernel\n"
    },
    {
        "/bin/sh",
        "Built-in SageOS shell.\n"
        "Current shell is kernel-resident and command based.\n"
    },
    {
        "/dev/fb0",
        "UEFI GOP framebuffer device.\n"
    },
};

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static inline void outw(uint16_t port, uint16_t val) {
    __asm__ volatile ("outw %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint16_t inw(uint16_t port) {
    uint16_t ret;
    __asm__ volatile ("inw %1, %0" : "=a"(ret) : "Nd"(port));
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

static const char *input_backend_name(void) {
    if (
        boot_info &&
        boot_info->boot_services_active &&
        boot_info->con_in != 0
    ) {
        return "uefi-firmware-conin-exclusive";
    }

    return "legacy-ps2-fallback";
}

static char uefi_getchar_poll(void) {
    if (
        !boot_info ||
        !boot_info->boot_services_active ||
        boot_info->con_in == 0
    ) {
        return 0;
    }

    EFI_SIMPLE_TEXT_INPUT_PROTOCOL *conin =
        (EFI_SIMPLE_TEXT_INPUT_PROTOCOL *)(uintptr_t)boot_info->con_in;

    if (!conin->ReadKeyStroke) {
        return 0;
    }

    EFI_INPUT_KEY key;
    EFI_STATUS status = conin->ReadKeyStroke(conin, &key);

    if (status != EFI_SUCCESS) {
        return 0;
    }

    if (key.UnicodeChar == 0) {
        return 0;
    }

    if (key.UnicodeChar == '\r') {
        return '\n';
    }

    if (key.UnicodeChar == 8 || key.UnicodeChar == 127) {
        return '\b';
    }

    if (key.UnicodeChar >= 32 && key.UnicodeChar <= 126) {
        return (char)key.UnicodeChar;
    }

    return 0;
}

static void firmware_shutdown(void) {
    if (!boot_info || boot_info->runtime_services == 0) {
        return;
    }

    EFI_RUNTIME_SERVICES *rt =
        (EFI_RUNTIME_SERVICES *)(uintptr_t)boot_info->runtime_services;

    if (!rt->ResetSystem) {
        return;
    }

    rt->ResetSystem(EFI_RESET_SHUTDOWN, EFI_SUCCESS, 0, 0);
}

static void firmware_reboot(void) {
    if (!boot_info || boot_info->runtime_services == 0) {
        return;
    }

    EFI_RUNTIME_SERVICES *rt =
        (EFI_RUNTIME_SERVICES *)(uintptr_t)boot_info->runtime_services;

    if (!rt->ResetSystem) {
        return;
    }

    rt->ResetSystem(EFI_RESET_COLD, EFI_SUCCESS, 0, 0);
}

static int str_eq(const char *a, const char *b) {
    while (*a && *b) {
        if (*a != *b) return 0;
        a++;
        b++;
    }

    return *a == 0 && *b == 0;
}

static int starts_word(const char *line, const char *word) {
    while (*word) {
        if (*line != *word) return 0;
        line++;
        word++;
    }

    return *line == 0 || *line == ' ' || *line == '\t';
}

static const char *skip_spaces(const char *s) {
    while (*s == ' ' || *s == '\t') {
        s++;
    }

    return s;
}

static const char *arg_after(const char *line, const char *cmd) {
    while (*cmd && *line == *cmd) {
        line++;
        cmd++;
    }

    return skip_spaces(line);
}

static void term_putc(char c);
static void term_write(const char *s);

static void term_write_hex64(uint64_t v) {
    static const char *hex = "0123456789ABCDEF";
    char out[19];

    out[0] = '0';
    out[1] = 'x';

    for (int i = 0; i < 16; i++) {
        out[2 + i] = hex[(v >> ((15 - i) * 4)) & 0xF];
    }

    out[18] = 0;
    term_write(out);
}

static void term_write_u32(uint32_t v) {
    char buf[16];
    int i = 0;

    if (v == 0) {
        term_putc('0');
        return;
    }

    while (v > 0 && i < 15) {
        buf[i++] = (char)('0' + (v % 10));
        v /= 10;
    }

    while (i > 0) {
        term_putc(buf[--i]);
    }
}

typedef struct {
    uint32_t pm1a_cnt;
    uint32_t pm1b_cnt;
    uint32_t smi_cmd;
    uint8_t acpi_enable;
    uint8_t acpi_disable;
    uint8_t s5_typa;
    uint8_t s5_typb;
    uint8_t s3_typa;
    uint8_t s3_typb;
    int has_s5;
    int has_s3;
    int ready;
} AcpiState;

static AcpiState acpi_state;

static uint8_t mem8(uint64_t addr) {
    return *(volatile uint8_t *)(uintptr_t)addr;
}

static uint16_t mem16(uint64_t addr) {
    return *(volatile uint16_t *)(uintptr_t)addr;
}

static uint32_t mem32(uint64_t addr) {
    return *(volatile uint32_t *)(uintptr_t)addr;
}

static uint64_t mem64(uint64_t addr) {
    return *(volatile uint64_t *)(uintptr_t)addr;
}

static int sig4(uint64_t addr, const char *sig) {
    return
        mem8(addr + 0) == (uint8_t)sig[0] &&
        mem8(addr + 1) == (uint8_t)sig[1] &&
        mem8(addr + 2) == (uint8_t)sig[2] &&
        mem8(addr + 3) == (uint8_t)sig[3];
}

static int acpi_checksum(uint64_t addr, uint32_t len) {
    uint8_t sum = 0;

    for (uint32_t i = 0; i < len; i++) {
        sum = (uint8_t)(sum + mem8(addr + i));
    }

    return sum == 0;
}

static int acpi_parse_pkg_int(uint64_t *p, uint8_t *out) {
    uint8_t op = mem8(*p);

    if (op == 0x0A) {
        *out = mem8(*p + 1);
        *p += 2;
        return 1;
    }

    if (op == 0x0B) {
        *out = (uint8_t)(mem16(*p + 1) & 0xFF);
        *p += 3;
        return 1;
    }

    if (op == 0x0C) {
        *out = (uint8_t)(mem32(*p + 1) & 0xFF);
        *p += 5;
        return 1;
    }

    if (op == 0x00 || op == 0x01) {
        *out = op;
        *p += 1;
        return 1;
    }

    return 0;
}

static int acpi_find_sleep_package(uint64_t dsdt, const char *name, uint8_t *typa, uint8_t *typb) {
    uint32_t len = mem32(dsdt + 4);

    if (len < 44) {
        return 0;
    }

    for (uint64_t i = dsdt + 36; i + 16 < dsdt + len; i++) {
        if (
            mem8(i + 0) == '_' &&
            mem8(i + 1) == (uint8_t)name[1] &&
            mem8(i + 2) == (uint8_t)name[2] &&
            mem8(i + 3) == '_'
        ) {
            uint64_t p = i + 4;

            if (mem8(p) == 0x12) {
                p++;

                uint8_t pkg_len_byte = mem8(p);
                uint8_t pkg_len_bytes = (uint8_t)((pkg_len_byte >> 6) + 1);
                p += pkg_len_bytes;

                /*
                 * NumElements.
                 */
                p++;

                if (!acpi_parse_pkg_int(&p, typa)) {
                    return 0;
                }

                if (!acpi_parse_pkg_int(&p, typb)) {
                    *typb = *typa;
                }

                return 1;
            }
        }
    }

    return 0;
}

static uint64_t acpi_find_table(const char *signature) {
    if (!boot_info || !boot_info->acpi_rsdp) {
        return 0;
    }

    uint64_t rsdp = boot_info->acpi_rsdp;

    if (
        mem8(rsdp + 0) != 'R' ||
        mem8(rsdp + 1) != 'S' ||
        mem8(rsdp + 2) != 'D' ||
        mem8(rsdp + 3) != ' ' ||
        mem8(rsdp + 4) != 'P' ||
        mem8(rsdp + 5) != 'T' ||
        mem8(rsdp + 6) != 'R' ||
        mem8(rsdp + 7) != ' '
    ) {
        return 0;
    }

    uint8_t revision = mem8(rsdp + 15);
    uint64_t root = 0;
    int xsdt = 0;

    if (revision >= 2) {
        root = mem64(rsdp + 24);
        xsdt = 1;
    }

    if (!root) {
        root = mem32(rsdp + 16);
        xsdt = 0;
    }

    if (!root) {
        return 0;
    }

    if (!acpi_checksum(root, mem32(root + 4))) {
        /*
         * Some firmware has odd checksum behavior during early boot.
         * Do not hard-fail; continue but prefer valid tables.
         */
    }

    uint32_t root_len = mem32(root + 4);
    uint32_t entry_size = xsdt ? 8 : 4;
    uint32_t entries = (root_len - 36) / entry_size;

    for (uint32_t i = 0; i < entries; i++) {
        uint64_t table = xsdt ? mem64(root + 36 + i * 8) : mem32(root + 36 + i * 4);

        if (!table) {
            continue;
        }

        if (sig4(table, signature)) {
            return table;
        }
    }

    return 0;
}

static int acpi_init(void) {
    if (acpi_state.ready) {
        return 1;
    }

    uint64_t fadt = acpi_find_table("FACP");

    if (!fadt) {
        return 0;
    }

    uint32_t fadt_len = mem32(fadt + 4);

    uint32_t dsdt32 = mem32(fadt + 40);
    uint64_t x_dsdt = 0;

    if (fadt_len >= 148) {
        x_dsdt = mem64(fadt + 140);
    }

    uint64_t dsdt = x_dsdt ? x_dsdt : dsdt32;

    acpi_state.smi_cmd = mem32(fadt + 48);
    acpi_state.acpi_enable = mem8(fadt + 52);
    acpi_state.acpi_disable = mem8(fadt + 53);
    acpi_state.pm1a_cnt = mem32(fadt + 64);
    acpi_state.pm1b_cnt = mem32(fadt + 68);

    if (!dsdt || !sig4(dsdt, "DSDT")) {
        return 0;
    }

    acpi_state.has_s5 = acpi_find_sleep_package(
        dsdt,
        "_S5_",
        &acpi_state.s5_typa,
        &acpi_state.s5_typb
    );

    acpi_state.has_s3 = acpi_find_sleep_package(
        dsdt,
        "_S3_",
        &acpi_state.s3_typa,
        &acpi_state.s3_typb
    );

    acpi_state.ready = 1;
    return 1;
}

static void acpi_enable_if_needed(void) {
    if (!acpi_state.pm1a_cnt) {
        return;
    }

    if (inw((uint16_t)acpi_state.pm1a_cnt) & 1) {
        return;
    }

    if (acpi_state.smi_cmd && acpi_state.acpi_enable) {
        outb((uint16_t)acpi_state.smi_cmd, acpi_state.acpi_enable);

        for (uint32_t i = 0; i < 1000000; i++) {
            if (inw((uint16_t)acpi_state.pm1a_cnt) & 1) {
                break;
            }

            __asm__ volatile ("pause");
        }
    }
}

static int acpi_enter_sleep(uint8_t typa, uint8_t typb) {
    if (!acpi_init()) {
        return 0;
    }

    if (!acpi_state.pm1a_cnt) {
        return 0;
    }

    acpi_enable_if_needed();

    uint16_t slp_en = (uint16_t)(1U << 13);
    uint16_t sci_en = 1;
    uint16_t val_a = (uint16_t)(((uint16_t)typa << 10) | slp_en | sci_en);
    uint16_t val_b = (uint16_t)(((uint16_t)typb << 10) | slp_en | sci_en);

    outw((uint16_t)acpi_state.pm1a_cnt, val_a);

    if (acpi_state.pm1b_cnt) {
        outw((uint16_t)acpi_state.pm1b_cnt, val_b);
    }

    for (uint32_t i = 0; i < 1000000; i++) {
        __asm__ volatile ("hlt");
    }

    return 1;
}

static int acpi_poweroff(void) {
    if (!acpi_init()) {
        return 0;
    }

    if (!acpi_state.has_s5) {
        return 0;
    }

    return acpi_enter_sleep(acpi_state.s5_typa, acpi_state.s5_typb);
}

static int acpi_suspend(void) {
    if (!acpi_init()) {
        return 0;
    }

    if (!acpi_state.has_s3) {
        return 0;
    }

    return acpi_enter_sleep(acpi_state.s3_typa, acpi_state.s3_typb);
}


static uint32_t fb_pack(uint32_t rgb) {
    uint8_t r = (rgb >> 16) & 0xFF;
    uint8_t g = (rgb >> 8) & 0xFF;
    uint8_t b = rgb & 0xFF;

    if (!boot_info) {
        return rgb;
    }

    /*
     * GOP pixel formats:
     * 0 = RGB reserved
     * 1 = BGR reserved
     * 2 = bitmask, usually still BGR on common firmware
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

        case 'a': { static const uint8_t g[7]={0,0,14,1,15,17,15}; return g; }
        case 'b': { static const uint8_t g[7]={16,16,22,25,17,17,30}; return g; }
        case 'c': { static const uint8_t g[7]={0,0,14,16,16,17,14}; return g; }
        case 'd': { static const uint8_t g[7]={1,1,13,19,17,17,15}; return g; }
        case 'e': { static const uint8_t g[7]={0,0,14,17,31,16,14}; return g; }
        case 'f': { static const uint8_t g[7]={6,9,8,28,8,8,8}; return g; }
        case 'g': { static const uint8_t g[7]={0,0,15,17,15,1,14}; return g; }
        case 'h': { static const uint8_t g[7]={16,16,22,25,17,17,17}; return g; }
        case 'i': { static const uint8_t g[7]={4,0,12,4,4,4,14}; return g; }
        case 'j': { static const uint8_t g[7]={2,0,6,2,2,18,12}; return g; }
        case 'k': { static const uint8_t g[7]={16,16,18,20,24,20,18}; return g; }
        case 'l': { static const uint8_t g[7]={12,4,4,4,4,4,14}; return g; }
        case 'm': { static const uint8_t g[7]={0,0,26,21,21,21,21}; return g; }
        case 'n': { static const uint8_t g[7]={0,0,22,25,17,17,17}; return g; }
        case 'o': { static const uint8_t g[7]={0,0,14,17,17,17,14}; return g; }
        case 'p': { static const uint8_t g[7]={0,0,30,17,30,16,16}; return g; }
        case 'q': { static const uint8_t g[7]={0,0,13,19,15,1,1}; return g; }
        case 'r': { static const uint8_t g[7]={0,0,22,25,16,16,16}; return g; }
        case 's': { static const uint8_t g[7]={0,0,15,16,14,1,30}; return g; }
        case 't': { static const uint8_t g[7]={8,8,28,8,8,9,6}; return g; }
        case 'u': { static const uint8_t g[7]={0,0,17,17,17,19,13}; return g; }
        case 'v': { static const uint8_t g[7]={0,0,17,17,17,10,4}; return g; }
        case 'w': { static const uint8_t g[7]={0,0,17,17,21,21,10}; return g; }
        case 'x': { static const uint8_t g[7]={0,0,17,10,4,10,17}; return g; }
        case 'y': { static const uint8_t g[7]={0,0,17,17,15,1,14}; return g; }
        case 'z': { static const uint8_t g[7]={0,0,31,2,4,8,31}; return g; }

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

    for (uint32_t y = fb_char_h; y < h; y++) {
        for (uint32_t x = 0; x < w; x++) {
            fb[(uint64_t)(y - fb_char_h) * pitch + x] = fb[(uint64_t)y * pitch + x];
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
            if (have_fb) fb_scroll();
            else vga_scroll();
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
            if (have_fb) fb_scroll();
            else vga_scroll();
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

static void draw_status_bar(void) {
    if (!have_fb || !boot_info) {
        return;
    }

    uint32_t old_fg = fg_rgb;
    uint32_t old_bg = bg_rgb;

    fg_rgb = 0x05070A;
    bg_rgb = 0x79FFB0;

    uint32_t old_row = term_row;
    uint32_t old_col = term_col;

    term_row = 0;
    term_col = 0;

    for (uint32_t i = 0; i < term_cols; i++) {
        fb_draw_char_cell(i, 0, ' ');
    }

    term_write(" SAGEOS 0.0.5  LENOVO 300E  X86_64 UEFI GOP ");

    term_row = old_row;
    term_col = old_col;

    fg_rgb = old_fg;
    bg_rgb = old_bg;
}

static void banner(void) {
    uint32_t old = fg_rgb;

    fg_rgb = 0x79FFB0;
    term_write("  ____    _    ____ _____ ___  ____  \n");
    term_write(" / ___|  / \\  / ___| ____/ _ \\/ ___| \n");
    term_write(" \\___ \\ / _ \\| |  _|  _|| | | \\___ \\ \n");
    term_write("  ___) / ___ \\ |_| | |__| |_| |___) |\n");
    term_write(" |____/_/   \\_\\____|_____\\___/|____/ \n");
    fg_rgb = old;

    term_write("\n");
}

static void term_clear_screen(void) {
    term_row = 0;
    term_col = 0;

    if (have_fb) {
        fb_clear();
        draw_status_bar();
        term_row = 2;
        term_col = 0;
    } else {
        vga_clear();
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
    } else {
        term_cols = VGA_W;
        term_rows = VGA_H;
    }

    term_clear_screen();
}

static void reboot(void) {
    firmware_reboot();

    uint8_t good = 0x02;

    while (good & 0x02) {
        good = inb(0x64);
    }

    outb(0x64, 0xFE);
}

static int shutdown_machine(void) {
    if (acpi_poweroff()) {
        return 1;
    }

    /*
     * Firmware ResetSystem(EfiResetShutdown) hung on the Lenovo build.
     * Keep it out of the normal shutdown path for now.
     */
    return 0;
}

static int suspend_machine(void) {
    if (acpi_suspend()) {
        return 1;
    }

    return 0;
}

static void firmware_shutdown_try(void) {
    firmware_shutdown();
}

static char keymap[128] = {
    0,  27, '1','2','3','4','5','6','7','8','9','0','-','=', '\b',
    '\t','q','w','e','r','t','y','u','i','o','p','[',']','\n', 0,
    'a','s','d','f','g','h','j','k','l',';','\'','`', 0, '\\',
    'z','x','c','v','b','n','m',',','.','/', 0, '*', 0, ' ',
};

static int ps2_shift_down = 0;
static int ps2_caps_lock = 0;

static char ps2_shift_char(char c) {
    if (c >= 'a' && c <= 'z') {
        return (char)(c - 'a' + 'A');
    }

    switch (c) {
        case '1': return '!';
        case '2': return '@';
        case '3': return '#';
        case '4': return '$';
        case '5': return '%';
        case '6': return '^';
        case '7': return '&';
        case '8': return '*';
        case '9': return '(';
        case '0': return ')';
        case '-': return '_';
        case '=': return '+';
        case '[': return '{';
        case ']': return '}';
        case '\\': return '|';
        case ';': return ':';
        case '\'': return '"';
        case ',': return '<';
        case '.': return '>';
        case '/': return '?';
        case '`': return '~';
        default: return c;
    }
}

static char ps2_poll_char(void) {
    if (!(inb(0x64) & 1)) {
        return 0;
    }

    uint8_t sc = inb(0x60);

    if (sc == 0x2A || sc == 0x36) {
        ps2_shift_down = 1;
        return 0;
    }

    if (sc == 0xAA || sc == 0xB6) {
        ps2_shift_down = 0;
        return 0;
    }

    if (sc == 0x3A) {
        ps2_caps_lock = !ps2_caps_lock;
        return 0;
    }

    if (sc & 0x80) {
        return 0;
    }

    if (sc >= sizeof(keymap)) {
        return 0;
    }

    char c = keymap[sc];

    if (!c) {
        return 0;
    }

    if (c >= 'a' && c <= 'z') {
        if (ps2_shift_down ^ ps2_caps_lock) {
            c = (char)(c - 'a' + 'A');
        }

        return c;
    }

    if (ps2_shift_down) {
        return ps2_shift_char(c);
    }

    return c;
}

static char kbd_getchar(void) {
    if (
        boot_info &&
        boot_info->boot_services_active &&
        boot_info->con_in != 0
    ) {
        for (;;) {
            char c = uefi_getchar_poll();

            if (c) {
                return c;
            }

            __asm__ volatile ("pause");
        }
    }

    /*
     * PS/2 is fallback only. Mixing firmware input and PS/2 polling caused
     * duplicate modifier state and random upper/lowercase transitions on
     * real hardware.
     */
    for (;;) {
        char c = ps2_poll_char();

        if (c) {
            return c;
        }

        __asm__ volatile ("pause");
    }
}

static void shell_prompt(void) {
    uint32_t old = fg_rgb;
    fg_rgb = 0x80C8FF;
    term_write("\nroot@sageos:/# ");
    fg_rgb = old;
}

static const char *ramfs_find(const char *path) {
    for (size_t i = 0; i < sizeof(ramfs) / sizeof(ramfs[0]); i++) {
        if (str_eq(path, ramfs[i].path)) {
            return ramfs[i].content;
        }
    }

    return 0;
}

static void cmd_help(void) {
    term_write("\nCommands:");
    term_write("\n  help              show this help");
    term_write("\n  clear             clear framebuffer console");
    term_write("\n  version           show SageOS version");
    term_write("\n  uname             show kernel/system id");
    term_write("\n  about             show project summary");
    term_write("\n  mem               show memory/load info");
    term_write("\n  fb                show framebuffer info");
    term_write("\n  ls                list tiny RAMFS");
    term_write("\n  cat <path>        show RAMFS or proc file");
    term_write("\n  echo <text>       print text");
    term_write("\n  color <name>      white green amber blue red");
    term_write("\n  input             show active keyboard backend");
    term_write("\n  dmesg             show early kernel log");
    term_write("\n  shutdown          power off through ACPI S5");
    term_write("\n  poweroff          alias for shutdown");
    term_write("\n  suspend           experimental ACPI S3 suspend");
    term_write("\n  fwshutdown        try firmware shutdown directly");
    term_write("\n  halt              halt CPU");
    term_write("\n  reboot            reboot through firmware or keyboard controller");
}

static void cmd_ls(void) {
    term_write("\n/");
    term_write("\n/etc/motd");
    term_write("\n/etc/version");
    term_write("\n/bin/sh");
    term_write("\n/dev/fb0");
    term_write("\n/proc/fb");
    term_write("\n/proc/meminfo");
}

static void cmd_fb(void) {
    term_write("\nFramebuffer: ");

    if (!have_fb || !boot_info) {
        term_write("not available");
        return;
    }

    term_write("enabled");
    term_write("\n  base: ");
    term_write_hex64(boot_info->framebuffer_base);
    term_write("\n  size: ");
    term_write_hex64(boot_info->framebuffer_size);
    term_write("\n  resolution: ");
    term_write_u32(boot_info->width);
    term_write("x");
    term_write_u32(boot_info->height);
    term_write("\n  pixels_per_scanline: ");
    term_write_u32(boot_info->pixels_per_scanline);
    term_write("\n  pixel_format: ");
    term_write_u32(boot_info->pixel_format);
    term_write("\n  terminal: ");
    term_write_u32(term_cols);
    term_write("x");
    term_write_u32(term_rows);
}

static void cmd_mem(void) {
    term_write("\nKernel physical load: 0x00100000");
    term_write("\nKernel stack: 64 KiB");
    term_write("\nBoot info pointer: ");
    term_write_hex64((uint64_t)(uintptr_t)boot_info);

    if (boot_info) {
        term_write("\nFramebuffer memory: ");
        term_write_hex64(boot_info->framebuffer_base);
        term_write(" - ");
        term_write_hex64(boot_info->framebuffer_base + boot_info->framebuffer_size);
    }
}

static void cmd_dmesg(void) {
    term_write("\n[    0.000000] SageOS kernel entered");
    term_write("\n[    0.000001] serial console initialized");
    term_write("\n[    0.000002] boot info received from UEFI loader");
    term_write("\n[    0.000003] GOP framebuffer console initialized");
    term_write("\n[    0.000004] kernel-resident shell started");
    term_write("\n[    0.000005] input backend: ");
    term_write(input_backend_name());
    term_write("\n[    0.000006] firmware shutdown path: ");
    if (boot_info && boot_info->runtime_services) {
        term_write("available");
    } else {
        term_write("unavailable");
    }
    term_write("\n[    0.000007] ACPI RSDP: ");
    if (boot_info && boot_info->acpi_rsdp) {
        term_write_hex64(boot_info->acpi_rsdp);
    } else {
        term_write("unavailable");
    }
}

static void cmd_cat(const char *path) {
    if (!*path) {
        term_write("\nusage: cat <path>");
        return;
    }

    if (str_eq(path, "/proc/fb")) {
        cmd_fb();
        return;
    }

    if (str_eq(path, "/proc/meminfo")) {
        cmd_mem();
        return;
    }

    const char *content = ramfs_find(path);

    if (!content) {
        term_write("\ncat: no such file: ");
        term_write(path);
        return;
    }

    term_write("\n");
    term_write(content);
}

static void cmd_color(const char *name) {
    if (str_eq(name, "green")) {
        fg_rgb = 0x79FFB0;
        term_write("\ncolor set to green");
        return;
    }

    if (str_eq(name, "white")) {
        fg_rgb = 0xE8E8E8;
        term_write("\ncolor set to white");
        return;
    }

    if (str_eq(name, "amber")) {
        fg_rgb = 0xFFBF40;
        term_write("\ncolor set to amber");
        return;
    }

    if (str_eq(name, "blue")) {
        fg_rgb = 0x80C8FF;
        term_write("\ncolor set to blue");
        return;
    }

    if (str_eq(name, "red")) {
        fg_rgb = 0xFF7070;
        term_write("\ncolor set to red");
        return;
    }

    term_write("\nusage: color <white|green|amber|blue|red>");
}

static void shell_exec(const char *cmd) {
    cmd = skip_spaces(cmd);

    if (str_eq(cmd, "")) {
        return;
    }

    if (starts_word(cmd, "help")) {
        cmd_help();
        return;
    }

    if (starts_word(cmd, "clear")) {
        term_clear_screen();
        banner();
        return;
    }

    if (starts_word(cmd, "version")) {
        term_write("\nSageOS kernel 0.0.5 x86_64");
        term_write("\nUEFI GOP framebuffer console");
        return;
    }

    if (starts_word(cmd, "uname")) {
        term_write("\nSageOS sageos 0.0.5 x86_64 lenovo_300e");
        return;
    }

    if (starts_word(cmd, "about")) {
        term_write("\nSageOS is a small POSIX-inspired educational OS target.");
        term_write("\nCurrent milestone: UEFI boot, GOP framebuffer, kernel shell.");
        term_write("\nTarget hardware: Lenovo 300e Chromebook 2nd Gen AST.");
        return;
    }

    if (starts_word(cmd, "mem")) {
        cmd_mem();
        return;
    }

    if (starts_word(cmd, "fb")) {
        cmd_fb();
        return;
    }

    if (starts_word(cmd, "ls")) {
        cmd_ls();
        return;
    }

    if (starts_word(cmd, "cat")) {
        cmd_cat(arg_after(cmd, "cat"));
        return;
    }

    if (starts_word(cmd, "echo")) {
        term_write("\n");
        term_write(arg_after(cmd, "echo"));
        return;
    }

    if (starts_word(cmd, "color")) {
        cmd_color(arg_after(cmd, "color"));
        return;
    }

    if (starts_word(cmd, "input")) {
        term_write("\nInput backend: ");
        term_write(input_backend_name());
        term_write("\nFirmware ConIn: ");
        if (boot_info && boot_info->con_in) {
            term_write("available");
        } else {
            term_write("unavailable");
        }
        term_write("\nPS/2 fallback: available when firmware input is unavailable");
        return;
    }

    if (starts_word(cmd, "dmesg")) {
        cmd_dmesg();
        return;
    }

    if (starts_word(cmd, "shutdown") || starts_word(cmd, "poweroff")) {
        term_write("\nRequesting ACPI S5 poweroff...");
        if (!shutdown_machine()) {
            term_write("\nACPI poweroff failed or unsupported.");
            term_write("\nSystem is still running.");
        }
        return;
    }

    if (starts_word(cmd, "fwshutdown")) {
        term_write("\nTrying firmware ResetSystem shutdown directly...");
        firmware_shutdown_try();
        term_write("\nFirmware shutdown returned.");
        return;
    }

    if (starts_word(cmd, "suspend")) {
        term_write("\nRequesting ACPI S3 suspend...");
        if (!suspend_machine()) {
            term_write("\nACPI S3 suspend failed or unsupported.");
            term_write("\nLid-close wake requires ACPI GPE/EC support next.");
        }
        return;
    }

    if (starts_word(cmd, "halt")) {
        term_write("\nHalting.");
        for (;;) {
            __asm__ volatile ("hlt");
        }
    }

    if (starts_word(cmd, "reboot")) {
        term_write("\nRebooting.");
        reboot();
        return;
    }

    term_write("\nUnknown command: ");
    term_write(cmd);
}

static void shell_run(void) {
    char line[160];
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

    banner();

    term_write("SageOS kernel entered.\n");
    term_write("Framebuffer console online.\n");
    term_write("Tiny RAMFS mounted.\n");
    term_write("Input backend: ");
    term_write(input_backend_name());
    term_write("\n");
    term_write("Type help to list commands.\n");

    shell_run();
}
