#include <stdint.h>
#include <stddef.h>

#if defined(__clang__) || defined(__GNUC__)
#define EFIAPI __attribute__((ms_abi))
#else
#define EFIAPI
#endif

typedef uint8_t  BOOLEAN;
typedef uint16_t CHAR16;
typedef uint64_t UINT64;
typedef int64_t  INT64;
typedef uint32_t UINT32;
typedef uint16_t UINT16;
typedef uint8_t  UINT8;
typedef uint64_t UINTN;
typedef uint64_t EFI_STATUS;
typedef void    *EFI_HANDLE;
typedef void    *EFI_EVENT;
typedef void    *EFI_DEVICE_PATH_PROTOCOL;
typedef uint64_t EFI_PHYSICAL_ADDRESS;
typedef uint64_t EFI_VIRTUAL_ADDRESS;

#define EFI_SUCCESS 0
#define EFI_ERROR_MASK 0x8000000000000000ULL
#define EFI_LOAD_ERROR (EFI_ERROR_MASK | 1)
#define EFI_INVALID_PARAMETER (EFI_ERROR_MASK | 2)
#define EFI_BUFFER_TOO_SMALL (EFI_ERROR_MASK | 5)

#define EFI_FILE_MODE_READ 0x0000000000000001ULL
#define KERNEL_LOAD_ADDR   0x100000ULL

typedef struct {
    UINT32 Data1;
    UINT16 Data2;
    UINT16 Data3;
    UINT8  Data4[8];
} EFI_GUID;

typedef struct {
    UINT64 Signature;
    UINT32 Revision;
    UINT32 HeaderSize;
    UINT32 CRC32;
    UINT32 Reserved;
} EFI_TABLE_HEADER;

typedef enum {
    AllocateAnyPages,
    AllocateMaxAddress,
    AllocateAddress
} EFI_ALLOCATE_TYPE;

typedef enum {
    EfiReservedMemoryType,
    EfiLoaderCode,
    EfiLoaderData,
    EfiBootServicesCode,
    EfiBootServicesData,
    EfiRuntimeServicesCode,
    EfiRuntimeServicesData,
    EfiConventionalMemory,
    EfiUnusableMemory,
    EfiACPIReclaimMemory,
    EfiACPIMemoryNVS,
    EfiMemoryMappedIO,
    EfiMemoryMappedIOPortSpace,
    EfiPalCode,
    EfiPersistentMemory,
    EfiMaxMemoryType
} EFI_MEMORY_TYPE;

typedef struct {
    UINT32 Type;
    UINT32 Pad;
    EFI_PHYSICAL_ADDRESS PhysicalStart;
    EFI_VIRTUAL_ADDRESS  VirtualStart;
    UINT64 NumberOfPages;
    UINT64 Attribute;
} EFI_MEMORY_DESCRIPTOR;

typedef struct EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
typedef struct EFI_SIMPLE_FILE_SYSTEM_PROTOCOL EFI_SIMPLE_FILE_SYSTEM_PROTOCOL;
typedef struct EFI_FILE_PROTOCOL EFI_FILE_PROTOCOL;
typedef struct EFI_BOOT_SERVICES EFI_BOOT_SERVICES;
typedef struct EFI_SYSTEM_TABLE EFI_SYSTEM_TABLE;

typedef EFI_STATUS (EFIAPI *EFI_TEXT_STRING)(
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *self,
    CHAR16 *string
);

struct EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
    void *Reset;
    EFI_TEXT_STRING OutputString;
    void *TestString;
    void *QueryMode;
    void *SetMode;
    void *SetAttribute;
    void *ClearScreen;
    void *SetCursorPosition;
    void *EnableCursor;
    void *Mode;
};

typedef EFI_STATUS (EFIAPI *EFI_ALLOCATE_PAGES)(
    EFI_ALLOCATE_TYPE Type,
    EFI_MEMORY_TYPE MemoryType,
    UINTN Pages,
    EFI_PHYSICAL_ADDRESS *Memory
);

typedef EFI_STATUS (EFIAPI *EFI_FREE_PAGES)(
    EFI_PHYSICAL_ADDRESS Memory,
    UINTN Pages
);

typedef EFI_STATUS (EFIAPI *EFI_GET_MEMORY_MAP)(
    UINTN *MemoryMapSize,
    EFI_MEMORY_DESCRIPTOR *MemoryMap,
    UINTN *MapKey,
    UINTN *DescriptorSize,
    UINT32 *DescriptorVersion
);

typedef EFI_STATUS (EFIAPI *EFI_ALLOCATE_POOL)(
    EFI_MEMORY_TYPE PoolType,
    UINTN Size,
    void **Buffer
);

typedef EFI_STATUS (EFIAPI *EFI_FREE_POOL)(
    void *Buffer
);

typedef EFI_STATUS (EFIAPI *EFI_HANDLE_PROTOCOL)(
    EFI_HANDLE Handle,
    EFI_GUID *Protocol,
    void **Interface
);

typedef EFI_STATUS (EFIAPI *EFI_LOCATE_PROTOCOL)(
    EFI_GUID *Protocol,
    void *Registration,
    void **Interface
);

typedef EFI_STATUS (EFIAPI *EFI_EXIT_BOOT_SERVICES)(
    EFI_HANDLE ImageHandle,
    UINTN MapKey
);

typedef EFI_STATUS (EFIAPI *EFI_SET_WATCHDOG_TIMER)(
    UINTN Timeout,
    UINT64 WatchdogCode,
    UINTN DataSize,
    CHAR16 *WatchdogData
);

struct EFI_BOOT_SERVICES {
    EFI_TABLE_HEADER Hdr;

    void *RaiseTPL;
    void *RestoreTPL;

    EFI_ALLOCATE_PAGES AllocatePages;
    EFI_FREE_PAGES FreePages;
    EFI_GET_MEMORY_MAP GetMemoryMap;
    EFI_ALLOCATE_POOL AllocatePool;
    EFI_FREE_POOL FreePool;

    void *CreateEvent;
    void *SetTimer;
    void *WaitForEvent;
    void *SignalEvent;
    void *CloseEvent;
    void *CheckEvent;

    void *InstallProtocolInterface;
    void *ReinstallProtocolInterface;
    void *UninstallProtocolInterface;
    EFI_HANDLE_PROTOCOL HandleProtocol;
    void *Reserved;
    void *RegisterProtocolNotify;
    void *LocateHandle;
    void *LocateDevicePath;
    void *InstallConfigurationTable;

    void *LoadImage;
    void *StartImage;
    void *Exit;
    void *UnloadImage;
    EFI_EXIT_BOOT_SERVICES ExitBootServices;

    void *GetNextMonotonicCount;
    void *Stall;
    EFI_SET_WATCHDOG_TIMER SetWatchdogTimer;

    void *ConnectController;
    void *DisconnectController;

    void *OpenProtocol;
    void *CloseProtocol;
    void *OpenProtocolInformation;

    void *ProtocolsPerHandle;
    void *LocateHandleBuffer;
    EFI_LOCATE_PROTOCOL LocateProtocol;
    void *InstallMultipleProtocolInterfaces;
    void *UninstallMultipleProtocolInterfaces;

    void *CalculateCrc32;
    void *CopyMem;
    void *SetMem;
    void *CreateEventEx;
};

struct EFI_SYSTEM_TABLE {
    EFI_TABLE_HEADER Hdr;
    CHAR16 *FirmwareVendor;
    UINT32 FirmwareRevision;

    EFI_HANDLE ConsoleInHandle;
    void *ConIn;

    EFI_HANDLE ConsoleOutHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *ConOut;

    EFI_HANDLE StandardErrorHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *StdErr;

    void *RuntimeServices;
    EFI_BOOT_SERVICES *BootServices;

    UINTN NumberOfTableEntries;
    void *ConfigurationTable;
};

typedef struct {
    UINT32 Revision;
    EFI_HANDLE ParentHandle;
    EFI_SYSTEM_TABLE *SystemTable;

    EFI_HANDLE DeviceHandle;
    EFI_DEVICE_PATH_PROTOCOL *FilePath;
    void *Reserved;

    UINT32 LoadOptionsSize;
    void *LoadOptions;

    void *ImageBase;
    UINT64 ImageSize;
    EFI_MEMORY_TYPE ImageCodeType;
    EFI_MEMORY_TYPE ImageDataType;

    EFI_STATUS (EFIAPI *Unload)(EFI_HANDLE ImageHandle);
} EFI_LOADED_IMAGE_PROTOCOL;

typedef EFI_STATUS (EFIAPI *EFI_FILE_OPEN)(
    EFI_FILE_PROTOCOL *self,
    EFI_FILE_PROTOCOL **new_handle,
    CHAR16 *file_name,
    UINT64 open_mode,
    UINT64 attributes
);

typedef EFI_STATUS (EFIAPI *EFI_FILE_CLOSE)(
    EFI_FILE_PROTOCOL *self
);

typedef EFI_STATUS (EFIAPI *EFI_FILE_READ)(
    EFI_FILE_PROTOCOL *self,
    UINTN *buffer_size,
    void *buffer
);

typedef EFI_STATUS (EFIAPI *EFI_FILE_GET_INFO)(
    EFI_FILE_PROTOCOL *self,
    EFI_GUID *information_type,
    UINTN *buffer_size,
    void *buffer
);

struct EFI_FILE_PROTOCOL {
    UINT64 Revision;
    EFI_FILE_OPEN Open;
    EFI_FILE_CLOSE Close;
    void *Delete;
    EFI_FILE_READ Read;
    void *Write;
    void *GetPosition;
    void *SetPosition;
    EFI_FILE_GET_INFO GetInfo;
    void *SetInfo;
    void *Flush;
};

typedef EFI_STATUS (EFIAPI *EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_OPEN_VOLUME)(
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *self,
    EFI_FILE_PROTOCOL **root
);

struct EFI_SIMPLE_FILE_SYSTEM_PROTOCOL {
    UINT64 Revision;
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_OPEN_VOLUME OpenVolume;
};

typedef struct {
    UINT64 Size;
    UINT64 FileSize;
    UINT64 PhysicalSize;
    char CreateTime[16];
    char LastAccessTime[16];
    char ModificationTime[16];
    UINT64 Attribute;
    CHAR16 FileName[1];
} EFI_FILE_INFO;

typedef struct {
    UINT32 RedMask;
    UINT32 GreenMask;
    UINT32 BlueMask;
    UINT32 ReservedMask;
} EFI_PIXEL_BITMASK;

typedef struct {
    UINT32 Version;
    UINT32 HorizontalResolution;
    UINT32 VerticalResolution;
    UINT32 PixelFormat;
    EFI_PIXEL_BITMASK PixelInformation;
    UINT32 PixelsPerScanLine;
} EFI_GRAPHICS_OUTPUT_MODE_INFORMATION;

typedef struct {
    UINT32 MaxMode;
    UINT32 Mode;
    EFI_GRAPHICS_OUTPUT_MODE_INFORMATION *Info;
    UINTN SizeOfInfo;
    EFI_PHYSICAL_ADDRESS FrameBufferBase;
    UINTN FrameBufferSize;
} EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE;

typedef struct EFI_GRAPHICS_OUTPUT_PROTOCOL EFI_GRAPHICS_OUTPUT_PROTOCOL;

struct EFI_GRAPHICS_OUTPUT_PROTOCOL {
    void *QueryMode;
    void *SetMode;
    void *Blt;
    EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE *Mode;
};

typedef struct {
    UINT64 magic;
    UINT64 framebuffer_base;
    UINT64 framebuffer_size;
    UINT32 width;
    UINT32 height;
    UINT32 pixels_per_scanline;
    UINT32 pixel_format;
    UINT32 reserved;
} SageOSBootInfo;

#define SAGEOS_BOOT_MAGIC 0x534147454F534249ULL

static EFI_GUID EFI_LOADED_IMAGE_PROTOCOL_GUID = {
    0x5B1B31A1, 0x9562, 0x11d2,
    {0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B}
};

static EFI_GUID EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID = {
    0x964E5B22, 0x6459, 0x11d2,
    {0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B}
};

static EFI_GUID EFI_FILE_INFO_GUID = {
    0x09576E92, 0x6D3F, 0x11d2,
    {0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B}
};

static EFI_GUID EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID = {
    0x9042A9DE, 0x23DC, 0x4A38,
    {0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A}
};

static EFI_SYSTEM_TABLE *gST;
static EFI_BOOT_SERVICES *gBS;
static SageOSBootInfo gBootInfo;

static void print(CHAR16 *s) {
    if (gST && gST->ConOut) {
        gST->ConOut->OutputString(gST->ConOut, s);
    }
}

static void print_hex64(UINT64 v) {
    static CHAR16 hex[] = L"0123456789ABCDEF";
    CHAR16 out[19];

    out[0] = L'0';
    out[1] = L'x';

    for (int i = 0; i < 16; i++) {
        out[2 + i] = hex[(v >> ((15 - i) * 4)) & 0xF];
    }

    out[18] = 0;
    print(out);
}

static void collect_gop_info(void) {
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = 0;

    gBootInfo.magic = SAGEOS_BOOT_MAGIC;
    gBootInfo.framebuffer_base = 0;
    gBootInfo.framebuffer_size = 0;
    gBootInfo.width = 0;
    gBootInfo.height = 0;
    gBootInfo.pixels_per_scanline = 0;
    gBootInfo.pixel_format = 0xFFFFFFFFU;
    gBootInfo.reserved = 0;

    EFI_STATUS status = gBS->LocateProtocol(
        &EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID,
        0,
        (void **)&gop
    );

    if (status != EFI_SUCCESS || !gop || !gop->Mode || !gop->Mode->Info) {
        print(L"GOP unavailable: ");
        print_hex64(status);
        print(L"\r\n");
        return;
    }

    gBootInfo.framebuffer_base = gop->Mode->FrameBufferBase;
    gBootInfo.framebuffer_size = gop->Mode->FrameBufferSize;
    gBootInfo.width = gop->Mode->Info->HorizontalResolution;
    gBootInfo.height = gop->Mode->Info->VerticalResolution;
    gBootInfo.pixels_per_scanline = gop->Mode->Info->PixelsPerScanLine;
    gBootInfo.pixel_format = gop->Mode->Info->PixelFormat;

    print(L"GOP framebuffer: ");
    print_hex64(gBootInfo.framebuffer_base);
    print(L" ");
    print_hex64(gBootInfo.width);
    print(L"x");
    print_hex64(gBootInfo.height);
    print(L"\r\n");
}

static EFI_STATUS load_kernel(EFI_HANDLE image_handle, UINT64 *kernel_size_out) {
    EFI_STATUS status;
    EFI_LOADED_IMAGE_PROTOCOL *loaded_image = 0;
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs = 0;
    EFI_FILE_PROTOCOL *root = 0;
    EFI_FILE_PROTOCOL *kernel = 0;

    status = gBS->HandleProtocol(
        image_handle,
        &EFI_LOADED_IMAGE_PROTOCOL_GUID,
        (void **)&loaded_image
    );

    if (status != EFI_SUCCESS) {
        print(L"HandleProtocol LoadedImage failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    status = gBS->HandleProtocol(
        loaded_image->DeviceHandle,
        &EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID,
        (void **)&fs
    );

    if (status != EFI_SUCCESS) {
        print(L"HandleProtocol SimpleFileSystem failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    status = fs->OpenVolume(fs, &root);

    if (status != EFI_SUCCESS) {
        print(L"OpenVolume failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    status = root->Open(
        root,
        &kernel,
        L"\\KERNEL.BIN",
        EFI_FILE_MODE_READ,
        0
    );

    if (status != EFI_SUCCESS) {
        print(L"Open \\KERNEL.BIN failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    UINTN info_size = 0;
    status = kernel->GetInfo(kernel, &EFI_FILE_INFO_GUID, &info_size, 0);

    if (status != EFI_BUFFER_TOO_SMALL) {
        print(L"GetInfo size failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    void *info_buf = 0;
    status = gBS->AllocatePool(EfiLoaderData, info_size, &info_buf);

    if (status != EFI_SUCCESS) {
        print(L"AllocatePool file info failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    status = kernel->GetInfo(kernel, &EFI_FILE_INFO_GUID, &info_size, info_buf);

    if (status != EFI_SUCCESS) {
        print(L"GetInfo failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    EFI_FILE_INFO *info = (EFI_FILE_INFO *)info_buf;
    UINT64 kernel_size = info->FileSize;
    *kernel_size_out = kernel_size;

    UINTN pages = (kernel_size + 0xFFF) / 0x1000;
    EFI_PHYSICAL_ADDRESS kernel_addr = KERNEL_LOAD_ADDR;

    status = gBS->AllocatePages(
        AllocateAddress,
        EfiLoaderData,
        pages,
        &kernel_addr
    );

    if (status != EFI_SUCCESS) {
        print(L"AllocatePages kernel failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    UINTN read_size = (UINTN)kernel_size;
    status = kernel->Read(kernel, &read_size, (void *)(uintptr_t)KERNEL_LOAD_ADDR);

    if (status != EFI_SUCCESS) {
        print(L"Read kernel failed: ");
        print_hex64(status);
        print(L"\r\n");
        return status;
    }

    if ((UINT64)read_size != kernel_size) {
        print(L"Short kernel read.\r\n");
        return EFI_LOAD_ERROR;
    }

    print(L"Kernel loaded at ");
    print_hex64(KERNEL_LOAD_ADDR);
    print(L", size ");
    print_hex64(kernel_size);
    print(L"\r\n");

    return EFI_SUCCESS;
}

static EFI_STATUS exit_boot_services_retry(EFI_HANDLE image_handle) {
    EFI_STATUS status;
    UINTN map_size = 0;
    UINTN map_key = 0;
    UINTN desc_size = 0;
    UINT32 desc_version = 0;
    EFI_MEMORY_DESCRIPTOR *map = 0;

    for (int attempt = 0; attempt < 8; attempt++) {
        map_size = 0;
        status = gBS->GetMemoryMap(&map_size, 0, &map_key, &desc_size, &desc_version);

        if (status != EFI_BUFFER_TOO_SMALL) {
            print(L"GetMemoryMap size failed: ");
            print_hex64(status);
            print(L"\r\n");
            return status;
        }

        map_size += desc_size * 16;

        status = gBS->AllocatePool(EfiLoaderData, map_size, (void **)&map);

        if (status != EFI_SUCCESS) {
            print(L"AllocatePool memory map failed: ");
            print_hex64(status);
            print(L"\r\n");
            return status;
        }

        status = gBS->GetMemoryMap(&map_size, map, &map_key, &desc_size, &desc_version);

        if (status != EFI_SUCCESS) {
            print(L"GetMemoryMap failed: ");
            print_hex64(status);
            print(L"\r\n");
            return status;
        }

        status = gBS->ExitBootServices(image_handle, map_key);

        if (status == EFI_SUCCESS) {
            return EFI_SUCCESS;
        }

        gBS->FreePool(map);
        map = 0;
    }

    print(L"ExitBootServices retry limit hit.\r\n");
    return EFI_INVALID_PARAMETER;
}

EFI_STATUS EFIAPI EfiMain(EFI_HANDLE image_handle, EFI_SYSTEM_TABLE *system_table) {
    gST = system_table;
    gBS = system_table->BootServices;

    if (gBS && gBS->SetWatchdogTimer) {
        gBS->SetWatchdogTimer(0, 0, 0, 0);
    }

    print(L"SageOS UEFI loader entered.\r\n");
    print(L"MS ABI loader active.\r\n");

    collect_gop_info();

    print(L"Loading KERNEL.BIN...\r\n");

    UINT64 kernel_size = 0;
    EFI_STATUS status = load_kernel(image_handle, &kernel_size);

    if (status != EFI_SUCCESS) {
        print(L"Kernel load failed.\r\n");
        for (;;) {}
    }

    print(L"Exiting boot services...\r\n");
    status = exit_boot_services_retry(image_handle);

    if (status != EFI_SUCCESS) {
        print(L"ExitBootServices failed: ");
        print_hex64(status);
        print(L"\r\n");
        for (;;) {}
    }

    typedef void (EFIAPI *kernel_entry_t)(SageOSBootInfo *);
    kernel_entry_t kernel_entry = (kernel_entry_t)(uintptr_t)KERNEL_LOAD_ADDR;
    kernel_entry(&gBootInfo);

    for (;;) {}
    return EFI_SUCCESS;
}
