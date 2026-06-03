import sys
import io

# Accumulator for output bytes
let output_bytes = []

proc write_byte(b):
    output_bytes.push(b & 0xFF)

proc write_string(s):
    for i in range(len(s)):
        write_byte(ord(s[i]))

proc write_be16(v):
    write_byte((v >> 8) & 0xFF)
    write_byte(v & 0xFF)

proc write_be32(v):
    write_byte((v >> 24) & 0xFF)
    write_byte((v >> 16) & 0xFF)
    write_byte((v >> 8) & 0xFF)
    write_byte(v & 0xFF)

proc hex_to_byte(h):
    let chars = "0123456789abcdef"
    let v1 = 0
    let v2 = 0
    let c1 = h[0]
    let c2 = h[1]
    
    if ord(c1) >= 65 and ord(c1) <= 70: c1 = chr(ord(c1) + 32)
    if ord(c2) >= 65 and ord(c2) <= 70: c2 = chr(ord(c2) + 32)

    for i in range(16):
        if chars[i] == c1: v1 = i
        if chars[i] == c2: v2 = i
    
    return (v1 << 4) | v2

proc create_const(type, val):
    let c = {}
    c["type"] = type
    if type == 1:
        c["num"] = val
    else:
        c["str"] = val
    return c

let global_consts = []

proc add_const_num(d):
    for i in range(len(global_consts)):
        if global_consts[i]["type"] == 1 and global_consts[i]["num"] == d:
            return i
    global_consts.push(create_const(1, d))
    return len(global_consts) - 1

proc add_const_str(s):
    for i in range(len(global_consts)):
        if global_consts[i]["type"] == 3 and global_consts[i]["str"] == s:
            return i
    global_consts.push(create_const(3, s))
    return len(global_consts) - 1

proc split_lines(s):
    let lines = []
    let current = ""
    let nl = chr(10)
    for i in range(len(s)):
        if s[i] == nl:
            lines.push(current)
            current = ""
        else:
            current = current + s[i]
    if len(current) > 0:
        lines.push(current)
    return lines

proc main():
    let args = sys.args()
    if len(args) < 3:
        print "Usage: sgvmc <input.sage> <output.sgvm>"
        return

    let input_file = args[1]
    let output_file = args[2]

    let tmp_svm = ".tmp.svm"
    let cmd = "./core/sage --emit-vm " + input_file + " -o " + tmp_svm
    sys.exec(cmd)

    let content = io.readfile(tmp_svm)
    if content == nil:
        print "Error: Could not read " + tmp_svm
        return

    let lines = split_lines(content)
    let chunk_count = 0
    let local_to_global = []
    let current_chunk = -1

    let i = 0
    while i < len(lines):
        let line = lines[i]
        if line.starts_with("chunks "):
            chunk_count = int(line.substring(7, len(line)))
        elif line == "chunk":
            current_chunk = current_chunk + 1
            local_to_global.push([])
            for j in range(256): local_to_global[current_chunk].push(0)
        elif line.starts_with("constants "):
            let count = int(line.substring(10, len(line)))
            for j in range(count):
                i = i + 1
                let cl = lines[i]
                if cl.starts_with("number "):
                    local_to_global[current_chunk][j] = add_const_num(float(cl.substring(7, len(cl))))
                elif cl.starts_with("string "):
                    let slen = int(cl.substring(7, len(cl)))
                    i = i + 1
                    let hex = lines[i]
                    let s = ""
                    for k in range(slen):
                        s = s + chr(hex_to_byte(hex.substring(k*2, k*2+2)))
                    local_to_global[current_chunk][j] = add_const_str(s)
        i = i + 1

    write_string("SGVM")
    write_byte(0x01)
    write_byte(0x00)

    write_be16(len(global_consts))
    for i in range(len(global_consts)):
        let c = global_consts[i]
        write_byte(c["type"])
        if c["type"] == 1:
            for j in range(8): write_byte(0) # FIXME: Pack double
        else:
            write_be16(len(c["str"]))
            write_string(c["str"])

    write_be32(chunk_count)
    
    # Second pass for code
    current_chunk = -1
    i = 0
    while i < len(lines):
        let line = lines[i]
        if line == "chunk":
            current_chunk = current_chunk + 1
        elif line.starts_with("code "):
            let clen = int(line.substring(5, len(line)))
            write_be32(clen)
            i = i + 1
            let hex = lines[i]
            let j = 0
            while j < clen * 2:
                let op = hex_to_byte(hex.substring(j, j + 2))
                write_byte(op)
                j = j + 2
                if op == 0 or op == 5 or op == 6 or op == 7 or op == 8 or op == 9 or op == 10 or op == 34 or op == 35 or op == 36 or op == 37 or op == 38 or op == 39 or op == 40 or op == 50:
                    if op == 0 or op == 5 or op == 6 or op == 7:
                        let local_idx = (hex_to_byte(hex.substring(j, j+2)) << 8) | hex_to_byte(hex.substring(j+2, j+4))
                        let g_idx = local_to_global[current_chunk][local_idx]
                        write_byte((g_idx >> 8) & 0xFF)
                        write_byte(g_idx & 0xFF)
                    else:
                        write_byte(hex_to_byte(hex.substring(j, j+2)))
                        write_byte(hex_to_byte(hex.substring(j+2, j+4)))
                    j = j + 4
        i = i + 1
    
    io.writebytes(output_file, output_bytes)
    print "Compiled " + input_file + " to " + output_file

main()
