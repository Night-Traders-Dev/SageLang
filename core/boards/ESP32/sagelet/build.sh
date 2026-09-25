#!/usr/bin/env bash
# build.sh — build the Sagelet ESP32 images from SageLang sources.
#
# Pipeline per image:
#   1. sage --emit-pico-c  ->  self-contained C with `static` stubs for every
#      `hw.*` native
#   2. rewrite that stub block into #include "esp32_hal.h", so the real HAL
#      definitions take their place (they are non-static and would otherwise
#      collide with the stubs)
#   3. xtensa-esp32-elf-gcc -nostdlib + our own newlib shim + newlib
#   4. esptool elf2image -> flashable .bin with the ESP32 image header
#
# Usage: bash core/boards/ESP32/sagelet/build.sh [app|boot|all]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
OUT="$HERE/build"

# --- toolchain -------------------------------------------------------------
find_toolchain() {
    if command -v xtensa-esp32-elf-gcc >/dev/null 2>&1; then
        echo "xtensa-esp32-elf-gcc"
        return
    fi
    local base="$HOME/.arduino15/packages/esp32/tools/esp-x32"
    if [ -d "$base" ]; then
        local cand
        cand="$(find "$base" -maxdepth 2 -name bin -type d 2>/dev/null | sort | tail -1)"
        if [ -n "$cand" ]; then
            echo "$cand"
            return
        fi
    fi
    echo ""
}

TC_BIN="$(find_toolchain)"
if [ -z "$TC_BIN" ]; then
    echo "error: xtensa-esp32-elf-gcc not found." >&2
    echo "       install the Arduino ESP32 core (arduino-cli core install esp32:esp32)" >&2
    exit 1
fi
CC="$TC_BIN/xtensa-esp32-elf-gcc"
SIZE="$TC_BIN/xtensa-esp32-elf-size"
OBJCOPY="$TC_BIN/xtensa-esp32-elf-objcopy"

SAGE="$ROOT/core/sage"
if [ ! -x "$SAGE" ]; then
    echo "error: $SAGE not built. Run ./sagemake first." >&2
    exit 1
fi

ESPTOOL="${ESPTOOL:-python3 -m esptool}"

mkdir -p "$OUT"

# --- step 2: swap the emitted stub block for the real HAL ------------------
rewrite_stubs() {
    local in_c="$1" out_c="$2"
    python3 - "$in_c" "$out_c" <<'PY'
import re, sys, pathlib

src = pathlib.Path(sys.argv[1]).read_text()

def strip_pico_includes(text):
    # The emitter adds Pico/SDK headers that mean nothing on ESP32; the HAL
    # supplies the real declarations. This is the "adapt prog.c" step that
    # core/docs/esp32.md describes.
    return re.sub(r'^#include "(pico|hardware)/[^"]*"$',
                  '/* removed Pico/SDK include */', text, flags=re.M)

def find_block(text, start):
    """Return (end_index_inclusive, n) for the #if/#endif group starting at
    the first #if at or after `start`, tracking nesting."""
    lines = text.split("\n")
    off = sum(len(l) + 1 for l in lines[:start])
    del off
    # Work on offsets.
    i = start
    depth = 0
    began = False
    while i < len(text):
        nl = text.find("\n", i)
        if nl < 0:
            nl = len(text)
        line = text[i:nl].strip()
        if line.startswith("#if"):
            depth += 1
            began = True
        elif line.startswith("#endif"):
            depth -= 1
            if began and depth == 0:
                return nl
        i = nl + 1
    return len(text) - 1

# --- 1. the hw block becomes the real HAL --------------------------------
marker = "/* --- hw module: hardware access (implementation defined per target) --- */"
i = src.find(marker)
if i < 0:
    out = strip_pico_includes(src)
else:
    j = src.find("#if", i)
    end = find_block(src, j)
    tail_start = src.find("\n", end) + 1
    out = (src[:i]
           + '/* --- hw module: hardware access (implementation defined per target) --- */\n'
           + '/* Rewritten by build.sh: the emitted stubs are replaced by the real\n'
           + ' * bare-metal ESP32 HAL. */\n'
           + '#include "esp32_hal.h"\n'
           + src[tail_start:])

# --- 2. hosted thread/sys natives have no bare-metal equivalent ----------
# A single-core image has no pthreads and no hosted clock, and the emitted
# branches reference pthread_self(), nanosleep(), clock() and the Pico SDK.
# Neutralize those groups rather than pulling a hosted libc onto the target.
def kill_group(m):
    body = m.group(0)
    if "sage_native_hw_" in body:
        return body
    if ("sage_native_thread_" in body) or ("sage_native_sys_" in body):
        return "/* Rewritten by build.sh: hosted thread/sys natives are not "\
               "available bare-metal; a single-core image does without them. */"
    # POSIX semaphores: this newlib has no <semaphore.h>, and a single-core
    # image has nothing to synchronise. Keep the stubs, drop the real ones.
    if "sage_sem_" in body:
        stubs = "\n".join(l for l in body.split("\n")
                          if "sage_sem_" in l and l.strip().startswith("static")
                          and "sem_" in l.split("sage_sem_", 1)[1])
        return ("/* Rewritten by build.sh: POSIX semaphores are unavailable "\
                "bare-metal. */\n" + stubs)
    return body

out = re.sub(r'#if !defined\(PICO_ON_DEVICE\)(?:.|\n)*?#endif', kill_group, out)

out = strip_pico_includes(out)

# The emitted runtime uses C11 atomics for its GC bookkeeping; on the Pico
# target those come in through <pico/stdlib.h>, which we just removed. Put the
# real header in at the top, where the atomics are first used (line ~120, long
# before the HAL include near the end of the file).
if "#include <stdatomic.h>" not in out:
    lines = out.split("\n")
    last = 0
    for idx, line in enumerate(lines[:80]):
        if line.startswith("#include"):
            last = idx
    lines.insert(last + 1, "#include <stdatomic.h>")
    out = "\n".join(lines)

pathlib.Path(sys.argv[2]).write_text(out)
print("    hw block replaced; Pico includes, hosted thread/sys groups and POSIX semaphores stripped")
PY
}

# --- one image -------------------------------------------------------------
# build_image <sage-src> <ld-script> <prefix> <load-addr> <text-addr>
build_image() {
    local src="$1" ld="$2" prefix="$3" load="$4" text="$5"
    local stem; stem="$(basename "$src" .sage)"

    echo "==> $prefix ($stem.sage)"

    echo "  [1/5] emit C"
    "$SAGE" --emit-pico-c "$src" -o "$OUT/$prefix.raw.c"

    echo "  [2/5] rewrite hw stubs"
    rewrite_stubs "$OUT/$prefix.raw.c" "$OUT/$prefix.c"

    echo "  [3/5] compile"
    "$CC" \
        -mlongcalls -mtext-section-literals \
        -ffunction-sections -fdata-sections \
        -nostdlib \
        -Os -g \
        -Wall -Wno-unused-function -Wno-unused-variable \
        -Wno-format-truncation \
        -I"$HERE/hal" \
        -DTARGET_ESP32=1 -DUART_CLK_HZ=80000000 \
        -c "$OUT/$prefix.c" -o "$OUT/$prefix.o"
    "$CC" -mlongcalls -mtext-section-literals -Os -I"$HERE/hal" -c "$HERE/hal/esp32_hal.c"  -o "$OUT/hal_$prefix.o"
    "$CC" -mlongcalls -mtext-section-literals -Os -I"$HERE/hal" -c "$HERE/hal/esp32_newlib.c" -o "$OUT/newlib_$prefix.o"
    "$CC" -mlongcalls -mtext-section-literals -Os -I"$HERE/hal" -c "$HERE/hal/startup.c"    -o "$OUT/startup_$prefix.o"

    echo "  [4/5] link (load $load, text $text)"
    "$CC" -mlongcalls -nostartfiles -T "$ld" \
        -Wl,--gc-sections \
        -Wl,-Map,"$OUT/$prefix.map" \
        "$OUT/startup_$prefix.o" "$OUT/$prefix.o" \
        "$OUT/hal_$prefix.o" "$OUT/newlib_$prefix.o" \
        -Wl,--start-group -lc -lm -lgcc -Wl,--end-group \
        -o "$OUT/$prefix.elf"

    "$SIZE" "$OUT/$prefix.elf" | sed 's/^/    /'

    echo "  [5/5] elf2image"
    $ESPTOOL --chip esp32 elf2image \
        --flash-mode dio --flash-freq 40m --flash-size 4MB \
        --output "$OUT/$prefix.bin" "$OUT/$prefix.elf"
}

TARGET="${1:-all}"

if [ "$TARGET" = "all" ] || [ "$TARGET" = "app" ]; then
    build_image "$HERE/os.sage" "$HERE/hal/linker_app.ld" "sagelet_os" 0x10000 0x3FFB0000
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "boot" ]; then
    build_image "$HERE/boot.sage" "$HERE/hal/linker_boot.ld" "sagelet_boot" 0x1000 0x3FFB0000
fi

echo
echo "built:"
ls -l "$OUT"/*.bin 2>/dev/null | sed 's/^/  /'
