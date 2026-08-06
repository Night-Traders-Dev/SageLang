## AVR instruction encoder for the ATmega328P / ATmega328PB AVR core.
##
## Encodings verified against the Microchip datasheet instruction map and the
## simavr decoder (simavr/sim/sim_core.c). All methods return either a single
## 16-bit word, or a list of words for multi-word instructions (jmp/call/lds/sts).


## ----------------------------------------------------------------------
## raw field encoders (encode direction)
## ----------------------------------------------------------------------
## Rd 5-bit field -> opcode bits 8..4
proc _d5(rd):
    return (rd & 0x1F) << 4

## Rr 5-bit field -> opcode bit 9 (value bit4) + bits 3..0
proc _r5(rr):
    return ((rr & 0x10) << 5) | (rr & 0x0F)

## Rd + Rq
proc _d5_r5(base, rd, rr):
    return base | _d5(rd) | _r5(rr)

## h (reg 16..31) -> bits 7..4 ; K high nibble @ bits 11..8, low @ 3..0
proc _h4_k8(base, rd, k):
    return base | ((rd & 0x0F) << 4) | ((k & 0xF0) << 4) | (k & 0x0F)

## 6-bit IO address -> high 2 bits @ bits 9..10, low nibble @ 3..0
proc _a6(a):
    return ((a & 0x30) << 5) | (a & 0x0F)

## 5-bit IO address -> bits 7..3
proc _io5(a):
    return (a & 0x1F) << 3

## signed 7-bit branch offset k -> bits 9..3 ; condition s -> bits 2..0
proc _br(base, k, s):
    return base | ((k & 0x7F) << 3) | (s & 7)

## 6-bit displacement q -> bit13, lines 11..10, lines 2..0
proc _q6(q):
    return ((q & 0x20) << 8) | ((q & 0x18) << 7) | (q & 0x07)

## --- register-register ALU / data ops ----------------------------------
proc enc_add(rd, rr):   return _d5_r5(0x0C00, rd, rr)
proc enc_adc(rd, rr):   return _d5_r5(0x1C00, rd, rr)
proc enc_and(rd, rr):   return _d5_r5(0x2000, rd, rr)
proc enc_eor(rd, rr):   return _d5_r5(0x2400, rd, rr)
proc enc_or(rd, rr):    return _d5_r5(0x2800, rd, rr)
proc enc_sub(rd, rr):   return _d5_r5(0x1800, rd, rr)
proc enc_sbc(rd, rr):   return _d5_r5(0x0800, rd, rr)
proc enc_cp(rd, rr):    return _d5_r5(0x1400, rd, rr)
proc enc_cpc(rd, rr):   return _d5_r5(0x0400, rd, rr)
proc enc_mov(rd, rr):   return _d5_r5(0x2C00, rd, rr)
proc enc_cpse(rd, rr):  return _d5_r5(0x1000, rd, rr)
proc enc_mul(rd, rr):   return _d5_r5(0x9C00, rd, rr)

## --- two-register special forms ----------------------------------------
proc enc_movw(rd, rr):
    return 0x0100 | (((rd >> 1) & 0x0F) << 4) | ((rr >> 1) & 0x0F)

proc enc_muls(rd, rr):
    return 0x0200 | ((rd & 0x0F) << 4) | (rr & 0x0F)

## --- register-immediate (rd 16..31) -----------------------------------
proc enc_cpi(rd, k):    return _h4_k8(0x3000, rd, k)
proc enc_sbci(rd, k):   return _h4_k8(0x4000, rd, k)
proc enc_subi(rd, k):   return _h4_k8(0x5000, rd, k)
proc enc_ori(rd, k):    return _h4_k8(0x6000, rd, k)
proc enc_andi(rd, k):   return _h4_k8(0x7000, rd, k)
proc enc_ldi(rd, k):    return _h4_k8(0xE000, rd, k)

## --- word-immediate (adiw/sbiw, pairs R24/R26/R28/R30) ----------------
proc enc_adiw(rg, k):
    return 0x9600 | ((k & 0x30) << 2) | (k & 0x0F) | (((rg - 24) >> 1) << 4)
proc enc_sbiw(rg, k):
    return 0x9700 | ((k & 0x30) << 2) | (k & 0x0F) | (((rg - 24) >> 1) << 4)

## --- single-register ops ----------------------------------------------
proc enc_inc(rd):   return 0x9403 | _d5(rd)
proc enc_dec(rd):   return 0x940A | _d5(rd)
proc enc_com(rd):   return 0x9400 | _d5(rd)
proc enc_neg(rd):   return 0x9401 | _d5(rd)
proc enc_swap(rd):  return 0x9402 | _d5(rd)
proc enc_asr(rd):   return 0x9405 | _d5(rd)
proc enc_lsr(rd):   return 0x9406 | _d5(rd)
proc enc_ror(rd):   return 0x9407 | _d5(rd)
proc enc_push(rd):  return 0x920F | _d5(rd)
proc enc_pop(rd):   return 0x900F | _d5(rd)

## --- IO / bit ops ------------------------------------------------------
proc enc_sbi(a, b):   return 0x9A00 | _io5(a) | (b & 7)
proc enc_cbi(a, b):   return 0x9800 | _io5(a) | (b & 7)
proc enc_sbis(a, b):  return 0x9B00 | _io5(a) | (b & 7)
proc enc_sbic(a, b):  return 0x9900 | _io5(a) | (b & 7)
proc enc_in(rd, a):   return 0xB000 | _d5(rd) | _a6(a)
proc enc_out(a, rr):  return 0xB800 | _d5(rr) | _a6(a)

## --- control flow ------------------------------------------------------
proc enc_rjmp(rel):   return 0xC000 | (rel & 0x0FFF)
proc enc_rcall(rel):  return 0xD000 | (rel & 0x0FFF)

## branches, base = 0xF000 (set/BRBS family) or 0xF400 (clear/BRBC family)
proc enc_breq(rel):   return _br(0xF000, rel, 1)
proc enc_brne(rel):   return _br(0xF400, rel, 1)
proc enc_brlo(rel):   return _br(0xF000, rel, 0)
proc enc_brsh(rel):   return _br(0xF400, rel, 0)
proc enc_brge(rel):   return _br(0xF400, rel, 4)
proc enc_brlt(rel):   return _br(0xF000, rel, 4)
proc enc_brmi(rel):   return _br(0xF000, rel, 2)
proc enc_brpl(rel):   return _br(0xF400, rel, 2)
proc enc_brvs(rel):   return _br(0xF000, rel, 3)
proc enc_brvc(rel):   return _br(0xF400, rel, 3)
proc enc_brcc(rel):   return _br(0xF400, rel, 0)
proc enc_brcs(rel):   return _br(0xF000, rel, 0)
proc enc_brie(rel):   return _br(0xF000, rel, 7)
proc enc_brid(rel):   return _br(0xF400, rel, 7)

## --- long jump/call (2 words; flash < 128K so single 16-bit low word) --
proc enc_jmp(addr):
    return [0x940C, addr & 0xFFFF]
proc enc_call(addr):
    return [0x940E, addr & 0xFFFF]

## --- pointer loads/stores (LDD/STD displacement) ----------------------
proc enc_ldd_z(rd, q): return 0x8000 | _d5(rd) | _q6(q)
proc enc_ldd_y(rd, q): return 0x8008 | _d5(rd) | _q6(q)
proc enc_std_z(rr, q): return 0x8000 | _d5(rr) | _q6(q)
proc enc_std_y(rr, q): return 0x8008 | _d5(rr) | _q6(q)

## --- 2-word direct load/store ------------------------------------------
proc enc_lds(rd, addr):
    return [0x9000 | _d5(rd), addr & 0xFFFF]
proc enc_sts(rr, addr):
    return [0x9200 | _d5(rr), addr & 0xFFFF]
