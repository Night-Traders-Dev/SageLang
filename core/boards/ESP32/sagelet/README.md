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

### Wrong: the literal addresses are fine. The marker method was unsound.

**This retracts the previous two commits' conclusions.** String literals resolve
correctly, and the "misresolved literal" theory is dead.

How that was settled, and why the earlier evidence was wrong:

- The probe (`tools/ptr_dump.py`) now prints *two* values: the pointer
  `sage_string_const` received, and the address of a literal defined **inside the
  probe itself**. That gives a ground-truth calibration point in the same
  translation unit, so addresses can be mapped without trusting a segment table
  or a disassembly guess.
- The received pointer was `0x4008d0e6`. The byte at that address is `0x00` -- it
  is the empty-string literal `""`.
- The disassembly confirms it: the `l32r` that loads `0x4008d0e6` is
  `sage_string_take`'s own `value == NULL ? "" : value` fallback. Entirely
  correct code.

The "+3 / +6 / +9 into a string" pattern that drove the earlier theory was an
artefact of measuring from whatever string happened to precede the address. The
empty string legitimately follows `" "`, so `start + 3` *is* the correct
address of `""`. There was never a skew.

**The marker method itself is unsound, which invalidates the localisation.**
The startup markers are `volatile` byte stores, and a volatile store may be
reordered with respect to ordinary computation -- it is only ordered against
*other* volatile accesses. So "marker at function entry appears, marker after
the hash does not" does **not** prove the hang is in the hash; the compiler is
free to sink that store past it. Every location conclusion drawn from marker
ordering in this bring-up is suspect for the same reason.

### What is still established

1. Startup reaches `sage_string_const` and stops somewhere inside it.
2. It is the string path, not allocation: neutralising only the 16
   `sage_string_const(...)` sites lets the OS start, neutralising only the 9
   `sage_make_array(...)` sites does not. Reproducible.
3. The argument it receives is a valid pointer to a valid string.
4. The GC is not involved (retested in a configuration that reaches this code).
5. `malloc` works: a probe inside `main` gets non-NULL from `malloc(64)` and
   `free()` succeeds.
6. Stack size and the memory map are ruled out.

So the remaining candidates inside `sage_string_const` are the intern-table
probe loop, or `sage_string` -> `sage_gc_copy_string` -> `sage_gc_alloc` ->
`malloc`, and the previous evidence cannot distinguish them.

### The intern probe loop is implicated (weakly)

Replacing `while (sage_intern_table[h].content != NULL) { ... }` with a single
`if` changed one run from 656 bytes of output to 2388, so control does reach
that loop. Treat this as weak: the same experiment run in another configuration
appeared to get *worse*, and both measurements were taken before the two probe
bugs described below were found. Re-run it with a sound build before relying on
it.

The apparent second failure mode — "not reproducible, alternating between a
silent hang and a 327-boot reset loop" — **was an artefact of my own probe**,
which was writing the UART status register as though it were the TX FIFO. The
same build is stable once the probe is correct. See "Three measurement errors"
below. The chip is not resetting in a loop.

The memory layout is *not* the cause, and is now verified by readback:

```
.iram0.text    0x40080000   51 KB
.iram0.rodata  0x4008ce90    3 KB
.data          0x3ffb0000    0 KB
.bss           0x3ffce000   98 KB   <- mostly the 4096-entry intern table
.heap          0x3ffe6938   72 KB
.stack         0x3fff8938   24 KB
                                    ends 0x3fffe940, limit 0x40000000
```

194 KB of the 200 KB `DRAM_HI` block, entirely inside internal SRAM. The intern
table is 4096 x 20 bytes = 80 KB, so ~80% of `.bss`, and a full sweep of it is
readable. The layout is tight -- 5 KB spare -- but not overrunning.

### What is now verified on the board

Everything below was checked against the installed Espressif headers, or measured
on the board, in one session. Treat it as the current truth.

**Peripheral addresses — all correct as written.** Checked one by one against
`soc/esp32/register/soc/*.h` in `esp32-libs/3.3.11`:

| Register | Address | Header |
| --- | --- | --- |
| UART0 FIFO | `0x3FF40000` | `uart_struct.h` index 0 |
| UART0 STATUS (`txfifo_cnt` = bits 23:16) | `0x3FF4001C` | index 7 |
| UART0 CONF0 (`clk_en` = bit 25) | `0x3FF40020` | index 8 |
| RTC_CNTL base / `WDTCONFIG0` / `WDTFEED` / `WDTWPROTECT` | `0x3FF48000` + `0x8C` / `0xA0` / `0xA4` | `rtc_cntl_reg.h` |
| TIMG0 / TIMG1 base | `0x3FF5F000` / `0x3FF60000` | `timer_group_reg.h` |
| TIMG `WDTCONFIG0` / `WDTFEED` / `WDTWPROTECT` | base + `0x48` / `0x60` / `0x64` | `timer_group_reg.h` |
| GPIO base | `0x3FF44000` | `gpio_reg.h` |

**DRAM is sound.** A write-then-readback sweep of all 98 KB of `.bss`
(`0x3FFCE000`–`0x3FFE6938`, 25 blocks of 4 KB) returns correct data in every
block. `.data` is `0x3FFB0000`–`0x3FFB012C`, heap 72 KB, stack 24 KB, ending
`0x3FFFE940` — 194 KB of the 200 KB `DRAM_HI`, inside the `0x40000000` limit.
The earlier fear that the top of `.bss` walked into unmapped space is wrong.

**The `.data` copy is required.** `_data_load` resolves to `0x4008E040`, inside
IRAM0, and the ROM prints `load:0x3FFB0000,len:300` before it jumps, so the
copy looks redundant. It is not: skipping it turns a stable boot into a 330-boot
reset loop. Keep it.

**Startup runs to completion, and C-to-C calls work.** With `-DSAGE_TRACE` the
markers print in full — `1` after the watchdog takeover, `x` after the `.bss`
clear, `x` after the `.data` copy, `x` immediately before `main()` — and a
`noinline` C function called from `reset_handler` at that point writes to the
UART correctly. So the entry stub, both stack registers, the watchdog takeover,
`.bss`, `.data` and the call mechanism are all sound.

**The board itself is healthy.** `esptool chip-id` works, and three flash reads
return identical checksums. The pure-assembly park (`SAGET_EXTRA_CFLAGS=-DSAGE_ENTRY_UART`,
which never calls C at all) emits 100 000+ bytes and then runs steadily.

**Where it stops:** the boot is stable and the OS emits no output at all.

### Three measurement errors that cost most of this session

Recorded so they are not repeated:

1. **Volatile markers do not order against ordinary computation.** A `volatile`
   store is ordered only against *other* volatile accesses, so the compiler may
   sink one past surrounding work. "The entry marker printed and the later one
   did not" therefore does not localise a hang. This invalidated every location
   claim made from marker ordering, including the one that `main()` is never
   entered — that claim came from a marker inside `main` and is **not**
   established.
2. **Defining a flag on the wrong translation unit silently does nothing.**
   Injecting `-D...` into the `sagelet_os.c` compile alone leaves `startup.c` and
   `entry.S` untouched, so `-DSAGE_SKIP_WDT`, `-DSAGE_STOP_AFTER_BSS` and
   `-DSAGE_TRACE` all did nothing until they were passed through
   `SAGET_EXTRA_CFLAGS`, which `build.sh` applies to every unit. Three bisects
   were invalid before this was spotted.
3. **A probe that writes the wrong register looks like a firmware bug.** Scratch
   probes were built using `0x3FF4001C` as the TX FIFO and `0x3FF40020` as the
   status register. `0x3FF4001C` is *STATUS*; the FIFO is `0x3FF40000`. Poking
   `txfifo_cnt` and the write-1-to-clear interrupt bits with byte values
   destabilised the chip and produced an convincing but entirely artificial
   "327-boot reset loop". The shipped `tools/ptr_dump.py` was always correct; only
   the scratch copies were wrong.

The upshot: the "non-reproducible fault" described above was mostly artefact.
The build is stable, and the remaining failure is that the OS produces no
output after startup.

### Next step

Two things are worth doing before more probing, and neither is a marker
experiment:

- Get `EXCCAUSE` and `EPC`. On this chip an unhandled exception goes to the ROM
  panic handler, which resets, so a fault presents exactly like the reset loops
  above. `rsr` is available for `exccause`, `epc1`, `ps` and `excvaddr`; only
  `EXCVECTOR` has no symbolic name, and it is set with the enable variant.
  Installing a level-1 vector table in IRAM0 is the one measurement that would
  settle what happens after `main()` is entered.
- Sound tracing. If markers are used again they need
  `__asm__ __volatile__("" ::: "memory")` fences on both sides, or a step index
  written to a RAM array and dumped afterwards. A plain `volatile` store is not
  enough, and that is what made the last three conclusions unreliable.

### Open: the second blocker

With the value-init block bypassed, the OS is entered (`hw.uart_init` runs) and
then stops before its first `hw.uart_puts`, i.e. in `led_init()` or on entry to
`repl()`. This should be re-checked once the first blocker is resolved.

