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

ENTRY(boot_entry)

MEMORY
{
  /* The ROM jumps to the second-stage entry before the flash cache is live,
   * so text must be executable without the cache: put it in internal SRAM.
   * Espressif's own bootloader does the same (its entry is 0x4008059c). */
  IRAM0 (rx)  : ORIGIN = 0x40080000, LENGTH = 0x20000
  /* Real internal DRAM, per the ESP32 memory map and the ESP-IDF layout.
   *
   * This used to claim 0x3FF80000, which is not DRAM: internal DRAM begins at
   * 0x3FFB0000. The ROM's loader will happily write a .data image to an
   * arbitrary address, so a bogus .data placement looks fine at link and flash
   * time -- and .bss, which is simply a loop of stores, then walks off into
   * unmapped space. Symptom: everything up to the .bss clear works, then
   * nothing, with no reset and no output. */
  DRAM0 (rw)  : ORIGIN = 0x3FFB0000, LENGTH = 0x6000
  /* The high DRAM block, ending exactly at the top of internal SRAM. */
  DRAM_HI (rw): ORIGIN = 0x3FFCE000, LENGTH = 0x32000
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
  /* .bss is ~100 KB, far more than DRAM0's 24 KB, so it goes in the high
   * block. Keeping it out of DRAM0 also leaves the low block free for .data,
   * which does have to be adjacent to its load address in a predictable
   * place. */
  .bss (NOLOAD) :
  {
    _bss_start = ABSOLUTE(.);
    . = ALIGN(8);
    *(.bss .bss.* .gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(8);
    _bss_end = ABSOLUTE(.);
  } > DRAM_HI

  .heap (NOLOAD) :
  {
    _heap_start = ABSOLUTE(.);
    . = ALIGN(8);
    . = . + 0x11000;          /* 68 KB heap: DRAM_HI holds .bss, heap and stack,
                             * and the ASSERT below enforces that */
    _heap_end = ABSOLUTE(.);
  } > DRAM_HI

  /* The stack sits immediately after the code, inside IRAM0, because the entry
   * stub loads _stack_top with l32r and that instruction only reaches +/-256 KiB.
   * Left down in DRAM_HI the address is ~4 MB away and the link fails with
   * "operand 2 of l32r has out of range value". */
  /* The stack lives in high DRAM, not next to the code. entry.S loads
   * _stack_top as a plain 32-bit constant, so the address can be anywhere --
   * the l32r reach argument only ever mattered while the pool had to sit near
   * the load address, which it no longer does now that boot_entry is a j over
   * the pool. Keeping it in IRAM0 also meant the stack sat directly above the
   * loaded image, so a modest overflow silently corrupted rodata. */
  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    . = . + 0x8000;           /* 32 KB stack */
    . = ALIGN(16);
    _stack_top = ABSOLUTE(.);
  } > DRAM_HI

  _dram_end = ABSOLUTE(.) ;
  ASSERT(_data_end <= ORIGIN(DRAM0) + LENGTH(DRAM0),
         "SageletOS .data does not fit in DRAM0")
  ASSERT(_heap_end <= ORIGIN(DRAM_HI) + LENGTH(DRAM_HI),
         "SageletOS heap does not fit in DRAM_HI (above the flash alias)")
  ASSERT(_stack_top <= ORIGIN(DRAM_HI) + LENGTH(DRAM_HI),
         "SageletOS stack does not fit in DRAM_HI")
  /* No overlap check needed against IRAM0 any more: the loaded image lives
   * there and the stack is in DRAM_HI, so the two are in different windows by
   * construction. The fit assert above is the one that matters. */
}
