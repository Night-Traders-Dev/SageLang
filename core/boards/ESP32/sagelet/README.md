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
| OS reaches its REPL and prints a prompt | **not yet** — boots and runs, but stops after the first startup marker |
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

### Fixed: the watchdog was never actually disarmed

This was the real cause of the reset loop, and it took three rounds to find
because the failure is silent and the symptom is misleading.

The ROM leaves **three** watchdogs armed when it hands over to a second-stage
image. The previous startup code tried to disarm one of them using the
`0x3FFA1Fxx` "RTC_WD_*" block from older TRM revisions. On this chip that block
is not the watchdog: every write landed somewhere harmless. The registers that
matter are in the `0x3ff48000` RTC_CNTL block and the `0x3ff5f000` timer-group
blocks, and the timer-group ones sit behind a write-protect register unlocked
with the key `0x50d83aa1`:

| what | address | notes |
| --- | --- | --- |
| `RTC_CNTL_WDTWPROTECT` | `0x3ff480a4` | write `0x50d83aa1` to unlock |
| `RTC_CNTL_WDTCONFIG0` | `0x3ff4808c` | `WDT_EN` bit 31, `STG0` bits [30:28] |
| `TIMG0_WDTWPROTECT` | `0x3ff5f064` | same key |
| `TIMG0_WDTCONFIG0` | `0x3ff5f048` | `WDT_EN` bit 31, `STG0` bits [30:29] |
| `TIMG1_*` | `+0x1000` | second timer group, disarmed too |

All of these are transcribed from the installed IDF headers
(`rtc_cntl_reg.h`, `timer_group_reg.h`, `wdt_periph.h`).

Each fix moved the reset reason one step along, which is how the chain was
identified at all:

- wrong RTC addresses -> `rst:0x10 (RTCWDT_RTC_RESET)`
- RTC fixed, TG ignored -> still `RTCWDT_RTC_RESET`
- RTC + TG0 fixed -> `rst:0x7 (TG0WDT_SYS_RESET)`
- RTC + TG0 + TG1 fixed -> **no reset**; the image runs and parks

Verified three independent ways, none of which depend on the console: a
GPIO2 blink, a `SAGE_ENTRY_PARK_ONLY` build that stays up indefinitely, and a
build that streams tens of thousands of bytes to UART0 and keeps running.

### Fixed: the entry stub began with data, not code

`l32r` on this toolchain only reaches *backwards*, so the literal pool has to
precede the instructions that load it. That put 12 bytes of constants at the
image's load address. The entry is now a single `j` over the pool, so the first
instruction in the loaded segment is real code. The pool also has to stay
4-byte aligned: the `j` is 3 bytes, and an `l32r` whose target sits at an
unaligned offset is rejected as "out of range" (`-13` fails where `-12` works).

### Fixed: the UART TX FIFO always looked full

`REG_UART0_STATUS >> 16` was used unmasked. `txfifo_cnt` is bits [23:16], but
bits 31:29 are `TXD`/`RTSN`/`DTRN` and 27:24 are `st_utx_out`, so the value was
always at least `0x1000`, the "FIFO full" test was permanently true, and
`hal_uart_putc()` spun to its timeout and dropped **every byte**. With the mask
added, C code drives the console: a `P`-emitting park loop produced 45,840
characters and kept running.

Related: `hal_uart_init()` no longer reprograms the pads or the divisor. The ROM
has already routed GPIO1/GPIO3 and set 115200 on the clock source it is really
using, and `conf0.tick_ref_always_on` (bit 27) selects between the 26 MHz
crystal and the 80 MHz APB clock — assuming the wrong one gives roughly 3.3x the
intended rate. The IO_MUX map in this IDF is also sparse and non-uniform (pin 0
is `base+0x44`, pin 2 is `base+0x40`, pin 4 is `base+0x48`), so a stride-based
pin address is simply wrong for some pins. It only re-asserts `conf0.clk_en`,
because writes to a gated peripheral's FIFO are accepted and discarded.

### Fixed: DRAM was mapped to an address that is not DRAM

The linker claimed `0x3FF80000` for `DRAM0`. Internal DRAM begins at
`0x3FFB0000`. The ROM's loader will write a `.data` image to any address, so a
bogus placement looks completely fine at link and flash time — and `.bss`, which
is just a loop of stores, then walks into unmapped space. Now:

- `DRAM0` `0x3FFB0000`, 24 KB (`.data`)
- `DRAM_HI` `0x3FFCE000`, 200 KB (`.bss`, heap)

### Fixed: a diagnostic that hid its own result

A trace marker written *before* `take_over_watchdogs()` reliably produced
`RTCWDT_RTC_RESET`, because the UART write polls the FIFO and that polling runs
with the watchdog still armed. Any diagnostic has to disarm the watchdogs first,
or it manufactures the very failure it is looking for.

### Fixed: my own diagnostic was faking a toolchain bug

Worth recording, because it cost real time and the wrong conclusion was
committed before it was caught.

Startup markers are emitted with:

```c
#define TRACE(c) do {                        /* takes a CHARACTER */     \
        REG_UART0_CONF0 |= (1u << 25);                                  \
        while ((((REG_UART0_STATUS >> 16) & 0xFFu) >= 128u)) {}         \
        REG_UART0_FIFO = (uint32_t)(unsigned char)(c);                   \
    } while (0)
```

The `.bss` and later markers were still being passed **strings** — `TRACE("3-bss")`
— which expands to `(unsigned char)(&"3-bss"[0])`, i.e. the low byte of the
string's *address*, not `'3'`. On the wire that appeared as three mystery bytes
(`0x80 0x86 0x8d`, the low bytes of three different string pointers) and looked
exactly like corrupted or miscompiled data.

That produced two wrong conclusions, both now retracted:

- that string literals were being miscompiled — a literal really did live at
  `0x4008c2e8` while the `l32r` pool word held `0x4008d190`, but the two
  measurements came from different builds, and removing `-mlongcalls` or
  `-mtext-section-literals` never changed anything because nothing was wrong;
- that a line reading `ho 0 tail 12 room 4` came from the ROM. It is our own
  output. It still appears once per boot and is not yet explained, but it is
  definitely not the ROM (Espressif's own bootloader does not print it).

With the markers passing characters, **all four appear** (`1xxx`) and startup
runs clean through the watchdog takeover, the `.bss` clear, the `.data` copy and
into `main()`, with no reset.

### Open: the OS hangs before its first statement

`main()` is entered, and `hal_uart_init()` is never reached, so the hang is in
the generated runtime's own startup rather than in anything hand-written here.
A marker inside `hal_uart_init()` (build with `SAGET_EXTRA_CFLAGS=-DSAGE_HAL_TRACE`)
does not appear, which is what places the failure before the first `.sage`
statement executes.

Enlarging the stack from 24 KB to 48 KB and the heap from 96 KB to 100 KB did
not change it, so it is not simply out of room. Remaining suspects, in order:

1. The runtime's initial allocation. The heap starts at `0x3ffe6848` and the
   `.bss` at `0x3ffce000`; both are now inside real DRAM, but the allocator's
   assumptions about the region have not been checked against the runtime.
2. The generated C's global initialisers, which run before the first statement
   and are the only code executed between entry into `main()` and the OS body.
3. A CPU fault with no handler installed. Nothing resets, which argues against
   this, but an exception with an invalid vector table can spin instead.

This now looks like a runtime/toolchain question rather than a board one, and a
JTAG session would answer it immediately.

### JTAG

`gdb-multiarch` (with Xtensa support) and `openocd` v0.12.0-esp32 are both
installed. **No probe is connected** — the only ESP32 device on the bus is the
CP2102 UART bridge, which carries no JTAG lines. A session needs an external
probe (FTDI/ESP-PROG/CMSIS-DAP will all work; the `ftdi`, `cmsis-dap` and
`esp_usb_jtag` adapter configs ship with this openocd) wired to the board:

| board pin | signal |
| --- | --- |
| GPIO15 | TCK |
| GPIO13 | TMS |
| GPIO12 | TDI |
| GPIO14 | TDO |
| GND | ground |

Optionally `EN` and `GPIO0` for reset/boot control. With that in place:

```
openocd -f interface/ftdi/esp32_devkitj_v1.cfg -f target/esp32.cfg
gdb-multiarch core/boards/ESP32/sagelet/build/sagelet_os.elf \
    -ex 'target remote :3333' -ex 'monitor reset halt' -ex continue
```

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
