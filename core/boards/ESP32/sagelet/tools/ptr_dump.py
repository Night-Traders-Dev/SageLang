#!/usr/bin/env python3
"""Dump the pointer sage_string_const() receives, straight to the UART.

Diagnostic for the ESP32 bring-up, injected by build.sh when SAGE_PTR_DUMP=1.
The generated C is the only place the resolved literal address is observable
without guessing, and guessing has been wrong twice: the address a literal
*should* have resolved to is not recoverable from disassembly by inspection,
because picking "the nearest preceding l32r" picks a neighbouring call's pool
word. So the program reports what it actually got.

Emits eight bytes, little-endian, before anything else in the function:

    bytes 0..3   the pointer sage_string_const() actually received
    bytes 4..7   the address of a literal defined right here in the probe

The second value is the reference point. Attributing a pool word to a specific
call site from disassembly is unreliable -- that has been wrong twice -- but a
literal defined inside the probe is unambiguous: it goes through the same
assembler, the same literal pool and the same linker, in the same translation
unit, so the difference between the two printed values is the skew directly,
with no guessing about which literal "should" have been passed.
"""
import sys

UART_FIFO = 0x3FF40000
UART_STATUS = 0x3FF4001C

NEEDLE = 'static SageValue sage_string_const(const char* value) {\n    if (value == NULL) value = "";'
REPLACEMENT = f"""static const char sage_probe_literal[] = "SAGEPROBE";

static SageValue sage_string_const(const char* value) {{
    {{
        volatile unsigned long v = (volatile unsigned long)value;
        volatile char* fp = (volatile char*){UART_FIFO};
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)(v & 0xFFu);
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)((v >> 8) & 0xFFu);
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)((v >> 16) & 0xFFu);
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)((v >> 24) & 0xFFu);
        v = (volatile unsigned long)sage_probe_literal;
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)(v & 0xFFu);
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)((v >> 8) & 0xFFu);
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)((v >> 16) & 0xFFu);
        while ((*(volatile unsigned*){UART_STATUS} >> 16 & 0xFFu) >= 128u) {{}}
        *fp = (char)((v >> 24) & 0xFFu);
    }}
    if (value == NULL) value = "";"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: ptr_dump.py <generated.c>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    text = open(path).read()
    if NEEDLE not in text:
        print("ptr_dump.py: sage_string_const prologue not found; "
              "the emitter's output shape must have changed", file=sys.stderr)
        return 1
    open(path, "w").write(text.replace(NEEDLE, REPLACEMENT, 1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
