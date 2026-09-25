#!/usr/bin/env python3
"""gen_partitions.py — build an ESP32 partition table image.

The format is fixed by the chip: a sequence of 32-byte entries, each

    offset  size  field
    0       2     magic 0x50AA (little endian, i.e. bytes AA 50)
    2       1     type:  0x00 app, 0x01 data, 0x02 bootloader
    3       1     subtype (meaning depends on type)
    4       4     flash offset, 0x10000 aligned
    8       4     size in bytes, 0x10000 aligned
    12      16    label, ASCII, NUL padded
    28      4     flags

terminated by an entry whose type byte is 0xFF. This is the same layout the
Espressif partition-gen tool emits, and the same one boot.sage walks.

Usage: gen_partitions.py <out.bin> [spec ...]
  spec: name:type:subtype:offset:size   (offset/size accept 0x hex)
"""
import struct
import sys

# type codes
T_APP, T_DATA = 0x00, 0x01
# data subtypes
D_OTA, D_NVS, D_SPIFFS, D_COREDUMP = 0x00, 0x02, 0x04, 0x03
# app subtypes
A_OTA = 0x10

DATA_SUBTYPES = {
    "ota": D_OTA, "nvs": D_NVS, "spiffs": D_SPIFFS, "coredump": D_COREDUMP,
}
APP_SUBTYPES = {"ota": A_OTA, "factory": 0x00, "test": 0x01}

# The layout SageletOS expects: a small NVS, OTA bookkeeping, then the app
# where our bootloader looks for it.
DEFAULT_SPEC = [
    "nvs:data:nvs:0x9000:0x5000",
    "otadata:data:ota:0xe000:0x2000",
    "app:app:ota:0x10000:0x140000",   # app subtypes: factory=0, ota_0=0x10
]


def align_up(value, alignment=0x10000):
    return (value + alignment - 1) & ~(alignment - 1)


def encode(name, ptype, subtype, offset, size):
    label = name.encode("ascii")[:16]
    label = label + b"\x00" * (16 - len(label))
    return struct.pack("<HBBII16sI", 0x50AA, ptype, subtype,
                       offset, size, label, 0)


def parse_spec(spec):
    parts = spec.split(":")
    if len(parts) != 5:
        raise SystemExit(f"bad spec {spec!r}: want name:type:subtype:offset:size")
    name, tname, sname, off, size = parts
    off_i = int(off, 0)
    size_i = int(size, 0)
    if tname == "app":
        if sname not in APP_SUBTYPES:
            raise SystemExit(f"unknown app subtype {sname!r}")
        return name, T_APP, APP_SUBTYPES[sname], off_i, size_i
    if tname == "data":
        if sname not in DATA_SUBTYPES:
            raise SystemExit(f"unknown data subtype {sname!r}")
        return name, T_DATA, DATA_SUBTYPES[sname], off_i, size_i
    raise SystemExit(f"unknown type {tname!r} (want 'app' or 'data')")


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    out_path = sys.argv[1]
    specs = sys.argv[2:] or DEFAULT_SPEC

    entries = [parse_spec(s) for s in specs]

    # Alignment rules: the table lives at 0x8000 (4 KiB aligned). App
    # partitions must start on a 0x10000 boundary because the image header's
    # 24-bit offset field and the MMU page mapping assume it; data partitions
    # only need 4 KiB, which is why nvs can sit at 0x9000.
    occupied = []
    for name, ptype, _s, off, size in entries:
        align = 0x10000 if ptype == T_APP else 0x1000
        if off % align:
            raise SystemExit(f"{name}: offset 0x{off:x} is not 0x{align:x} aligned")
        if size % 0x1000:
            raise SystemExit(f"{name}: size 0x{size:x} is not 4 KiB aligned")
        for oname, ooff, osize in occupied:
            if off < ooff + osize and ooff < off + size:
                raise SystemExit(f"{name} overlaps {oname}")
        occupied.append((name, off, size))

    blob = b"".join(encode(*e) for e in entries)
    # Terminator: a single entry with type 0xFF.
    blob += struct.pack("<HBBII16sI", 0xFFFF, 0xFF, 0xFF, 0, 0, b"\x00" * 16, 0)

    with open(out_path, "wb") as fh:
        fh.write(blob)

    print(f"wrote {out_path} ({len(blob)} bytes, {len(entries)} entries)")
    for name, t, s, off, size in entries:
        tname = "app " if t == T_APP else "data"
        print(f"  {name:<10} {tname} sub=0x{s:02x} off=0x{off:06x} size=0x{size:06x}")


if __name__ == "__main__":
    main()
