## Two-pass AVR assembler for ATmega328P / ATmega328PB.
##
##   import avr_assembler
##   let words = avr_assembler.assemble(source_text)   # list of 16-bit words

import avr_opcodes
import dicts
import std.fmt

# ---------------------------------------------------------------------------
# string helpers
# ---------------------------------------------------------------------------
proc index_of(s, needle):
    let nl = len(needle)
    for i in range(0, len(s) - nl + 1):
        if slice(s, i, i + nl) == needle:
            return i
    return -1

proc c2i(c):
    let o = ord(c)
    if o >= 48 and o <= 57: return o - 48
    if o >= 65 and o <= 70: return o - 55
    if o >= 97 and o <= 102: return o - 87
    return 0

proc parse_int(s):
    s = strip(s)
    let neg = false
    if len(s) >= 1 and s[0] == "-":
        neg = true
        s = slice(s, 1, len(s))
    let v = 0
    if len(s) >= 2 and s[0] == "0" and s[1] == "x":
        for i in range(2, len(s)):
            v = v * 16 + c2i(s[i])
        if neg: v = 0 - v
        return v
    if len(s) >= 2 and s[0] == "0" and s[1] == "b":
        for i in range(2, len(s)):
            v = v * 2 + c2i(s[i])
        if neg: v = 0 - v
        return v
    for i in range(len(s)):
        v = v * 10 + c2i(s[i])
    if neg:
        v = 0 - v
    return v

proc parse_reg(s):
    s = lower(strip(s))
    if len(s) >= 1 and s[0] == "r":
        return parse_int(slice(s, 1, len(s)))
    return parse_int(s)

# I/O-space register names (direct 0x00..0x3F)
proc io_const(name):
    let t = lower(name)
    if t == "sreg": return 0x3f
    if t == "sph":  return 0x3e
    if t == "spl":  return 0x3d
    if t == "eearl": return 0x1d
    if t == "eearh": return 0x1e
    if t == "eedr": return 0x1f
    if t == "eecr": return 0x1c
    if t == "spmcr": return 0x37
    if t == "pinb": return 0x03
    if t == "ddrb": return 0x04
    if t == "portb": return 0x05
    if t == "pinc": return 0x06
    if t == "ddrc": return 0x07
    if t == "portc": return 0x08
    if t == "pind": return 0x09
    if t == "ddrd": return 0x0a
    if t == "portd": return 0x0b
    return nil

proc resolve_operand(s, syms, consts):
    let t = lower(strip(s))
    let io = io_const(t)
    if io != nil:
        return io
    if dicts.has(consts, t):
        return consts[t]
    return parse_int(s)

proc resolve_target(s, syms, consts):
    let t = strip(s)
    if dicts.has(syms, t):
        return syms[t]
    if dicts.has(consts, t):
        return consts[t]
    return parse_int(t)

proc size_of(op):
    if op == "jmp" or op == "call" or op == "lds" or op == "sts":
        return 2
    return 1

# ---------------------------------------------------------------------------
# tokenization -> array of dicts
# ---------------------------------------------------------------------------
proc tokenize(source_text):
    let items = []
    for raw in split(source_text, "\n"):
        let ln = strip(raw)
        let ci = index_of(ln, ";")
        if ci >= 0:
            ln = strip(slice(ln, 0, ci))
        if ln == "":
            continue

        let inst = { "kind": "instr", "op": "", "args": [], "name": "" }
        let spaces = index_of(ln, " ")

        # optional label prefix
        let lblci = index_of(ln, ":")
        if lblci > 0 and not contains(slice(ln, 0, lblci), " "):
            inst["kind"] = "label"
            inst["name"] = strip(slice(ln, 0, lblci))
            ln = strip(slice(ln, lblci + 1, len(ln)))
            if ln == "":
                push(items, inst)
                continue

        if startswith(ln, "."):
            inst["kind"] = "directive"
            let sp = index_of(ln, " ")
            if sp < 0:
                inst["op"] = lower(ln)
                inst["raw"] = ""
            else:
                inst["op"] = lower(slice(ln, 0, sp))
                inst["raw"] = strip(slice(ln, sp + 1, len(ln)))
            push(items, inst)
            continue

        # normal instruction
        if spaces < 0:
            inst["op"] = lower(ln)
            inst["args"] = []
        else:
            inst["op"] = lower(slice(ln, 0, spaces))
            inst["args"] = split(slice(ln, spaces + 1, len(ln)), ",")
        push(items, inst)
    return items

# ---------------------------------------------------------------------------
# assembler entry
# ---------------------------------------------------------------------------
proc assemble(source_text):
    let items = tokenize(source_text)

    # pass 1: symbol table + sizes  (pc is a BYTE address; size<<1 bytes)
    let syms = {}
    let consts = {}
    var pc = 0
    for it in items:
        if it["kind"] == "label":
            syms[it["name"]] = pc
        elif it["kind"] == "directive":
            if it["op"] == ".org":
                pc = parse_int(it["raw"])
        else:
            pc = pc + ((size_of(it["op"])) << 1)

    # pass 2: emit + resolve consts
    let out = []
    pc = 0
    for it in items:
        if it["kind"] == "label":
            continue
        if it["kind"] == "directive":
            let d = it["op"]
            if d == ".org":
                pc = parse_int(it["raw"])
            elif d == ".equ" or d == ".set":
                let rawr = strip(it["raw"])
                let ix = index_of(rawr, " ")
                if ix >= 0:
                    let nm = strip(slice(rawr, 0, ix))
                    let val = strip(slice(rawr, ix + 1, len(rawr)))
                    consts[nm] = resolve_operand(val, syms, consts)
                elif len(rawr) > 0:
                    consts[rawr] = 0
            elif d == ".byte":
                for b in it["args"]:
                    push(out, (resolve_operand(b, syms, consts) & 0xFF) << 8)
                pc = pc + len(it["args"])
            continue
        # instruction
        let wl = encode_instr(it, pc, syms, consts)
        for w in wl:
            push(out, w)
        pc = pc + ((size_of(it["op"])) << 1)
    return out

# ---------------------------------------------------------------------------
# encode one instruction
# ---------------------------------------------------------------------------
proc encode_instr(it, pc, syms, consts):
    let op = it["op"]
    let a = it["args"]

    if op == "nop":   return [0x0000]
    if op == "ret":   return [0x9508]
    if op == "reti":  return [0x9518]
    if op == "sleep": return [0x9588]
    if op == "wdr":   return [0x95a8]
    if op == "sei":   return [0x9478]
    if op == "cli":   return [0x94f8]
    if op == "ijmp":  return [0x9409]
    if op == "icall": return [0x9509]
    if op == "lpm":   return [0x95c8]

    if op == "add":   return [avr_opcodes.enc_add(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "adc":   return [avr_opcodes.enc_adc(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "and":   return [avr_opcodes.enc_and(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "eor":   return [avr_opcodes.enc_eor(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "or":    return [avr_opcodes.enc_or(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "sub":   return [avr_opcodes.enc_sub(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "sbc":   return [avr_opcodes.enc_sbc(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "cp":    return [avr_opcodes.enc_cp(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "cpc":   return [avr_opcodes.enc_cpc(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "mov":   return [avr_opcodes.enc_mov(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "cpse":  return [avr_opcodes.enc_cpse(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "mul":   return [avr_opcodes.enc_mul(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "movw":  return [avr_opcodes.enc_movw(parse_reg(a[0]), parse_reg(a[1]))]
    if op == "muls":  return [avr_opcodes.enc_muls(parse_reg(a[0]), parse_reg(a[1]))]

    if op == "cpi":   return [avr_opcodes.enc_cpi(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "sbci":  return [avr_opcodes.enc_sbci(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "subi":  return [avr_opcodes.enc_subi(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "ori":   return [avr_opcodes.enc_ori(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "andi":  return [avr_opcodes.enc_andi(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "ldi":   return [avr_opcodes.enc_ldi(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "ser":   return [avr_opcodes.enc_ldi(parse_reg(a[0]), 0xFF)]

    if op == "adiw":  return [avr_opcodes.enc_adiw(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "sbiw":  return [avr_opcodes.enc_sbiw(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]

    if op == "inc":   return [avr_opcodes.enc_inc(parse_reg(a[0]))]
    if op == "dec":   return [avr_opcodes.enc_dec(parse_reg(a[0]))]
    if op == "com":   return [avr_opcodes.enc_com(parse_reg(a[0]))]
    if op == "neg":   return [avr_opcodes.enc_neg(parse_reg(a[0]))]
    if op == "swap":  return [avr_opcodes.enc_swap(parse_reg(a[0]))]
    if op == "asr":   return [avr_opcodes.enc_asr(parse_reg(a[0]))]
    if op == "lsr":   return [avr_opcodes.enc_lsr(parse_reg(a[0]))]
    if op == "ror":   return [avr_opcodes.enc_ror(parse_reg(a[0]))]
    if op == "push":  return [avr_opcodes.enc_push(parse_reg(a[0]))]
    if op == "pop":   return [avr_opcodes.enc_pop(parse_reg(a[0]))]
    if op == "lsl":   return [avr_opcodes.enc_add(parse_reg(a[0]), parse_reg(a[0]))]
    if op == "rol":   return [avr_opcodes.enc_adc(parse_reg(a[0]), parse_reg(a[0]))]
    if op == "tst":   return [avr_opcodes.enc_and(parse_reg(a[0]), parse_reg(a[0]))]

    if op == "sbi":
        return [avr_opcodes.enc_sbi(resolve_operand(a[0], syms, consts), resolve_operand(a[1], syms, consts))]
    if op == "cbi":
        return [avr_opcodes.enc_cbi(resolve_operand(a[0], syms, consts), resolve_operand(a[1], syms, consts))]
    if op == "sbis":
        return [avr_opcodes.enc_sbis(resolve_operand(a[0], syms, consts), resolve_operand(a[1], syms, consts))]
    if op == "sbic":
        return [avr_opcodes.enc_sbic(resolve_operand(a[0], syms, consts), resolve_operand(a[1], syms, consts))]
    if op == "in":
        return [avr_opcodes.enc_in(parse_reg(a[0]), resolve_operand(a[1], syms, consts))]
    if op == "out":
        return [avr_opcodes.enc_out(resolve_operand(a[0], syms, consts), parse_reg(a[1]))]

    if op == "rjmp" or op == "rcall":
        let target = resolve_target(a[0], syms, consts)
        let rel = int((target - pc - 2) / 2)
        if op == "rjmp":
            return [avr_opcodes.enc_rjmp(rel)]
        return [avr_opcodes.enc_rcall(rel)]

    if op == "jmp":
        return avr_opcodes.enc_jmp(resolve_target(a[0], syms, consts) >> 1)
    if op == "call":
        return avr_opcodes.enc_call(resolve_target(a[0], syms, consts) >> 1)

    if op == "breq": return [br_word(true, 1, a[0], pc, syms, consts)]
    if op == "brne": return [br_word(false, 1, a[0], pc, syms, consts)]
    if op == "brcc": return [br_word(false, 0, a[0], pc, syms, consts)]
    if op == "brcs": return [br_word(true, 0, a[0], pc, syms, consts)]
    if op == "brsh": return [br_word(false, 0, a[0], pc, syms, consts)]
    if op == "brlo": return [br_word(true, 0, a[0], pc, syms, consts)]
    if op == "brge": return [br_word(false, 4, a[0], pc, syms, consts)]
    if op == "brlt": return [br_word(true, 4, a[0], pc, syms, consts)]
    if op == "brpl": return [br_word(false, 2, a[0], pc, syms, consts)]
    if op == "brmi": return [br_word(true, 2, a[0], pc, syms, consts)]
    if op == "brvc": return [br_word(false, 3, a[0], pc, syms, consts)]
    if op == "brvs": return [br_word(true, 3, a[0], pc, syms, consts)]
    if op == "brhs": return [br_word(true, 5, a[0], pc, syms, consts)]
    if op == "brhc": return [br_word(false, 5, a[0], pc, syms, consts)]

    if op == "lds":
        return avr_opcodes.enc_lds(parse_reg(a[0]), resolve_operand(a[1], syms, consts))
    if op == "sts":
        return avr_opcodes.enc_sts(parse_reg(a[0]), resolve_operand(a[1], syms, consts))

    return [0x0000]

proc br_word(set_flag, flag_s, opnd, pc, syms, consts):
    let target = resolve_target(opnd, syms, consts)
    let rel = int((target - pc - 2) / 2)
    let base = 0xF000
    if not set_flag:
        base = 0xF400
    return base | ((rel & 0x7F) << 3) | (flag_s & 7)