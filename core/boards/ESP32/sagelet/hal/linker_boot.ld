/* linker_boot.ld — SageBoot, the ESP32 second-stage bootloader image.
 *
 * Flashed at 0x1000 and loaded by the ESP32 ROM bootloader, which then jumps to
 * the start of the loaded segment. The Xtensa windowed ABI uses a1-a15 with a15
 * as the callee-saved stack pointer, so hal/entry.S establishes both a1 and a15
 * before calling into C, and a0 is pointed at a safe address rather than argc.
 *
 * This script used to be an ESP-IDF-style ESP32 layout with two wrong regions:
 * IRAM0 at 0x3FFB0000 (that is DRAM0, and only 24 KB of it) and a "DRAM" region
 * at 0x3FF80000, which is not DRAM at all. Internal DRAM begins at 0x3FFB0000.
 * It also omitted KEEP(*(.iram0.text.entry)), so the build links with
 * --gc-sections and the entry stub -- the only thing the ROM jumps to -- was
 * garbage-collected, leaving an image with no entry point.
 *
 * The regions below are the ones verified on the board; see README, "What is now
 * verified on the board". The bootloader is small, so it takes a smaller heap
 * and stack than the application, but it uses the same map and the same section
 * order as linker_app.ld so the two images cannot drift apart.
 *
 * Note that nothing here is in flash. The ROM loads the whole image into
 * internal SRAM before it jumps, so code and rodata live in IRAM0.
 */

ENTRY(boot_entry)

MEMORY
{
  /* Code, rodata and the .data initialisers. The ROM jumps to the entry before
   * the flash cache is live, so text must be executable without the cache. */
  IRAM0 (rx)  : ORIGIN = 0x40080000, LENGTH = 0x20000   /* 128 KB */
  /* .data run-time copy. */
  DRAM0 (rw)  : ORIGIN = 0x3FFB0000, LENGTH = 0x6000    /* 24 KB */
  /* .bss, heap, stack. Ends exactly at the top of internal SRAM. */
  DRAM_HI (rw): ORIGIN = 0x3FFCE000, LENGTH = 0x32000   /* 200 KB */
}

SECTIONS
{
  /* ---- code and read-only data: loaded image --------------------------- */
  .iram0.text :
  {
    . = ALIGN(4);
    /* The entry stub must survive --gc-sections: it is what the ROM jumps to,
     * and nothing references it. It leads the section because the ROM lands on
     * the start of the loaded segment. */
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

  /* ---- initialized data: runs from DRAM, loaded from IRAM0 ------------ */
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
  } > DRAM_HI

  .heap (NOLOAD) :
  {
    _heap_start = ABSOLUTE(.);
    . = ALIGN(8);
    /* 96 KB. SageBoot has no GC and no intern table, so it needs far less than
     * the application's 72 KB-plus-98 KB of .bss. */
    . = . + 0x18000;
    _heap_end = ABSOLUTE(.);
  } > DRAM_HI

  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    . = . + 0x4000;            /* 16 KB stack */
    . = ALIGN(16);
    _stack_top = ABSOLUTE(.);
  } > DRAM_HI

  _dram_end = ABSOLUTE(.);

  ASSERT(_data_end <= ORIGIN(DRAM0) + LENGTH(DRAM0),
         "SageBoot .data does not fit in DRAM0")
  ASSERT(_heap_end <= ORIGIN(DRAM_HI) + LENGTH(DRAM_HI),
         "SageBoot heap does not fit in DRAM_HI")
  ASSERT(_stack_top <= ORIGIN(DRAM_HI) + LENGTH(DRAM_HI),
         "SageBoot stack does not fit in DRAM_HI")
}
