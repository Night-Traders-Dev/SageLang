import sys
import io

# Bytecode opcodes
let OP_CONSTANT       = 0
let OP_NIL            = 1
let OP_TRUE           = 2
let OP_FALSE          = 3
let OP_POP            = 4
let OP_GET_GLOBAL     = 5
let OP_DEFINE_GLOBAL  = 6
let OP_SET_GLOBAL     = 7
let OP_GET_INDEX      = 11
let OP_SET_INDEX      = 12
let OP_ADD            = 14
let OP_SUB            = 15
let OP_MUL            = 16
let OP_DIV            = 17
let OP_MOD            = 18
let OP_NEGATE         = 19
let OP_EQUAL          = 20
let OP_NOT_EQUAL      = 21
let OP_GREATER        = 22
let OP_GREATER_EQ     = 23
let OP_LESS           = 24
let OP_LESS_EQ        = 25
let OP_BIT_AND        = 26
let OP_BIT_OR         = 27
let OP_BIT_XOR        = 28
let OP_BIT_NOT        = 29
let OP_SHIFT_LEFT     = 30
let OP_SHIFT_RIGHT    = 31
let OP_NOT            = 32
let OP_TRUTHY         = 33
let OP_JUMP           = 34
let OP_JUMP_IF_FALSE  = 35
let OP_CALL           = 36
let OP_ARRAY          = 38
let OP_PRINT          = 41
let OP_RETURN         = 43
let OP_PUSH_ENV       = 44
let OP_POP_ENV        = 45
let OP_DUP            = 46
let OP_ARRAY_LEN      = 47
let OP_BREAK          = 48
let OP_CONTINUE       = 49
let OP_LOOP_BACK      = 50
let OP_DEFINE_FN      = 8
let OP_HALT           = 0xFF

class MetalVM:
    proc init(self):
        self.stack = []
        self.constants = []
        self.chunks = []
        self.globals = {}
        self.scopes = [{}]
        self.ip = 0
        self.code = []
        self.halted = false

    proc push(self, val):
        self.stack.push(val)

    proc pop(self):
        if len(self.stack) == 0: return nil
        return self.stack.pop()

    proc peek(self, dist):
        if len(self.stack) <= dist: return nil
        return self.stack[len(self.stack) - 1 - dist]

    proc read_u8(self):
        let b = self.code[self.ip]
        self.ip = self.ip + 1
        return b

    proc read_u16(self):
        let hi = self.read_u8()
        let lo = self.read_u8()
        return (hi << 8) | lo

    proc run(self, code):
        self.code = code
        self.ip = 0
        self.halted = false
        while not self.halted and self.ip < len(self.code):
            let op = self.read_u8()
            if op == OP_CONSTANT:
                let idx = self.read_u16()
                self.push(self.constants[idx])
            elif op == OP_NIL: self.push(nil)
            elif op == OP_TRUE: self.push(true)
            elif op == OP_FALSE: self.push(false)
            elif op == OP_POP: self.pop()
            elif op == OP_GET_GLOBAL:
                let name = self.constants[self.read_u16()]
                # Search scopes from top to bottom
                let found = false
                for i in range(len(self.scopes)):
                    let s = self.scopes[len(self.scopes) - 1 - i]
                    if s.has(name):
                        self.push(s[name])
                        found = true
                        break
                if not found:
                    if self.globals.has(name):
                        self.push(self.globals[name])
                    else:
                        print "Runtime Error: Undefined variable " + name
                        self.halted = true
            elif op == OP_DEFINE_GLOBAL:
                let name = self.constants[self.read_u16()]
                let val = self.pop()
                self.scopes[len(self.scopes)-1][name] = val
            elif op == OP_SET_GLOBAL:
                let name = self.constants[self.read_u16()]
                let val = self.peek(0)
                let found = false
                for i in range(len(self.scopes)):
                    let s = self.scopes[len(self.scopes) - 1 - i]
                    if s.has(name):
                        s[name] = val
                        found = true
                        break
                if not found:
                    self.globals[name] = val
            elif op == OP_ADD:
                let b = self.pop()
                let a = self.pop()
                self.push(a + b)
            elif op == OP_SUB:
                let b = self.pop()
                let a = self.pop()
                self.push(a - b)
            elif op == OP_MUL:
                let b = self.pop()
                let a = self.pop()
                self.push(a * b)
            elif op == OP_DIV:
                let b = self.pop()
                let a = self.pop()
                self.push(a / b)
            elif op == OP_EQUAL:
                let b = self.pop()
                let a = self.pop()
                self.push(a == b)
            elif op == OP_NOT_EQUAL:
                let b = self.pop()
                let a = self.pop()
                self.push(a != b)
            elif op == OP_GREATER:
                let b = self.pop()
                let a = self.pop()
                self.push(a > b)
            elif op == OP_LESS:
                let b = self.pop()
                let a = self.pop()
                self.push(a < b)
            elif op == OP_PRINT:
                print self.pop()
            elif op == OP_JUMP:
                self.ip = self.read_u16()
            elif op == OP_JUMP_IF_FALSE:
                let off = self.read_u16()
                if not self.pop(): self.ip = off
            elif op == OP_LOOP_BACK:
                self.ip = self.ip - self.read_u16()
            elif op == OP_PUSH_ENV:
                self.scopes.push({})
            elif op == OP_POP_ENV:
                self.scopes.pop()
            elif op == OP_HALT:
                self.halted = true
            elif op == 0xFF:
                self.halted = true
            else:
                print "Unknown opcode: " + str(op)
                self.halted = true

proc read_be16(bs, off):
    return (bs[off] << 8) | bs[off+1]

proc read_be32(bs, off):
    return (bs[off] << 24) | (bs[off+1] << 16) | (bs[off+2] << 8) | bs[off+3]

proc main():
    let args = sys.args()
    if len(args) < 2:
        print "Usage: sgvm <file.sgvm>"
        return

    let data = io.readbytes(args[1])
    if data == nil:
        print "Error: Could not read " + args[1]
        return

    if len(data) < 4 or chr(data[0]) != "S" or chr(data[1]) != "G" or chr(data[2]) != "V" or chr(data[3]) != "M":
        print "Error: Invalid SGVM header"
        return

    let vm = MetalVM()
    let off = 6
    let const_count = read_be16(data, off)
    off = off + 2

    for i in range(const_count):
        let type = data[off]
        off = off + 1
        if type == 1: # Number
            # Sage needs a way to read double from bytes
            # For now, placeholder or adding a helper
            # Let's assume we can't easily do it and skip or use 0
            # Wait, I can't skip it because the offset must be correct
            # Double is 8 bytes.
            vm.constants.push(0.0) # FIXME
            off = off + 8
        elif type == 3: # String
            let slen = read_be16(data, off)
            off = off + 2
            let s = ""
            for j in range(slen):
                s = s + chr(data[off + j])
            vm.constants.push(s)
            off = off + slen

    let chunk_count = read_be32(data, off)
    off = off + 4

    for i in range(chunk_count):
        let clen = read_be32(data, off)
        off = off + 4
        let chunk_code = []
        for j in range(clen):
            chunk_code.push(data[off + j])
        vm.chunks.push(chunk_code)
        off = off + clen

    for i in range(len(vm.chunks)):
        vm.run(vm.chunks[i])

main()
