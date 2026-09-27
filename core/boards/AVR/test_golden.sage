#########################################################################
## AVR backend golden test — byte-exact Intel HEX output
##
## test_smoke.sage asserts on *words*, and prints the hex it produced rather
## than comparing it. That is why three real defects survived it:
##
##   * emit_hex() wrote each word high byte first, so every image it produced
##     decoded as different instructions;
##   * `sts` took its operands register-first, so `sts 0x00C5, r16` encoded as
##     `sts r5, 0x0010`;
##   * `sbrs` and `sbrc` were never implemented and fell through to nop.
##
## None of those change a single assembled word in the way test_smoke.sage
## checks, so this test compares the *emitted bytes* against payload ground
## truth taken from `avr-as` + `avr-ld`. The same .asm files under examples/
## are what GNU was run on, so there is no second copy to drift.
##
## Run from the SageLang repository root:
##   sage -I core/boards/AVR core/boards/AVR/test_golden.sage
#########################################################################

import avr_common
import avr_assembler
import avr_hex
import io

var failures = 0
var passes = 0

proc check(cond, msg):
    if cond:
        passes = passes + 1
        print("  PASS:", msg)
    else:
        failures = failures + 1
        print("  FAIL:", msg)

# ---------------------------------------------------------------- helpers

proc hexdig(c):
    let u = upper(c)
    if u >= "0" and u <= "9":
        return ord(u) - 48
    if u >= "A" and u <= "F":
        return ord(u) - 55
    return -1

## Byte value of one hex digit pair in an Intel HEX record.
proc byte_at(line, k):
    let hi = hexdig(line[k])
    let lo = hexdig(line[k + 1])
    if hi < 0 or lo < 0:
        return -1
    return hi * 16 + lo

## Parse data records into a flat address-ordered byte list.
proc parse_hex(text):
    var mem = []
    for raw in split(text, "\n"):
        let line = strip(raw)
        if len(line) < 11:
            continue
        if line[0] != ":":
            continue
        # type 00 is data; 01 is EOF and the rest are metadata
        if byte_at(line, 7) != 0:
            continue
        let count = byte_at(line, 1)
        let addr = byte_at(line, 3) * 256 + byte_at(line, 5)
        while len(mem) < addr:
            push(mem, 0xFF)
        var k = 0
        while k < count:
            push(mem, byte_at(line, 9 + 2 * k))
            k = k + 1
    return mem

## Every Intel HEX record must sum to 0 mod 256 including its checksum byte.
proc bad_checksums(text):
    var bad = 0
    for raw in split(text, "\n"):
        let line = strip(raw)
        if len(line) < 11:
            continue
        if line[0] != ":":
            continue
        var sum = 0
        var k = 1
        let n = len(line)
        while k + 1 < n:
            let b = byte_at(line, k)
            if b < 0:
                break
            sum = sum + b
            k = k + 2
        if (sum & 0xFF) != 0:
            bad = bad + 1
    return bad

proc load_source(name):
    # Works from the repository root or from inside the AVR package.
    let a = "core/boards/AVR/examples/" + name
    if io.exists(a):
        return io.readfile(a)
    let b = "examples/" + name
    if io.exists(b):
        return io.readfile(b)
    return ""

proc compare(name, expected):
    let src = load_source(name)
    if src == "":
        check(false, "found " + name)
        return
    let words = avr_assembler.assemble(src)
    let text = avr_hex.emit_hex(words, 0)

    check(bad_checksums(text) == 0, name + ": Intel HEX checksums are valid")

    let got = parse_hex(text)
    if len(got) != len(expected):
        check(false, name + ": emitted " + str(len(got)) + " bytes, expected " + str(len(expected)))
        return
    var first_bad = -1
    var k = 0
    while k < len(expected):
        if got[k] != expected[k] and first_bad < 0:
            first_bad = k
        k = k + 1
    if first_bad < 0:
        check(true, name + ": " + str(len(expected)) + " emitted bytes match GNU as/ld")
    else:
        var h = "0123456789ABCDEF"
        check(false, name + ": first mismatch at byte " + str(first_bad) +
                   " got " + h[(got[first_bad] >> 4) & 0xF] + h[got[first_bad] & 0xF] +
                   " want " + h[(expected[first_bad] >> 4) & 0xF] + h[expected[first_bad] & 0xF])

# ------------------------------------------- ground truth from avr-as/avr-ld

let GOLDEN_BRANCHES = [
    0x00, 0xE0, 0x01, 0xC0, 0xFF, 0xCF, 0x17, 0xD0, 0xF1, 0xF3, 0xE9, 0xF7,
    0xE0, 0xF3, 0xD8, 0xF7, 0xD0, 0xF3, 0xC8, 0xF7, 0xC4, 0xF3, 0xBC, 0xF7,
    0xB2, 0xF3, 0xAA, 0xF7, 0xA3, 0xF3, 0x9B, 0xF7, 0x95, 0xF3, 0x8D, 0xF7,
    0x02, 0xFF, 0x02, 0xFD, 0x29, 0x9B, 0x29, 0x99, 0x0C, 0x94, 0x1B, 0x00,
    0x0E, 0x94, 0x1B, 0x00, 0x02, 0xC0, 0x15, 0xE5, 0x08, 0x95, 0xFF, 0xCF
]

let GOLDEN_COVERAGE = [
    0x00, 0xE2, 0xFF, 0xEF, 0x01, 0x0F, 0x01, 0x1F, 0x01, 0x23, 0x01, 0x27,
    0x01, 0x2B, 0x01, 0x1B, 0x01, 0x0B, 0x01, 0x17, 0x01, 0x07, 0x01, 0x2F,
    0x01, 0x13, 0x01, 0x9F, 0x9B, 0x01, 0x45, 0x02, 0x00, 0x31, 0x01, 0x41,
    0x02, 0x51, 0x00, 0x62, 0x0F, 0x70, 0x03, 0x96, 0x12, 0x97, 0x03, 0x95,
    0x0A, 0x95, 0x00, 0x95, 0x01, 0x95, 0x02, 0x95, 0x05, 0x95, 0x06, 0x95,
    0x07, 0x95, 0x0F, 0x93, 0x1F, 0x91, 0x2B, 0x9A, 0x2B, 0x98, 0x2B, 0x9B,
    0x2B, 0x99, 0x05, 0xFF, 0x13, 0xFD, 0x00, 0xFE, 0xF7, 0xFD, 0x0D, 0xB7,
    0x0E, 0xBF, 0x00, 0x00, 0x08, 0x95, 0x18, 0x95, 0x88, 0x95, 0xA8, 0x95,
    0x78, 0x94, 0xF8, 0x94, 0x09, 0x94, 0x09, 0x95, 0xC8, 0x95, 0x00, 0x0F,
    0x00, 0x1F, 0x00, 0x23, 0x2F, 0xEF, 0x00, 0x91, 0x00, 0x01, 0x10, 0x91,
    0xC0, 0x00, 0x20, 0x93, 0xC6, 0x00, 0x30, 0x93, 0x00, 0x01
]

let GOLDEN_BITSKIP = [
    0x15, 0xFF, 0x15, 0xFD, 0x00, 0xFE, 0xF7, 0xFD,
    0x2B, 0x9B, 0x2B, 0x99, 0x07, 0xFF, 0x01, 0xFD
]

# ------------------------------------------------------------------- tests

print("== emitted bytes vs GNU as/ld ==")
compare("branches.asm", GOLDEN_BRANCHES)
compare("coverage.asm", GOLDEN_COVERAGE)
compare("bitskip.asm", GOLDEN_BITSKIP)

## The endianness defect in particular: the first word of coverage.asm is
## `ldi r16, 0x20` = 0xE200, which must reach the file as 00 E2.
print("== byte order ==")
let cov = load_source("coverage.asm")
if cov == "":
    check(false, "coverage.asm readable")
else:
    let first = parse_hex(avr_hex.emit_hex(avr_assembler.assemble(cov), 0))
    check(len(first) >= 2 and first[0] == 0x00 and first[1] == 0xE2,
          "words are emitted low byte first (ldi r16,0x20 -> 00 E2)")

## `sts k, Rd` takes the address first, matching the AVR manual and GNU as.
## A register-first reading would emit 30 93 05 00 (addr 0x0010, reg r5).
print("== sts operand order ==")
let sts_words = avr_assembler.assemble("    ldi r16, 0x00\n    sts 0x00C5, r16\n")
let sts_bytes = parse_hex(avr_hex.emit_hex(sts_words, 0))
check(len(sts_bytes) >= 4 and sts_bytes[2] == 0x00 and sts_bytes[3] == 0x93
          and sts_bytes[4] == 0xC5 and sts_bytes[5] == 0x00,
      "sts 0x00C5, r16 keeps the address 0x00C5 and register r16")

## The assembler used to have no error path at all, which is how `sts 0x00C5,
## r16` became `sts r5, 0x0010` and how sbrs/sbrc became nops. Both classes of
## mistake have to be *rejected*, not merely absent from the examples.
proc expect_rejected(src, label):
    var rejected = false
    try:
        avr_assembler.assemble(src)
    catch e:
        rejected = true
    check(rejected, label)

print("== malformed input is rejected, not guessed ==")
expect_rejected("    sts r16, 0x00C5\n",
                "sts written register-first is rejected, not mis-encoded")
expect_rejected("    mov 0x10, r16\n",
                "a hex literal in a register field is rejected")
expect_rejected("    ldi r99, 0x20\n",
                "a register above r31 is rejected")
expect_rejected("    mov r16x, r1\n",
                "a register with trailing junk is rejected")
expect_rejected("    frobnicate r16\n",
                "an unknown mnemonic is rejected rather than emitting a nop")
expect_rejected("    sbrs r16\n",
                "a missing operand is rejected")

## And the well-formed forms still assemble.
proc expect_accepted(src, label):
    var ok = true
    try:
        avr_assembler.assemble(src)
    catch e:
        ok = false
    check(ok, label)

print("== well-formed input still assembles ==")
expect_accepted("    sts 0x00C5, r16\n", "sts with address first is accepted")
expect_accepted("    lds r17, 0x00C0\n", "lds with register first is accepted")
expect_accepted("    sbrs r17, 5\n", "sbrs is accepted")
expect_accepted("    sbrc r0, 0\n", "sbrc with r0 is accepted")
expect_accepted("    mov r16, r1\n", "a bare decimal register is still accepted")

## The package entry point declared in __init__.sage could not be imported at
## all: AsmError used `def` for its methods, which SageLang rejects, so
## `import avr_common` failed. It was never noticed because every test imports
## the modules directly and never touches the package.
print("== the AVR package imports ==")
check(str(avr_common.AsmError("boom", 12)) == "error at line 12: boom",
      "AsmError formats with its line number")
check(str(avr_common.AsmError("boom")) == "boom",
      "AsmError without a line omits the prefix")

## Diagnostics must say *where* the problem is, not just what it is.
proc expect_error_at(src, want_line, label):
    var got_line = 0
    var got_msg = ""
    try:
        avr_assembler.assemble(src)
    catch e:
        got_msg = str(e)
        got_line = e.line
    check(got_line == want_line and contains_line(got_msg, want_line),
          label + " (reported line " + str(got_line) + ")")

proc contains_line(msg, n):
    return contains(msg, "error at line " + str(n) + ":")

print("== diagnostics cite the source line ==")
expect_error_at("    ldi r16, 0x00\n    ldi r17, 0x01\n    frobnicate r16\n", 3,
                "unknown mnemonic is reported on its own line")
expect_error_at("    nop\n    nop\n    nop\n    ldi r16, r5\n", 4,
                "a register in an operand position is reported on its line")
expect_error_at("    nop\n    ldi r99, 0x20\n", 2,
                "an out-of-range register cites line 2")
expect_error_at("    nop\n    nop\n    sbrs r16\n", 3,
                "a missing operand cites line 3")
## Comments and blank lines must not shift the count.
expect_error_at("    nop\n\n    ; a comment\n\n    ldi r16, r5\n", 5,
                "blank lines and comments are counted correctly")

print("")
print("Results:", passes, "passed,", failures, "failed")
if failures == 0:
    print("ALL OK")
