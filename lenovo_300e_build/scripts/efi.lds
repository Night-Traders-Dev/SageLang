/* efi.lds — Minimal EFI Linker Script for x86_64 */
ENTRY(efi_main)
SECTIONS
{
    . = 0x1000;
    .text : {
        *(.text)
        *(.text.*)
    }
    . = ALIGN(4096);
    .data : {
        *(.data)
        *(.data.*)
        *(.rodata)
        *(.rodata.*)
    }
    . = ALIGN(4096);
    .reloc : {
        *(.reloc)
    }
    . = ALIGN(4096);
    .dynamic : { *(.dynamic) }
    .dynsym : { *(.dynsym) }
    .dynstr : { *(.dynstr) }
    .hash : { *(.hash) }
}
