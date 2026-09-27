#!/usr/bin/env python3
"""Inject *sound* step markers into the emitted C.

Every previous attempt to find the hang used `volatile` byte stores as markers,
which does not work: a volatile store is ordered only against other volatile
accesses, so the compiler is free to sink one past the computation it was meant
to bracket. That produced several confident and wrong conclusions about where
the program stopped.

This tool brackets each marker with an empty asm barrier carrying a "memory"
clobber. That makes the marker a full compiler barrier in both directions:
nothing before it can be moved after it, and nothing after it can be moved
before it. The byte on the wire is therefore a truthful statement that the
function was entered, and its absence is truthful too.

Markers are two bytes: a stable id then a constant tag. Scanning for the tag
alone would trip over ordinary program output; scanning for the pair cannot.

    python3 tools/step_trace.py build/sagelet_os.c > build/sagelet_os.map.trace

Writes the id -> function name table to stdout.
"""

from __future__ import annotations

import pathlib
import re
import sys

TAG = 0x5A  # constant second byte; unlikely in UTF-8 program output

PREAMBLE = """
/* --- sound step markers, injected by tools/step_trace.py ----------------
 * Each marker is bracketed by an empty asm barrier with a memory clobber, so
 * it cannot be reordered against the code around it. That is the whole point:
 * an unbracketed volatile store can be sunk past ordinary computation, and
 * "the marker after this step is missing" then means nothing at all. */
static void __attribute__((used, noinline)) sage_step(unsigned int id) {{
    volatile unsigned int* fifo = (volatile unsigned int*)0x3FF40000u;
    volatile unsigned int* stat = (volatile unsigned int*)0x3FF4001Cu;
    volatile unsigned int  c;
    __asm__ __volatile__("" ::: "memory");
    c = id & 0xFFu;   while (((*stat >> 16) & 0xFFu) >= 128u) {{}} *fifo = c;
    c = 0x{tag:02X}u;  while (((*stat >> 16) & 0xFFu) >= 128u) {{}} *fifo = c;
    __asm__ __volatile__("" ::: "memory");
}}
"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: step_trace.py <emitted.c>", file=sys.stderr)
        return 2

    path = pathlib.Path(sys.argv[1])
    source = path.read_text()

    # Only mark definitions, not declarations or call sites: a line that opens a
    # body is one whose brace is at the end of it.
    pattern = re.compile(
        r"^(?P<head>(?:static\s+)?[A-Za-z_][A-Za-z0-9_ *]*\b"
        r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\([^;{]*\)\s*\{)\s*$",
        re.MULTILINE,
    )

    out: list[str] = []
    table: list[tuple[int, str]] = []
    index = 1  # id 0 is reserved for "got this far"

    out.append(PREAMBLE.format(tag=TAG))
    last = 0
    for match in pattern.finditer(source):
        out.append(source[last : match.start()])
        out.append(match.group("head"))
        out.append("\n    sage_step(%du);" % index)
        table.append((index, match.group("name")))
        index += 1
        last = match.end()
    out.append(source[last:])

    path.write_text("".join(out))

    print("# id  function")
    for ident, name in table:
        print("%3d  %s" % (ident, name))
    print("# marker tag byte: 0x%02X" % TAG)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
