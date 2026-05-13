gc_disable()
# Regular expression engine
# Supports: literal, ., *, +, ?, [], [^], ^, $, |, (), \d, \w, \s, escapes

# ============================================================================
# Pattern compilation (regex string -> instruction list)
# ============================================================================

let OP_LITERAL = 1
let OP_DOT = 2
let OP_STAR = 3
let OP_PLUS = 4
let OP_QUESTION = 5
let OP_CHAR_CLASS = 6
let OP_NEG_CLASS = 7
let OP_ANCHOR_START = 8
let OP_ANCHOR_END = 9
let OP_GROUP_START = 10
let OP_GROUP_END = 11
let OP_ALT = 12
let OP_DIGIT = 13
let OP_WORD = 14
let OP_SPACE = 15
let OP_NOT_DIGIT = 16
let OP_NOT_WORD = 17
let OP_NOT_SPACE = 18

proc is_digit(c):
    let code = ord(c)
    return code >= 48 and code <= 57

proc is_word_char(c):
    let code = ord(c)
    if code >= 48 and code <= 57:
        return true
    if code >= 65 and code <= 90:
        return true
    if code >= 97 and code <= 122:
        return true
    if code == 95:
        return true
    return false

proc is_space(c):
    let code = ord(c)
    return code == 32 or code == 9 or code == 10 or code == 13

# Compile a regex pattern string into an instruction list
proc compile(pattern):
    let ops = []
    let i = 0
    while i < len(pattern):
        let c = pattern[i]
        if c == ".":
            push(ops, {"op": 2})
            i = i + 1
            continue
        if c == "^":
            push(ops, {"op": 8})
            i = i + 1
            continue
        if c == "$":
            push(ops, {"op": 9})
            i = i + 1
            continue
        if c == chr(92) and i + 1 < len(pattern):
            let nc = pattern[i + 1]
            if nc == "d":
                push(ops, {"op": 13})
            if nc == "D":
                push(ops, {"op": 16})
            if nc == "w":
                push(ops, {"op": 14})
            if nc == "W":
                push(ops, {"op": 17})
            if nc == "s":
                push(ops, {"op": 15})
            if nc == "S":
                push(ops, {"op": 18})
            if nc != "d" and nc != "D" and nc != "w" and nc != "W" and nc != "s" and nc != "S":
                push(ops, {"op": 1, "ch": nc})
            i = i + 2
            continue
        if c == "[":
            let chars = ""
            let neg = false
            i = i + 1
            if i < len(pattern) and pattern[i] == "^":
                neg = true
                i = i + 1
            while i < len(pattern) and pattern[i] != "]":
                if pattern[i] == "-" and len(chars) > 0 and i + 1 < len(pattern) and pattern[i + 1] != "]":
                    let from_code = ord(chars[len(chars) - 1])
                    let to_code = ord(pattern[i + 1])
                    let j = from_code + 1
                    while j <= to_code:
                        chars = chars + chr(j)
                        j = j + 1
                    i = i + 2
                else:
                    chars = chars + pattern[i]
                    i = i + 1
            i = i + 1
            if neg:
                push(ops, {"op": 7, "chars": chars})
            else:
                push(ops, {"op": 6, "chars": chars})
            continue
        # Quantifiers modify the previous op
        if c == "*":
            if len(ops) > 0:
                let prev = ops[len(ops) - 1]
                let wrapped = {"op": 3, "inner": prev}
                ops[len(ops) - 1] = wrapped
            i = i + 1
            continue
        if c == "+":
            if len(ops) > 0:
                let prev = ops[len(ops) - 1]
                let wrapped = {"op": 4, "inner": prev}
                ops[len(ops) - 1] = wrapped
            i = i + 1
            continue
        if c == "?":
            if len(ops) > 0:
                let prev = ops[len(ops) - 1]
                let wrapped = {"op": 5, "inner": prev}
                ops[len(ops) - 1] = wrapped
            i = i + 1
            continue
        # Default: literal character
        push(ops, {"op": 1, "ch": c})
        i = i + 1
    return ops

# ============================================================================
# Matching engine (backtracking NFA)
# ============================================================================

proc match_op(op, text, pos):
    if pos >= len(text):
        return -1
    let c = text[pos]
    let opcode = op["op"]
    if opcode == 1:
        if c == op["ch"]:
            return pos + 1
        return -1
    if opcode == 2:
        return pos + 1
    if opcode == 13:
        if is_digit(c):
            return pos + 1
        return -1
    if opcode == 16:
        if not is_digit(c):
            return pos + 1
        return -1
    if opcode == 14:
        if is_word_char(c):
            return pos + 1
        return -1
    if opcode == 17:
        if not is_word_char(c):
            return pos + 1
        return -1
    if opcode == 15:
        if is_space(c):
            return pos + 1
        return -1
    if opcode == 18:
        if not is_space(c):
            return pos + 1
        return -1
    if opcode == 6:
        let chars = op["chars"]
        let found = false
        for j in range(len(chars)):
            if not found and c == chars[j]:
                found = true
        if found:
            return pos + 1
        return -1
    if opcode == 7:
        let chars = op["chars"]
        let found = false
        for j in range(len(chars)):
            if not found and c == chars[j]:
                found = true
        if not found:
            return pos + 1
        return -1
    return -1

proc match_ops(ops, idx, text, pos):
    if idx >= len(ops):
        return pos
    let op = ops[idx]
    let opcode = op["op"]
    # Anchor start
    if opcode == 8:
        if pos == 0:
            return match_ops(ops, idx + 1, text, pos)
        return -1
    # Anchor end
    if opcode == 9:
        if pos == len(text):
            return match_ops(ops, idx + 1, text, pos)
        return -1
    # Star (greedy)
    if opcode == 3:
        let inner = op["inner"]
        # Try matching as many as possible, then backtrack
        let positions = [pos]
        let p = pos
        let max_iter = len(text) + 1
        let iter_count = 0
        while iter_count < max_iter:
            let np = match_op(inner, text, p)
            if np < 0:
                iter_count = max_iter
            else:
                push(positions, np)
                p = np
                iter_count = iter_count + 1
        # Try from longest match down
        let pi = len(positions) - 1
        while pi >= 0:
            let result = match_ops(ops, idx + 1, text, positions[pi])
            if result >= 0:
                return result
            pi = pi - 1
        return -1
    # Plus (one or more, greedy)
    if opcode == 4:
        let inner = op["inner"]
        let first = match_op(inner, text, pos)
        if first < 0:
            return -1
        let positions = [first]
        let p = first
        let max_iter = len(text) + 1
        let iter_count = 0
        while iter_count < max_iter:
            let np = match_op(inner, text, p)
            if np < 0:
                iter_count = max_iter
            else:
                push(positions, np)
                p = np
                iter_count = iter_count + 1
        let pi = len(positions) - 1
        while pi >= 0:
            let result = match_ops(ops, idx + 1, text, positions[pi])
            if result >= 0:
                return result
            pi = pi - 1
        return -1
    # Question (zero or one)
    if opcode == 5:
        let inner = op["inner"]
        let with_match = match_op(inner, text, pos)
        if with_match >= 0:
            let result = match_ops(ops, idx + 1, text, with_match)
            if result >= 0:
                return result
        return match_ops(ops, idx + 1, text, pos)
    # Simple ops
    let next_pos = match_op(op, text, pos)
    if next_pos >= 0:
        return match_ops(ops, idx + 1, text, next_pos)
    return -1

# ============================================================================
# Public API
# ============================================================================

# Test if pattern matches anywhere in text
proc search(pattern, text):
    let ops = compile(pattern)
    for i in range(len(text)):
        let result = match_ops(ops, 0, text, i)
        if result >= 0:
            let m = {}
            m["start"] = i
            m["end"] = result
            m["text"] = ""
            for j in range(result - i):
                m["text"] = m["text"] + text[i + j]
            return m
    return nil

# Test if pattern matches the entire text
proc full_match(pattern, text):
    let ops = compile(pattern)
    let result = match_ops(ops, 0, text, 0)
    if result == len(text):
        return true
    return false

# Test if pattern matches (returns boolean)
proc test(pattern, text):
    return search(pattern, text) != nil

# Find all non-overlapping matches
proc find_all(pattern, text):
    let ops = compile(pattern)
    let results = []
    let i = 0
    while i < len(text):
        let result = match_ops(ops, 0, text, i)
        if result >= 0 and result > i:
            let m = {}
            m["start"] = i
            m["end"] = result
            m["text"] = ""
            for j in range(result - i):
                m["text"] = m["text"] + text[i + j]
            push(results, m)
            i = result
        else:
            i = i + 1
    return results

# Replace first match
proc replace_first(pattern, text, replacement):
    let m = search(pattern, text)
    if m == nil:
        return text
    let result = ""
    for i in range(m["start"]):
        result = result + text[i]
    result = result + replacement
    for i in range(len(text) - m["end"]):
        result = result + text[m["end"] + i]
    return result

# Replace all matches
proc replace_all(pattern, text, replacement):
    let ops = compile(pattern)
    let result = ""
    let i = 0
    while i < len(text):
        let end_pos = match_ops(ops, 0, text, i)
        if end_pos >= 0 and end_pos > i:
            result = result + replacement
            i = end_pos
        else:
            result = result + text[i]
            i = i + 1
    return result

# Split text by pattern
proc split_by(pattern, text):
    let ops = compile(pattern)
    let parts = []
    let current = ""
    let i = 0
    while i < len(text):
        let end_pos = match_ops(ops, 0, text, i)
        if end_pos >= 0 and end_pos > i:
            push(parts, current)
            current = ""
            i = end_pos
        else:
            current = current + text[i]
            i = i + 1
    push(parts, current)
    return parts
