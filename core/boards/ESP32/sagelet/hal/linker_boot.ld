/* linker_app.ld — classic ESP32 application image.
 *
 * Loaded by our second-stage bootloader from the OTA slot at 0x10000. The
 * Xtensa windowed ABI uses a1-a15 (a15 is the callee-saved stack pointer) and
 * a0-a15 plus the branch target, so the entry code lives at the very start and
 * a0 is set to a safe address rather than argc.
 */

ENTRY(reset_handler)

MEMORY
{
  /* ESP32-D0WD: 520 KB SRAM0 + 32 KB SRAM1 usable as one heap window. */
  IRAM0 (rx)  : ORIGIN = 0x3FFB0000, LENGTH = 0x50000
  DRAM (rwx)  : ORIGIN = 0x3FF80000, LENGTH = 0x80000
}

SECTIONS
{
  .rtc.text :
  {
    . = ALIGN(4);
    *(.rtc.text .rtc.text.*)
  } > DRAM

  .rtc.rodata :
  {
    . = ALIGN(4);
    *(.rtc.rodata .rtc.rodata.*)
  } > DRAM

  .rtc.data :
  {
    . = ALIGN(4);
    *(.rtc.data .rtc.data.*)
  } > DRAM

  .rtc.bss (NOLOAD) :
  {
    . = ALIGN(8);
    *(.rtc.bss .rtc.bss.*)
  } > DRAM

  .iram0.text :
  {
    . = ALIGN(4);
    *(.iram0.text .iram0.text.*)
    *(.iram0.vectors .iram0.vectors.*)
  } > IRAM0

  .iram0.rodata :
  {
    . = ALIGN(4);
    *(.iram0.rodata .iram0.rodata.*)
  } > IRAM0

  .dram0.text :
  {
    . = ALIGN(4);
    *(.literal .text .literal.* .text.* .gnu.linkonce.t.*)
    KEEP(*(.init))
    KEEP(*(.init.*))
  } > DRAM

  .dram0.rodata :
  {
    . = ALIGN(4);
    *(.rodata .rodata.* .gnu.linkonce.r.*)
    . = ALIGN(8);
  } > DRAM

  .ext_ram.text : { *(.flash1 .flash1.*) } > DRAM

  .data : ALIGN(4)
  {
    _data_start = ABSOLUTE(.);
    *(.data .data.* .gnu.linkonce.d.*)
    . = ALIGN(4);
    _data_end = ABSOLUTE(.);
  } > DRAM AT > IRAM0

  _data_load = LOADADDR(.data);

  .bss (NOLOAD) :
  {
    _bss_start = ABSOLUTE(.);
    . = ALIGN(8);
    *(.bss .bss.* .gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(8);
    _bss_end = ABSOLUTE(.);
  } > DRAM

  .heap (NOLOAD) :
  {
    _heap_start = ABSOLUTE(.);
    . = ALIGN(8);
    . = . + 0x20000;          /* 128 KB heap for the Sage runtime */
    _heap_end = ABSOLUTE(.);
  } > DRAM

  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    . = . + 0x8000;           /* 32 KB stack */
    . = ALIGN(16);
    _stack_top = ABSOLUTE(.);
  } > DRAM
}
