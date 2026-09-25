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
| OS reaches its REPL and prints a prompt | **not yet** — resets before the first side effect |
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
constraint: its entry is `0x4008059c` in internal SRAM. Linking the image into
`0x40080000` made the fault disappear, so `linker_app.ld` uses:

- `IRAM0  0x40080000` — text, rodata, `.data` load address, and the stack
- `DRAM0  0x3FF80000` — `.data`, `.bss` (below the flash alias)
- `DRAM_HI 0x3FFC0000` — heap (above the flash alias)

The stack is placed adjacent to the code on purpose: the entry loads its address
with `l32r`, which reaches only +/-256 KiB.

### Fixed: `l32r` on this toolchain only reaches backwards

`l32r reg, label` with a *forward* label is rejected outright:

```
Error: operand 2 of 'l32r' has out of range value '8'
```

...even for a literal 8 bytes ahead. The compiler emits `l32r` with negative
offsets (e.g. `0xfffc0004`) because GCC places the literal pool *before* the
code that loads it. `hal/entry.S` follows that convention: the pool comes first,
then the instructions. An earlier version of that file had the pool after the
code and would not assemble.

### Fixed: the RTC register block is write-protected

Disabling the watchdog looked correct and had no effect, because the `RTC_WD_*`
registers come up write-protected after reset and every write is silently
dropped. `startup.c` now clears the protect field in `RTC_CNTL` (0x3FFA1060,
`0x5500`) before touching the watchdog block, and re-locks afterwards. The
watchdog is also *fed* rather than trusted to stay off, because on this part the
ROM-enabled RTC watchdog does not reliably stay disabled.

### Corrected: a reset loop is not evidence of a fault

The ROM reset-loops on its own whenever the second-stage image does not take
over — with **no image at all** at 0x1000 it prints `invalid header: 0xffffffff`
forever, and Espressif's own bootloader with no app prints its entry address in
a loop. So "the board keeps rebooting" says nothing on its own about whether the
image is at fault. Several hours were spent chasing the loop as if it were a
crash before this control experiment was run.

### Board and UART are healthy

With Espressif's bootloader installed and no app, the board produces 0% garbage
at 115200. The ROM log, the CP2102 bridge, and the crystal are all fine. The
authoritative UART register map also agrees with what the HAL uses
(`esp32-libs/3.3.11/include/soc/esp32/register/soc/uart_reg.h`: `0x00` FIFO,
`0x0C` INT_ENA, `0x14` CLKDIV, `0x18` AUTOBAUD, `0x1C` STATUS, `0x20` CONF0);
the AHB alias `UART_FIFO_AHB_REG` at `0x60000000` was tried as well.

### Open: the entry does not survive long enough to talk

`startup.c` has two diagnostic modes, both enabled with `SAGET_EXTRA_CFLAGS`:

- `-DSAGE_ENTRY_PARK_ONLY` — take over the watchdogs, then spin and touch
  nothing else.
- `-DSAGE_ENTRY_HEARTBEAT` — push a `[SAGE-ENTRY]` marker out of the UART
  before anything else.

Neither marker ever appears, and the park-only image still resets. The stub
assembles and links, and the ROM reports loading it and jumping to it, so the
handoff happens; the CPU then resets before the first observable side effect.
No fatal-exception backtrace is printed, so this is not an ordinary trap.

Things already tried and ruled out: code in the flash window vs. internal SRAM
at both `0x40080000` and `0x40078000`; UART offsets from the TRM, from the IDF
struct, and via the AHB alias; five clock sources (26/40/80/160/240/320 MHz) and
both the TRM and IDF divisor formulas; watching a suspiciously fast reset that
turned out to be the host's own RTS toggling EN; and opening the port with DTR
and RTS left deasserted.

Leading suspects, in order:

1. The image overruns the internal SRAM block it is linked into. At
   `0x40080000` the image is ~58 KB, past the 32 KB DRAM2 block; Espressif
   keeps its loadable part small and runs the rest from flash. Worth testing
   with a genuinely small image (a few hundred bytes) linked at `0x40078000` —
   the 256-byte park-only build was linked at `0x40080000` throughout.
2. Something between the ROM's jump and the first store. The stub is six
   instructions and the reported entry address matches, but the CPU may still
   be resetting on entry for a reason the ROM does not report.
3. Clock gating. UART0 and the RTC block are peripherals whose module clocks the
   ROM enables for itself; a bare-metal image that relies on them may need the
   module clock gate set explicitly (`APB_SERIAL_CLK_CONF`), which nothing here
   does yet.

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

The prerequisite is a small, self-contained emitter change: add `hw.flash_read8`,
`hw.flash_read32` and `hw.jump` to the known-native list in
`core/src/c/compiler.c` (and `core/src/sage/compiler.sage` for parity), with the
same no-op stubs the other `hw.*` names get. Once that lands the bootloader logic
is small: validate the app image header, read the entry address, jump.

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
