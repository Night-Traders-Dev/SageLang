/* linker_app.ld — classic ESP32 application image.
 *
 * Loaded by our second-stage bootloader from the OTA slot at 0x10000.
 *
 * Memory regions follow the ESP-IDF esp32 layout:
 *   IRAM0  0x3FFB0000  320 KB  the memory-mapped *flash* window. Code and
 *                              rodata must live here or they will not execute,
 *                              and .data is loaded from here at startup.
 *   DRAM   0x3FF80000  512 KB  SRAM: .data copy, .bss, heap, stack.
 *
 * The Xtensa windowed ABI uses a15 as the callee-saved stack pointer, so the
 * entry stub sets a0 to a safe value rather than argc.
 */

ENTRY(reset_handler)

MEMORY
{
  /* The ROM jumps to the second-stage entry before the flash cache is live,
   * so text must be executable without the cache: put it in internal SRAM.
   * Espressif's own bootloader does the same (its entry is 0x4008059c). */
  IRAM0 (rx)  : ORIGIN = 0x40080000, LENGTH = 0x20000
  /* SRAM below the flash alias. The alias is mapped *over* this address
   * range, so nothing else may be placed in 0x3FFB0000..0x3FFC0000. */
  DRAM0 (rw)  : ORIGIN = 0x3FF80000, LENGTH = 0x30000
  /* SRAM above the flash alias: free for the heap and the stack. */
  DRAM_HI (rw): ORIGIN = 0x3FFC0000, LENGTH = 0x20000
}

SECTIONS
{
  /* ---- code and read-only data: memory-mapped flash ------------------- */
  .iram0.text :
  {
    . = ALIGN(4);
    KEEP(*(.iram0.text.entry))
    *(.iram0.vectors .iram0.vectors.*)
    KEEP(*(.init))
    KEEP(*(.init.*))
    *(.literal .literal.*)
    *(.text .text.* .gnu.linkonce.t.*)
    . = ALIGN(4);
  } > IRAM0

  .iram0.rodata :
  {
    . = ALIGN(4);
    *(.rodata .rodata.* .gnu.linkonce.r.*)
    *(.srodata .srodata.*)
    . = ALIGN(8);
  } > IRAM0

  .flash1.appdesc :
  {
    . = ALIGN(4);
    KEEP(*(.flash1.appdesc))
  } > IRAM0

  /* ---- initialized data: runs from DRAM, loaded from IRAM0 ----------- */
  .data : ALIGN(4)
  {
    _data_start = ABSOLUTE(.);
    *(.data .data.* .gnu.linkonce.d.*)
    . = ALIGN(4);
    _data_end = ABSOLUTE(.);
  } > DRAM0 AT > IRAM0

  _data_load = LOADADDR(.data);

  /* ---- zero-initialized data, heap, stack ----------------------------- */
  .bss (NOLOAD) :
  {
    _bss_start = ABSOLUTE(.);
    . = ALIGN(8);
    *(.bss .bss.* .gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(8);
    _bss_end = ABSOLUTE(.);
  } > DRAM0

  .heap (NOLOAD) :
  {
    _heap_start = ABSOLUTE(.);
    . = ALIGN(8);
    . = . + 0x18000;          /* 96 KB heap for the Sage runtime */
    _heap_end = ABSOLUTE(.);
  } > DRAM_HI

  /* The stack sits immediately after the code, inside IRAM0, because the entry
   * stub loads _stack_top with l32r and that instruction only reaches +/-256 KiB.
   * Left down in DRAM_HI the address is ~4 MB away and the link fails with
   * "operand 2 of l32r has out of range value". */
  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    . = . + 0x6000;           /* 24 KB stack: the Sage REPL nests interpreter frames */
    . = ALIGN(16);
    _stack_top = ABSOLUTE(.);
  } > IRAM0

  _dram_end = ABSOLUTE(.) ;
  ASSERT(_bss_end <= ORIGIN(DRAM0) + LENGTH(DRAM0),
         "SageletOS .bss does not fit in DRAM0 (below the flash alias)")
  ASSERT(_heap_end <= ORIGIN(DRAM_HI) + LENGTH(DRAM_HI),
         "SageletOS heap does not fit in DRAM_HI (above the flash alias)")
  ASSERT(_stack_top <= ORIGIN(IRAM0) + LENGTH(IRAM0),
         "SageletOS stack does not fit in IRAM0 next to the code")
}
