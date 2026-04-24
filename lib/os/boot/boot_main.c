#include <stdint.h>

/* UEFI Definitions */
typedef void* EFI_HANDLE;
typedef uint64_t EFI_STATUS;

typedef struct {
    uint64_t Signature;
    uint32_t Revision;
    uint32_t HeaderSize;
    uint32_t CRC32;
    uint32_t Reserved;
} EFI_TABLE_HEADER;

typedef struct {
    EFI_TABLE_HEADER Hdr;
    uint16_t* FirmwareVendor;
    uint32_t FirmwareRevision;
    EFI_HANDLE ConsoleInHandle;
    void* ConIn;
    EFI_HANDLE ConsoleOutHandle;
    void* ConOut;
    EFI_HANDLE StandardErrorHandle;
    void* StdErr;
    void* RuntimeServices;
    void* BootServices;
    uint64_t NumberOfTableEntries;
    void* ConfigurationTable;
} EFI_SYSTEM_TABLE;

typedef struct {
    uint64_t (*OutputString)(void* This, uint16_t* String);
} EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;

/* Serial port output for debugging */
static void serial_putc(char c) {
    /* Wait for transmit buffer empty */
    while (!((*(volatile uint8_t*)0x3FD) & 0x20));
    *(volatile uint8_t*)0x3F8 = c;
}

static void serial_puts(const char* s) {
    while (*s) {
        if (*s == '\n') serial_putc('\r');
        serial_putc(*s++);
    }
}

/* Function to load kernel from disk */
EFI_STATUS load_kernel(EFI_SYSTEM_TABLE* SystemTable) {
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL* con_out = (EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL*)SystemTable->ConOut;
    
    serial_puts("SageOS Bootloader Starting...\n");
    
    /* Just print a message for now to confirm we reach this C code */
    con_out->OutputString(con_out, (uint16_t*)L"Loading Kernel...\r\n");
    
    serial_puts("Attempting to jump to kernel at 0x100000...\n");
    
    return 0;
}
