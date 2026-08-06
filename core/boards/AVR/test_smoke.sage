## Verification: assemble a fixed program and check exact words/hex.
## Expected bytes were cross-checked against simavr/avr-gcc encodings.

import avr_assembler
import avr_hex
import io

let src = "
    ldi r16, 0x20
    out DDRB, r16
    out PORTB, r16
    call delay
    rjmp loop
delay:
    ret
loop:
    rjmp loop
"
let w = avr_assembler.assemble(src)

# expected words (delay=0x0C -> word 6; forward rjmp .+2 -> 0xC001)
let expected = [0xE200, 0xB904, 0xB905, 0x940e, 0x0006, 0xC001, 0x9508, 0xCfff]

if len(w) != len(expected):
    print("FAIL length:", len(w), "expected", len(expected))
else:
    var ok = true
    for i in range(len(w)):
        if w[i] != expected[i]:
            ok = false
            print("FAIL word", i, "got", w[i], "want", expected[i])
    if ok:
        print("ALL OK: ", len(w), "words")
        print(avr_hex.emit_hex(w, 0))