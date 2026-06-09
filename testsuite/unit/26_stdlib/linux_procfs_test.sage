gc_disable()
# EXPECT: line_split
# EXPECT: key_value_parse
# EXPECT: loadavg_parse
# EXPECT: uptime_parse
# EXPECT: cmdline_parse
# EXPECT: proc_entry_create
# EXPECT: proc_entry_codegen
# EXPECT: PASS

# Test line splitting logic
let content = "line1" + chr(10) + "line2" + chr(10) + "line3"
let lines = []
let line = ""
let i = 0
while i < len(content):
    if content[i] == chr(10):
        push(lines, line)
        line = ""
    else:
        line = line + content[i]
    i = i + 1
if line != "":
    push(lines, line)
if len(lines) == 3:
    if lines[0] == "line1":
        if lines[2] == "line3":
            print "line_split"

# Test key:value parsing (like /proc/cpuinfo)
let kv_line = "model name : Intel Core i7"
let colon_pos = -1
let j = 0
while j < len(kv_line):
    if kv_line[j] == ":":
        colon_pos = j
        break
    j = j + 1
let key = ""
let k = 0
while k < colon_pos:
    if kv_line[k] != " ":
        key = key + kv_line[k]
    k = k + 1
let val = ""
let v = colon_pos + 2
while v < len(kv_line):
    val = val + kv_line[v]
    v = v + 1
if key == "modelname":
    if val == "Intel Core i7":
        print "key_value_parse"

# Test loadavg parsing
let loadavg_str = "0.52 0.38 0.41 2/256 12345"
let parts = []
let part = ""
let la_i = 0
while la_i < len(loadavg_str):
    if loadavg_str[la_i] == " ":
        push(parts, part)
        part = ""
    else:
        part = part + loadavg_str[la_i]
    la_i = la_i + 1
if part != "":
    push(parts, part)
if len(parts) == 5:
    if parts[0] == "0.52":
        if parts[4] == "12345":
            print "loadavg_parse"

# Test uptime parsing
let uptime_str = "3600.50 1200.25"
let up_parts = []
let up_part = ""
let up_i = 0
while up_i < len(uptime_str):
    if uptime_str[up_i] == " ":
        push(up_parts, up_part)
        up_part = ""
    else:
        up_part = up_part + uptime_str[up_i]
    up_i = up_i + 1
if up_part != "":
    push(up_parts, up_part)
if len(up_parts) == 2:
    if up_parts[0] == "3600.50":
        print "uptime_parse"

# Test cmdline parsing (tab-separated since chr(0) truncates C strings)
let cmdline = "sage" + chr(9) + "--version" + chr(9) + "file.sage"
let args = []
let arg = ""
let ci = 0
while ci < len(cmdline):
    if cmdline[ci] == chr(9):
        if arg != "":
            push(args, arg)
        arg = ""
    else:
        arg = arg + cmdline[ci]
    ci = ci + 1
if arg != "":
    push(args, arg)
if len(args) == 3:
    if args[0] == "sage":
        if args[2] == "file.sage":
            print "cmdline_parse"

# Test proc entry creation
proc create_proc_entry(name, read_body):
    let entry = {}
    entry["name"] = name
    entry["read_body"] = read_body
    entry["permissions"] = 292
    return entry

let pe_body = []
push(pe_body, "seq_printf(sf, hello);")
let pe = create_proc_entry("sage_info", pe_body)
if pe["name"] == "sage_info":
    if pe["permissions"] == 292:
        print "proc_entry_create"

# Test proc entry C codegen
let nl = chr(10)
let q = chr(34)
let code = ""
code = code + "static int sage_info_show(struct seq_file *sf, void *v) {" + nl
code = code + "    return 0;" + nl
code = code + "}" + nl
code = code + "static const struct proc_ops sage_info_pops = {" + nl
code = code + "    .proc_open = sage_info_open," + nl
code = code + "    .proc_read = seq_read," + nl
code = code + "};" + nl
if contains(code, "proc_ops"):
    if contains(code, "seq_read"):
        print "proc_entry_codegen"

print "PASS"
