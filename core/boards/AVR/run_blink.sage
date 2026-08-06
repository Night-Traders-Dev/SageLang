## Assemble examples/blink.asm -> Intel HEX and write examples/blink.hex.

import avr_assembler
import avr_hex
import io

let src = io.readfile("core/boards/AVR/examples/blink.asm")
let words = avr_assembler.assemble(src)
let hex_txt = avr_hex.emit_hex(words, 0)
io.writefile("core/boards/AVR/examples/blink.hex", hex_txt + "\n")
print("word count:", len(words))
print(hex_txt)