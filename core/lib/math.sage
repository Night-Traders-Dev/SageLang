# math.sage — Core math library for SageLang
# Uses comptime for constants and @inline for hot-path arithmetic.

import _math
from _math import *

# ============================================================================
# Inline arithmetic primitives
# ============================================================================

## Add two numbers
@inline
proc add(x, y):
    return x + y

## Subtract two numbers
@inline
proc sub(x, y):
    return x - y

## Multiply two numbers
@inline
proc mul(x, y):
    return x * y

## Divide two numbers
@inline
proc div(x, y):
    if y == 0:
        return 0
    return x / y

## Returns 1 if x > 0, -1 if x < 0, 0 otherwise
@inline
proc sign(x):
    if x > 0:
        return 1
    if x < 0:
        return 0 - 1
    return 0

## Returns the square of x
@inline
proc square(x):
    return x * x

## Returns the cube of x
@inline
proc cube(x):
    return x * x * x

## Linear interpolation between a and b by t
@inline
proc lerp(a, b, t):
    return a + (b - a) * t

## Binary exponentiation: base ^ exponent
proc pow_int(base, exponent):
    if exponent == 0:
        return 1
    if exponent < 0:
        return 1 / pow_int(base, 0 - exponent)

    let res = 1
    let b = base
    let e = exponent
    while e > 0:
        if e % 2 == 1:
            res = res * b
        b = b * b
        e = int(e / 2)
    return res

## Returns the factorial of n
proc factorial(n):
    if n <= 1:
        return 1

    let result = 1
    let i = 2
    while i <= n:
        result = result * i
        i = i + 1
    return result

## Returns the greatest common divisor of a and b
proc gcd(a, b):
    a = abs(a)
    b = abs(b)

    while b != 0:
        let temp = b
        b = a % b
        a = temp

    return a

## Returns the least common multiple of a and b
@inline
proc lcm(a, b):
    if a == 0 or b == 0:
        return 0
    return abs(a * b) / gcd(a, b)

## Returns the sum of a list of values
proc sum(values):
    let total_sum = 0
    for item in values:
        total_sum = total_sum + item
    return total_sum

## Returns the product of a list of values
proc product(values):
    let total_prod = 1
    for item in values:
        total_prod = total_prod * item
    return total_prod

## Returns the arithmetic mean of a list of values
@inline
proc mean(values):
    if len(values) == 0:
        return 0
    return sum(values) / len(values)

## Returns the squared distance between (x1, y1) and (x2, y2)
@inline
proc distance_sq(x1, y1, x2, y2):
    let dx = x2 - x1
    let dy = y2 - y1
    return dx * dx + dy * dy

## Returns the Euclidean distance between (x1, y1) and (x2, y2)
@inline
proc distance(x1, y1, x2, y2):
    return sqrt(distance_sq(x1, y1, x2, y2))

## Normalizes value between min_val and max_val to [0, 1]
@inline
proc normalize(value, min_val, max_val):
    if max_val == min_val:
        return 0
    return (value - min_val) / (max_val - min_val)

# ============================================================================
# Constants — evaluated at compile time
# ============================================================================

comptime:
    let PI = 3.14159265358979323846
    let E = 2.71828182845904523536

# ============================================================================
# Random number generation (Linear Congruential Generator)
# ============================================================================

# Initialize seed with a value from the native PRNG for unpredictability
let _random_seed = int(_math.random() * 4294967296.0)

comptime:
    let _LCG_A = 1664525
    let _LCG_C = 1013904223
    let _LCG_M = 4294967296

## Internal helper to generate next random seed
proc _random_next():
    _random_seed = (_random_seed * _LCG_A + _LCG_C) % _LCG_M
    return _random_seed

## Returns a random float in [0, 1)
@inline
proc random():
    return _random_next() / 4294967296.0

## Returns a random float in [min_val, max_val)
@inline
proc random_range(min_val, max_val):
    return min_val + random() * (max_val - min_val)

## Returns a random integer in [min_val, max_val]
@inline
proc random_int(min_val, max_val):
    return int(random_range(min_val, max_val + 1))

# ============================================================================
# Type conversion
# ============================================================================

# Note: abs, min, max, clamp, sqrt, floor, ceil, round, and int
# are now provided natively via _math or builtins.

@inline
proc pack64(n):
    return _math.pack64(n)

# ============================================================================
# printm() — Show math work
# ============================================================================

## Evaluates an arithmetic expression and shows the work.
## backend: "sage", "c", or "asm"
## formats: ["grade"] (default), can also include "exec", "bitwise"
proc printm(expr, backend="sage", formats=nil):
    if type(formats) == "nil":
        # Check global __MATH_WORK__ set via CLI
        let global_work = "grade"
        try:
            global_work = __MATH_WORK__
        catch e:
            global_work = "grade"
        end
        formats = split(global_work, ",")
    end
    
    let tokens = _printm_tokenize(expr)
    if len(tokens) == 0: return 0
    
    # Simple shunting-yard / evaluator for +, -, *, /
    # Precedence: * / > + -
    return _printm_eval(tokens, backend, formats)

proc _printm_tokenize(expr):
    let tokens = []
    let i = 0
    while i < len(expr):
        let c = expr[i]
        if c == " " or c == "\t" or c == "\n" or c == "\r":
            i = i + 1
            continue
        end
        if c == "+" or c == "-" or c == "*" or c == "/":
            push(tokens, c)
            i = i + 1
        elif (c >= "0" and c <= "9") or c == ".":
            let num = ""
            while i < len(expr) and ((expr[i] >= "0" and expr[i] <= "9") or expr[i] == "."):
                num = num + expr[i]
                i = i + 1
            end
            push(tokens, tonumber(num))
        else:
            i = i + 1
        end
    end
    return tokens

proc _printm_eval(tokens, backend, formats):
    # Pass 1: Handle * and /
    let i = 0
    while i < len(tokens):
        if tokens[i] == "*" or tokens[i] == "/":
            let left = tokens[i-1]
            let op = tokens[i]
            let right = tokens[i+1]
            let res = _printm_op(left, op, right, backend, formats)
            
            # Replace [left, op, right] with res
            let new_tokens = []
            let j = 0
            while j < i - 1:
                push(new_tokens, tokens[j])
                j = j + 1
            end
            push(new_tokens, res)
            j = i + 2
            while j < len(tokens):
                push(new_tokens, tokens[j])
                j = j + 1
            end
            tokens = new_tokens
            i = i - 1
        end
        i = i + 1
    end
    
    # Pass 2: Handle + and -
    let res = tokens[0]
    let j = 1
    while j < len(tokens):
        let op = tokens[j]
        let right = tokens[j+1]
        res = _printm_op(res, op, right, backend, formats)
        j = j + 2
    end
    return res

proc _printm_op(a, op, b, backend, formats):
    if backend == "c":
        if op == "+": return _math.printm_add(a, b)
        if op == "-": return _math.printm_sub(a, b)
        if op == "*": return _math.printm_mul(a, b)
        if op == "/": return _math.printm_div(a, b)
    elif backend == "asm":
        return _printm_op_asm(a, op, b, formats)
    else: # default "sage"
        return _printm_op_sage(a, op, b, formats)
    end
    return 0

proc _printm_op_sage(a, op, b, formats):
    let res = 0
    if op == "+": res = a + b
    elif op == "-": res = a - b
    elif op == "*": res = a * b
    elif op == "/": res = a / b
    end
    
    # Simple Grade-school vertical display
    let sa = str(a)
    let sb = str(b)
    let sr = str(res)
    let width = max(len(sa), max(len(sb) + 2, len(sr)))
    
    print " " * (width - len(sa)) + sa
    print op + " " + " " * (width - len(sb) - 2) + sb
    print "-" * width
    print " " * (width - len(sr)) + sr
    print ""
    return res

proc _printm_op_asm(a, op, b, formats):
    let arch = asm_arch()
    let lib = ffi_open("")
    if type(lib) == "nil":
        return _printm_op_sage(a, op, b, formats)
    end
    let printf_addr = ffi_sym_addr(lib, "printf")
    if printf_addr == 0:
        ffi_close(lib)
        return _printm_op_sage(a, op, b, formats)
    end
    
    let fmt = "  %g\n" + op + " %g\n----\n  %g\n\n"
    
    if array_contains(formats, "exec"):
        if op == "+": print "[ASM] Using ADD instruction"
        elif op == "-": print "[ASM] Using SUB instruction"
        elif op == "*": print "[ASM] Using MUL instruction"
        elif op == "/": print "[ASM] Using DIV instruction"
        end
    end

    if arch == "x86_64":
        let instr = ""
        if op == "+": instr = "addsd"
        elif op == "-": instr = "subsd"
        elif op == "*": instr = "mulsd"
        elif op == "/": instr = "divsd"
        end
        if instr != "":
            let code = "
                push %rbp
                mov %rsp, %rbp
                sub $48, %rsp
                movsd %xmm0, -8(%rbp)
                movsd %xmm1, -16(%rbp)
                cvttsd2si %xmm2, %r11
                cvttsd2si %xmm3, %rdi
                movsd -8(%rbp), %xmm0
                movsd -16(%rbp), %xmm1
                " + instr + " %xmm1, %xmm0
                movsd %xmm0, -24(%rbp)
                movsd -8(%rbp), %xmm0
                movsd -16(%rbp), %xmm1
                movsd -24(%rbp), %xmm2
                mov $3, %rax
                call *%r11
                movsd -24(%rbp), %xmm0
                leave
                ret
            "
            return asm_exec(code, "double", a, b, printf_addr, addressof_raw(fmt))
        end
    elif arch == "aarch64":
        let instr = ""
        if op == "+": instr = "fadd"
        elif op == "-": instr = "fsub"
        elif op == "*": instr = "fmul"
        elif op == "/": instr = "fdiv"
        end
        if instr != "":
            let code = "
                stp x29, x30, [sp, #-48]!
                mov x29, sp
                str d0, [sp, #16]
                str d1, [sp, #24]
                fcvtzs x4, d2
                fcvtzs x0, d3
                ldr d0, [sp, #16]
                ldr d1, [sp, #24]
                " + instr + " d2, d0, d1
                str d2, [sp, #32]
                ldr d0, [sp, #16]
                ldr d1, [sp, #24]
                blr x4
                ldr d0, [sp, #32]
                ldp x29, x30, [sp], #48
                ret
            "
            return asm_exec(code, "double", a, b, printf_addr, addressof_raw(fmt))
        end
    elif arch == "rv64":
        let instr = ""
        if op == "+": instr = "fadd.d"
        elif op == "-": instr = "fsub.d"
        elif op == "*": instr = "fmul.d"
        elif op == "/": instr = "fdiv.d"
        end
        if instr != "":
            let code = "
                addi sp, sp, -48
                sd ra, 40(sp)
                fsd fa0, 32(sp)
                fsd fa1, 24(sp)
                fcvt.l.d t0, fa2, rtz
                fcvt.l.d a0, fa3, rtz
                fld fa0, 32(sp)
                fld fa1, 24(sp)
                " + instr + " fa2, fa0, fa1
                fsd fa2, 16(sp)
                fld fa0, 32(sp)
                fld fa1, 24(sp)
                jalr t0
                fld fa0, 16(sp)
                ld ra, 40(sp)
                addi sp, sp, 48
                ret
            "
            return asm_exec(code, "double", a, b, printf_addr, addressof_raw(fmt))
        end
    end
    
    # Fallback to Sage if arch not supported or op not implemented in ASM
    return _printm_op_sage(a, op, b, formats)
