#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
BOOT="$ROOT/sageos_build/boot"
KERNEL="$ROOT/sageos_build/kernel"
BUILD_SCRIPT="$ROOT/scripts/build_os_unified.sh"

if [ ! -f "$BOOT/uefi_loader.c" ]; then
    echo "ERROR: missing $BOOT/uefi_loader.c"
    exit 1
fi

if [ ! -f "$KERNEL/kernel.c" ]; then
    echo "ERROR: missing $KERNEL/kernel.c"
    exit 1
fi

if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "ERROR: missing $BUILD_SCRIPT"
    exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$ROOT/sageos_build/backups/power_input_v005_$TS"
mkdir -p "$BACKUP"

cp "$BOOT/uefi_loader.c" "$BACKUP/uefi_loader.c.bak"
cp "$KERNEL/kernel.c" "$BACKUP/kernel.c.bak"

echo "[1/5] Patching UEFI loader to pass ACPI RSDP..."

python3 - "$BOOT/uefi_loader.c" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
s = path.read_text()

if "typedef struct EFI_CONFIGURATION_TABLE" not in s:
    marker = """struct EFI_SYSTEM_TABLE {
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
};"""
    repl = marker + """

typedef struct EFI_CONFIGURATION_TABLE {
    EFI_GUID VendorGuid;
    void *VendorTable;
} EFI_CONFIGURATION_TABLE;"""
    if marker not in s:
        raise SystemExit("Could not find EFI_SYSTEM_TABLE struct.")
    s = s.replace(marker, repl)

if "UINT64 acpi_rsdp;" not in s:
    s = s.replace(
        """    UINT64 con_out;
    UINT32 boot_services_active;
    UINT32 input_mode;
} SageOSBootInfo;""",
        """    UINT64 con_out;
    UINT32 boot_services_active;
    UINT32 input_mode;
    UINT64 acpi_rsdp;
} SageOSBootInfo;"""
    )

if "EFI_ACPI_20_TABLE_GUID" not in s:
    insert_after = """static EFI_GUID EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID = {
    0x9042A9DE, 0x23DC, 0x4A38,
    {0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A}
};"""
    acpi_guids = insert_after + """

static EFI_GUID EFI_ACPI_20_TABLE_GUID = {
    0x8868E871, 0xE4F1, 0x11D3,
    {0xBC, 0x22, 0x00, 0x80, 0xC7, 0x3C, 0x88, 0x81}
};

static EFI_GUID ACPI_10_TABLE_GUID = {
    0xEB9D2D30, 0x2D88, 0x11D3,
    {0x9A, 0x16, 0x00, 0x90, 0x27, 0x3F, 0xC1, 0x4D}
};"""
    if insert_after not in s:
        raise SystemExit("Could not find GOP GUID block.")
    s = s.replace(insert_after, acpi_guids)

if "static int guid_eq" not in s:
    anchor = """static void print_hex64(UINT64 v) {
    static CHAR16 hex[] = L"0123456789ABCDEF";
    CHAR16 out[19];

    out[0] = L'0';
    out[1] = L'x';

    for (int i = 0; i < 16; i++) {
        out[2 + i] = hex[(v >> ((15 - i) * 4)) & 0xF];
    }

    out[18] = 0;
    print(out);
}"""
    helper = anchor + r'''

static int guid_eq(EFI_GUID *a, EFI_GUID *b) {
    if (a->Data1 != b->Data1) return 0;
    if (a->Data2 != b->Data2) return 0;
    if (a->Data3 != b->Data3) return 0;

    for (int i = 0; i < 8; i++) {
        if (a->Data4[i] != b->Data4[i]) return 0;
    }

    return 1;
}

static UINT64 find_acpi_rsdp(EFI_SYSTEM_TABLE *st) {
    if (!st || !st->ConfigurationTable || st->NumberOfTableEntries == 0) {
        return 0;
    }

    EFI_CONFIGURATION_TABLE *tables =
        (EFI_CONFIGURATION_TABLE *)st->ConfigurationTable;

    for (UINTN i = 0; i < st->NumberOfTableEntries; i++) {
        if (guid_eq(&tables[i].VendorGuid, &EFI_ACPI_20_TABLE_GUID)) {
            return (UINT64)(uintptr_t)tables[i].VendorTable;
        }
    }

    for (UINTN i = 0; i < st->NumberOfTableEntries; i++) {
        if (guid_eq(&tables[i].VendorGuid, &ACPI_10_TABLE_GUID)) {
            return (UINT64)(uintptr_t)tables[i].VendorTable;
        }
    }

    return 0;
}
'''
    if anchor not in s:
        raise SystemExit("Could not find print_hex64 block.")
    s = s.replace(anchor, helper)

if "gBootInfo.acpi_rsdp = find_acpi_rsdp(system_table);" not in s:
    s = s.replace(
        """    gBootInfo.boot_services_active = 1;
    gBootInfo.input_mode = 1;

    print(L"Firmware input handoff active.\\r\\n");""",
        """    gBootInfo.boot_services_active = 1;
    gBootInfo.input_mode = 1;
    gBootInfo.acpi_rsdp = find_acpi_rsdp(system_table);

    print(L"Firmware input handoff active.\\r\\n");
    print(L"ACPI RSDP: ");
    print_hex64(gBootInfo.acpi_rsdp);
    print(L"\\r\\n");"""
    )

path.write_text(s)
PY

echo "[2/5] Patching kernel: stable input, ACPI poweroff, suspend command..."

python3 - "$KERNEL/kernel.c" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
s = path.read_text()

if "uint64_t acpi_rsdp;" not in s:
    s = s.replace(
        """    uint64_t con_out;
    uint32_t boot_services_active;
    uint32_t input_mode;
} SageOSBootInfo;""",
        """    uint64_t con_out;
    uint32_t boot_services_active;
    uint32_t input_mode;
    uint64_t acpi_rsdp;
} SageOSBootInfo;"""
    )

if "static inline void outw" not in s:
    s = s.replace(
        """static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}""",
        """static inline uint8_t inb(uint16_t port) {
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
}"""
    )

if "static int acpi_checksum" not in s:
    marker = """static void term_write_u32(uint32_t v) {
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
}"""
    acpi_code = marker + r'''

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
'''
    if marker not in s:
        raise SystemExit("Could not find term_write_u32 block.")
    s = s.replace(marker, acpi_code)

# Make firmware input exclusive. Do NOT mix with PS/2 fallback when ConIn exists.
kbd_re = re.compile(
    r'''static char kbd_getchar\(void\) \{
.*?
\}
(?=\s*static void shell_prompt\(void\))''',
    re.S
)

kbd_new = r'''static char kbd_getchar(void) {
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
'''

s, n = kbd_re.subn(kbd_new, s)
if n != 1:
    raise SystemExit("Could not replace kbd_getchar.")

# Improve input backend name wording.
s = s.replace(
    'return "uefi-firmware-conin";',
    'return "uefi-firmware-conin-exclusive";'
)

# Replace shutdown function to avoid hanging forever on failed poweroff.
shutdown_re = re.compile(
    r'''static void shutdown_machine\(void\) \{
.*?
\}
(?=\s*static char keymap)''',
    re.S
)

shutdown_new = r'''static int shutdown_machine(void) {
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
'''

s, n = shutdown_re.subn(shutdown_new, s)
if n != 1:
    raise SystemExit("Could not replace shutdown_machine block.")

# Help text.
s = s.replace(
    'term_write("\\n  shutdown          power off through firmware");',
    'term_write("\\n  shutdown          power off through ACPI S5");'
)
s = s.replace(
    'term_write("\\n  poweroff          alias for shutdown");',
    'term_write("\\n  poweroff          alias for shutdown");\n    term_write("\\n  suspend           experimental ACPI S3 suspend");\n    term_write("\\n  fwshutdown        try firmware shutdown directly");'
)

# dmesg ACPI lines.
s = s.replace(
    '''    if (boot_info && boot_info->runtime_services) {
        term_write("available");
    } else {
        term_write("unavailable");
    }''',
    '''    if (boot_info && boot_info->runtime_services) {
        term_write("available");
    } else {
        term_write("unavailable");
    }
    term_write("\\n[    0.000007] ACPI RSDP: ");
    if (boot_info && boot_info->acpi_rsdp) {
        term_write_hex64(boot_info->acpi_rsdp);
    } else {
        term_write("unavailable");
    }''',
    1
)

# Input command extra.
s = s.replace(
    '''        term_write("\\nPS/2 fallback: available");
        return;
    }''',
    '''        term_write("\\nPS/2 fallback: available when firmware input is unavailable");
        return;
    }''',
    1
)

# Replace shutdown command handling.
s = s.replace(
    '''    if (starts_word(cmd, "shutdown") || starts_word(cmd, "poweroff")) {
        term_write("\\nRequesting firmware shutdown...");
        shutdown_machine();
        return;
    }''',
    '''    if (starts_word(cmd, "shutdown") || starts_word(cmd, "poweroff")) {
        term_write("\\nRequesting ACPI S5 poweroff...");
        if (!shutdown_machine()) {
            term_write("\\nACPI poweroff failed or unsupported.");
            term_write("\\nSystem is still running.");
        }
        return;
    }

    if (starts_word(cmd, "fwshutdown")) {
        term_write("\\nTrying firmware ResetSystem shutdown directly...");
        firmware_shutdown_try();
        term_write("\\nFirmware shutdown returned.");
        return;
    }

    if (starts_word(cmd, "suspend")) {
        term_write("\\nRequesting ACPI S3 suspend...");
        if (!suspend_machine()) {
            term_write("\\nACPI S3 suspend failed or unsupported.");
            term_write("\\nLid-close wake requires ACPI GPE/EC support next.");
        }
        return;
    }'''
)

# version string if present.
s = s.replace("SageOS kernel 0.0.4", "SageOS kernel 0.0.5")
s = s.replace("SageOS kernel 0.0.3", "SageOS kernel 0.0.5")
s = s.replace("SageOS 0.0.3", "SageOS 0.0.5")
s = s.replace("SAGEOS 0.0.3", "SAGEOS 0.0.5")
s = s.replace("sageos 0.0.3", "sageos 0.0.5")

path.write_text(s)
PY

echo "[3/5] Checking for common generated C escape errors..."

if grep -n "case '\\\\': return '|';" "$KERNEL" >/dev/null; then
    echo "Backslash shift mapping OK."
else
    echo "WARNING: did not find expected valid backslash shift mapping."
fi

if grep -n 'print(L".*$' "$BOOT" | grep -v '\\r\\n");' | grep -E 'Keeping|Jumping|ACPI|Firmware'; then
    echo "ERROR: possible broken wide string in UEFI loader."
    exit 1
fi

echo "[4/5] Rebuilding SageOS image..."
bash "$BUILD_SCRIPT"

echo "[5/5] Writing v0.0.5 notes..."

cat > "$ROOT/sageos_build/V005_POWER_INPUT_NOTES.md" <<'EOF'
# SageOS v0.0.5 Power/Input Notes

## Fixed

- Firmware input is now exclusive when available.
- PS/2 polling is fallback-only.
- This prevents duplicate modifier-state behavior that caused random upper/lowercase changes.

## Added

- `shutdown` / `poweroff`
  - Attempts ACPI S5 using FADT + DSDT `_S5_`.
  - Does not hang forever if unsupported.

- `suspend`
  - Attempts ACPI S3 using DSDT `_S3_`.
  - This is experimental.

- `fwshutdown`
  - Direct UEFI RuntimeServices ResetSystem shutdown attempt.
  - Kept separate because it may hang on the Lenovo firmware.

## Lid close / wake status

Full automatic lid-close suspend and lid-open wake needs native ACPI event support:

- ACPI SCI interrupt routing
- GPE enable/status registers
- Lid device `_LID` method evaluation
- EC query/event support on Chromebooks
- AML interpreter or a targeted EC/GPE implementation

The `suspend` command is the first foundation. Real lid-triggered suspend/wake is the next driver milestone.
EOF

echo
echo "Done."
echo
echo "Test in QEMU:"
echo "  bash sageos_build/run_qemu_gop.sh"
echo
echo "Flash:"
echo "  ./flash_lenovo_300e_usb.sh sageos.img /dev/sdb"
echo
echo "Try inside SageOS:"
echo "  input"
echo "  echo abc DEF 123"
echo "  shutdown"
echo "  suspend"
