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

### Fixed: the delay never returned

`hal_delay_us()` was derived from a cycle count, and the cycle count was read
from `0x3FFFE000` -- which is not a peripheral at all, and returns a constant.
Every delay therefore spun forever. That is not a subtle stall: the emitted
`main()` opens with `stdio_init_all()` and then `sleep_ms(2000)`, so the hang
landed immediately after the console came up and looked exactly like "the
runtime never starts".

Switching to `rsr ccount` (the real Xtensa instruction counter) is not enough
either. ccount does advance -- a probe emitted `y` every time -- but by only
about 32 counts per call, nowhere near `CPU_HZ`. A deadline derived from 240 MHz
is roughly a million times too far away, so `sleep_ms()` still never returned.
The delay is now a calibrated nop loop (`HAL_DELAY_NOPS`), which is imprecise
and burns CPU but always terminates, which is what the OS needs in order to
boot. The proper replacement is TIMG0, whose register map is already known.

### Fixed: `$EXTRA_CFLAGS` only reached one translation unit

`SAGET_EXTRA_CFLAGS` was passed to `startup.c` and nothing else. A `-D` meant to
instrument the HAL was silently dropped, so the marker was never compiled in and
its absence was misread as "the OS hangs before `uart_init`". The flag now
reaches the generated C, the HAL and the newlib shim.

### Fixed: the stack was on top of the loaded image

The stack lived in IRAM0 immediately after the loaded text and rodata, so a
modest overflow silently corrupted code instead of faulting. Nothing needs it
there: `entry.S` loads `_stack_top` as a plain 32-bit constant, so the `l32r`
reach argument only ever applied while the literal pool had to sit near the load
address -- and it no longer does, now that `boot_entry` is a `j` over the pool.
The stack is in high DRAM with the `.bss` and heap, and the linker asserts that
all three fit.

### Fixed: the entry established `a15` but not `a1`

`a15` is the callee-saved stack pointer, but `a1` is the *call stack* pointer,
and every prologue's `entry a1, N` pushes a window increment there. Setting only
`a15` leaves `a1` pointing into whatever the ROM was using, so leaf code that
only stores to peripherals works while the first genuinely nested call sequence
walks off the end of it. Both now start at the same top, as in a normal ESP-IDF
application.

### Fixed: `__getreent` was newlib's failing stub

The linker had been saying this all along, past in the build output:

```
warning: __getreent is not implemented and will always fail
```

newlib's `malloc` is `_malloc_r(__getreent(), size)` -- the reentrancy struct
is an argument, not something it looks up itself. A single-core bare-metal image
has exactly one, so a static instance is the whole implementation. Without it
the first heap allocation in the runtime operates on a NULL reent pointer.

This is not the current blocker, but it was a real defect on the path and the
warning is now gone.

### Fixed: the GPIO register map was wrong

The HAL based GPIO at `0x3FF44504` with ad-hoc offsets. That is not the GPIO
block: `DR_REG_GPIO_BASE` is `0x3ff44000`, so `GPIO_OUT_W1TS` for pin 2 was being
computed as `0x3FF44528` where the real address is `0x3ff44008`. Every `gpio_put`
and `gpio_set_dir` was writing an unrelated register. `led_init()` is the first
thing the OS does once it is up, so this sat directly on the startup path.

The map is now transcribed from `gpio_reg.h`, with the bank arithmetic spelled
out: the ESP32 has 40 GPIOs, so two banks of 32. `OUT` is at `+0x04` with
`W1TS`/`W1TC` at `+0x08`/`+0x0c` and the next bank at `+0x10` (stride `0x0c`);
`ENABLE` follows the same stride from `+0x20`; `IN` is at `+0x3c` with a `0x04`
stride.

`hal_gpio_set_dir()` also assigned a literal `1u << 2`, which both hardcoded pin
2 and cleared every other pin's output enable -- the LED would have worked and
the rest of the board gone dead. It is now a read-modify-write of the pin's bit.

There is deliberately **no** pad-mux write any more. The `IO_MUX` registers are
not strided: in this IDF pin 0 is `base+0x44`, pin 2 is `base+0x40`, pin 4 is
`base+0x48`, pin 5 is `base+0x6c`, so any address computed from a pin number
lands in the wrong place. It is also unnecessary: GPIO1, GPIO2 and GPIO3 all come
out of reset with the plain GPIO function selected, which is everything this HAL
touches. `hal_gpio_set_pull()` is now an explicit no-op for the same reason --
`SETUP`/`PUPD` are not in this IDF's `gpio_reg.h` at all, and guessing is exactly
the mistake documented above.

### Narrowed to: `sage_string_const` receives the wrong pointer

**Correction first.** An earlier commit claimed a specific root cause -- that
string-literal `l32r` pool entries resolve to newlib's assertion text at
`0x4008d3ed` -- and that claim is withdrawn. It came from two bad measurements:
the pool word was picked as "the nearest preceding `l32r`", which belonged to a
different call (`SAGE_EQ`), and the "pointer is outside every segment" reading
came from a hand-rolled segment parser using the wrong offset. esptool's own
`image-info` shows the image is well formed: `0x12c` at `0x3ffb0000`, `0xd084` at
`0x40080000`, `0xf38` at `0x4008d088`.

What is established, by direct on-the-wire measurement:

1. Startup reaches `sage_string_const` and stops inside it. A marker at function
   entry arrives; one after `sage_intern_hash()` does not.
2. It is the string path. Neutralising only the 16 `sage_string_const(...)` call
   sites lets the OS start; neutralising only the 9 `sage_make_array(...)` sites
   does not.
3. The pointer it receives is a valid loaded address in the *wrong place*, and
   it lands inside a different literal each time. `tools/ptr_dump.py`, injected
   by `SAGE_PTR_DUMP=1`, reports the argument directly:

   | build | pointer | bytes there |
   | --- | --- | --- |
   | stock | `0x4008d317` | `b'gelet> '` -- 3 bytes into `"sagelet> "` |
   | `-mlongcalls` off | `0x4008d03f` | `b'tOS for ESP32'` -- 6 bytes into `"SageletOS for ESP32"` |

The `sage_intern_hash()` loop is `while (*s)`, so a pointer into the middle of a
literal never finds its terminator and spins. That is the whole failure: a
string-literal address is computed wrong.

**`-mlongcalls` is not the cause.** Turning it off was the obvious test -- the
image is only ~57 KB so `l32r`'s +/-256 KB reach is not needed, and long-call
expansion is what forces a distant literal pool. It changed the symptom and
fixed nothing: startup markers still all pass, the pointer is still wrong
(`0x4008d03f`), and the failure is no better. `-mlongcalls` has been restored
rather than removed, since the experiment bought nothing.

The offset is not constant either (+3, then +6), so this is not a fixed skew in
the `l32r` encoding. It is layout-dependent, and the wrong address moves around
with unrelated changes -- which is also the signature of the failure *point*
moving when the flag changed.

Ruled out by measurement, none of which changed anything:

- the toolchain and this linker script -- a four-line C file with the same flags
  and script resolves its literal exactly;
- removing `-mtext-section-literals`;
- removing `-ffunction-sections -fdata-sections`;
- merging `.iram0.rodata` into `.iram0.text` (reverted, it bought nothing);
- excluding library rodata from IRAM0 with `EXCLUDE_FILE`;
- removing `-mlongcalls`.

One solid structural observation: newlib's own code lands *inside* the runtime's
region -- `memcpy`, `memset`, `__divdf3` and `__udivdi3` sit at
`0x4008c000`-`0x4008d081` -- because `*(.text .text.*)` collects library text
into the same IRAM0 output section, so program literals and the C library's are
interleaved. Excluding library *rodata* did not help, so the mechanism is more
likely the literal-expansion machinery: the object carries 436
`R_XTENSA_ASM_EXPAND` pseudo-relocations, the assembler's `l32r`/pool expansion
hooks, which are the part that scales with code size.

Next step, now that there is a reliable probe: bisect by size. Build a cut-down
generated C -- `main` with the value-init block removed, which is known to get
the OS started -- and check whether literals resolve there. That separates "this
TU is too big" from "this construct is broken", and unlike the flag flailing it
narrows the search in one step. `tools/ptr_dump.py` makes the check a one-liner.

### Open: the second blocker

With the value-init block bypassed, the OS is entered (`hw.uart_init` runs) and
then stops before its first `hw.uart_puts`, i.e. in `led_init()` or on entry to
`repl()`. Given what A turned out to be, this is quite likely the same
misresolution in a different callee rather than an independent fault, so it
should be re-checked once literals resolve.
