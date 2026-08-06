## Intel HEX (I8HEX) emitter for AVR flash images.
##
##   import avr_hex
##   let txt = avr_hex.emit_hex(words, base)

proc hex2(v):
    let digs = "0123456789abcdef"
    let a = (v >> 4) & 0xF
    let b = v & 0xF
    return digs[a] + digs[b]

proc hex4(v):
    return hex2((v >> 8) & 0xFF) + hex2(v & 0xFF)

proc emit_hex(words_list, base):
    let lines_out = []
    var addr = base
    var i = 0
    let n = len(words_list)
    while i < n:
        let count = n - i
        if count > 16:
            count = 16            # 16 words = 32 bytes per record
        let byte_count = count * 2
        var rec = ":" + hex2(byte_count) + hex2((addr >> 8) & 0xFF) + hex2(addr & 0xFF) + "00"
        var cksum = byte_count + ((addr >> 8) & 0xFF) + (addr & 0xFF) + 0
        var j = i
        while j < i + count:
            let w = words_list[j]
            let hi = (w >> 8) & 0xFF
            let lo = w & 0xFF
            rec = rec + hex2(hi) + hex2(lo)
            cksum = cksum + hi + lo
            j = j + 1
        let chk = (0 - cksum) & 0xFF
        rec = rec + hex2(chk)
        push(lines_out, rec)
        addr = addr + byte_count
        i = i + count
    push(lines_out, ":00000001FF")
    let result = ""
    var k = 0
    let m = len(lines_out)
    while k < m:
        if k > 0:
            result = result + "\n"
        result = result + lines_out[k]
        k = k + 1
    return result