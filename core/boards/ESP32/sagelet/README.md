# Sagelet — a SageLang bootloader + OS for the classic ESP32

Target: **ESP32-D0WD-V3 rev 3.1** (ESP-WROOM-32 / DevKit, 4 MB flash, 26 MHz
crystal, CP2102 on `/dev/ttyUSB0`). Verified against the board on 2026-09-25.

## Status: build pipeline works, on-device bring-up is incomplete

Read this before assuming the images run. See [Findings](#findings) for what is
proven and what is not.

| Stage | State |
| ----- | ----- |
| `sage --emit-pico-c` on `os.sage` | works |
| Rewriting the emitted `hw.*` stub block for a real HAL | works |
| Cross-compiling + linking with newlib | works |
| `esptool elf2image` -> flashable image | works (valid header, checksum) |
| `esptool write-flash` | works (ROM loads every segment) |
| ROM jumps to the entry and executes it | works (one real bug found and fixed) |
| OS reaches its REPL and prints a prompt | **not yet** — chip resets first |
| `blink` over the REPL | **not reached** |

## Layout

```
0x001000  (intended)  SageBoot   — second-stage bootloader, boot.sage
0x008000  (intended)  partition table (gen_partitions.py)
0x010000  (intended)  SageOS     — os.sage, the REPL
```

## Files

- `os.sage` — the OS and REPL in SageLang. Commands: `help`, `blink [n] [on_ms]
  [off_ms]`, `led on|off|read`, `uptime`, `clock`, `temp`, `board`, `bootinfo`,
  `ver`, `clear`, `reset`.
- `boot.sage` — placeholder. **Not implemented yet**; see the emitter gap below.
- `hal/esp32_hal.[ch]` — the bare-metal target shim: UART0, GPIO, timing,
  flash read, jump, reset. Register map taken from the Espressif headers
  shipped with the local Arduino-ESP32 core rather than from memory.
- `hal/startup.c` — reset handler: takes over the watchdogs, clears `.bss`,
  copies `.data`, calls `main`.
- `hal/linker_app.ld` — memory layout. See the internal-SRAM note below.
- `gen_partitions.py` — ESP32 partition-table builder (esptool 5.x dropped
  `gen-partition-table`).
- `build.sh` — emit, rewrite, compile, link, `elf2image`.
- `flash.sh` — not written yet; the commands are in this file.

## Build

Requires the Arduino-ESP32 core (supplies the Xtensa toolchain):

```bash
arduino-cli core install esp32:esp32     # provides xtensa-esp32-elf-gcc
bash core/boards/ESP32/sagelet/build.sh all
```

`build.sh` finds the toolchain on `PATH` or under
`~/.arduino15/packages/esp32/tools/esp-x32/*/bin`.

## Findings

### Fixed: the second-stage entry cannot live in the flash window

The first image died immediately with

```
Fatal exception (2): InstructionFetchError
epc1=0x3ffb0180, excvaddr=0x3ffb0180
```

The ROM jumps to the entry before the flash cache is live, so code in the
`0x3FFB0000` window cannot be fetched. Espressif's own bootloader has the same
constraint and puts its entry in internal SRAM (`0x4008059c`, and a segment at
`0x40080400`). Linking the image into `0x40080000` made the fault disappear.
`linker_app.ld` therefore uses:

- `IRAM0  0x40080000` — text, rodata, `.data` load, and the stack
- `DRAM0  0x3FF80000` — `.data`, `.bss` (below the flash alias)
- `DRAM_HI 0x3FFC0000` — heap (above the flash alias)

The stack is placed adjacent to the code deliberately: the entry needs its
address in an `l32r`, which only reaches +/-256 KiB.

### Fixed: the ROM does not leave a usable stack

The entry must establish `a15` (the Xtensa windowed-ABI stack pointer) before
entering C. A dedicated `entry.S` stub was attempted, but this toolchain's
assembler rejects `l32r` at any offset in every configuration tested, so the
stub is currently absent. The ROM's leftover stack has been adequate in
practice; this is unresolved rather than proven safe.

### Open: the chip resets before the REPL starts

Symptom: the ROM loads every segment, the image executes (it has produced
`print()` output), and then the board resets and the ROM bootloader logs again.
A single-character test that parks immediately does not survive.

Things ruled out by experiment:

- **UART register offsets.** The authoritative map
  (`esp32-libs/3.3.11/include/soc/esp32/register/soc/uart_reg.h`) confirms
  `0x00` FIFO, `0x14` CLKDIV, `0x18` AUTOBAUD, `0x1C` STATUS, `0x20` CONF0 —
  the same as the IDF struct. The AHB alias `UART_FIFO_AHB_REG` at `0x60000000`
  was also tried.
- **Baud/clock source.** Swept 26/40/80/160/240/320 MHz and both the TRM
  (`div_v = div-1`) and IDF (`div_int`/`div_frag`) formulas. The observed byte
  pattern was *identical* across every one of them, which is only possible if
  the traffic is not the program's own output.
- **The host and the board's UART.** The Espressif ROM bootloader prints its
  log cleanly at 115200 on the same port, repeatedly.

So the UART path is known-good and the register map is correct; what remains is
a reset during Sage runtime start-up. Leading suspects, in order:

1. The Sage runtime's static footprint. The image has ~100 KiB of `.bss` and the
   emitted GC root/temp structures are large; something may be writing past a
   region, or tripping the stack guard.
2. `stdio_init_all()` / `sleep_ms(2000)` at the top of the emitted `main` — the
   2-second busy-wait runs before any Sage code and may be the reset window.
3. The heap. It is 96 KiB at `0x3FFC0000`; `_sbrk` is a simple bump allocator
   over `_heap_start.._heap_end` with no guard, so an over-large request
   returns `(void*)-1` and callers may not check.

### Not started: the bootloader

`boot.sage` cannot yet read the partition table or hand off to the app, because
neither primitive is reachable from SageLang:

- `mem_read`/`mem_write` are **intentionally confined** to `mem_alloc` regions
  by `sage_mem_range_valid()` in the emitted runtime, so they cannot touch
  memory-mapped flash. Weakening that to enable MMIO would be a regression in a
  memory-safety check, so it was not done.
- The emitter's `hw.*` module is the documented "implementation defined per
  target" hook and is where flash-read and jump belong, but it currently
  exposes only 25 names and neither of these.

The prerequisite is therefore a small, self-contained emitter change: add
`hw.flash_read8`, `hw.flash_read32` and `hw.jump` to the known-native list in
`core/src/c/compiler.c` (and `core/src/sage/compiler.sage` for parity), with
the same no-op stubs the other `hw.*` names get. Once that lands, the
bootloader logic itself is small: validate the app image header, read the
entry address, jump.

## Flashing by hand

```bash
python3 -m esptool --port /dev/ttyUSB0 --baud 115200 --no-stub \
    erase-region 0x0 0x400000

python3 -m esptool --port /dev/ttyUSB0 --baud 460800 --no-stub \
    write-flash --flash-mode dio --flash-size detect --flash-freq 40m \
    -z 0x1000  core/boards/ESP32/sagelet/build/sagelet_os.bin
```

The board currently holds this experimental image and will reset-loop. To
restore a usable device, see the CircuitPython recovery recipe in
`core/docs/esp32.md`, or flash an Arduino sketch with `arduino-cli`.
