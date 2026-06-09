gc_disable()
# EXPECT: io_cmd
# EXPECT: ior_cmd
# EXPECT: iow_cmd
# EXPECT: iowr_cmd
# EXPECT: ioctl_set
# EXPECT: header_gen
# EXPECT: handler_gen
# EXPECT: PASS

# Direction constants
let IOC_NONE = 0
let IOC_WRITE = 1
let IOC_READ = 2
let IOC_READWRITE = 3

# _IO(type, nr)
proc io_cmd(cmd_type, nr):
    let type_val = ord(cmd_type)
    return (IOC_NONE * 1073741824) + (type_val * 256) + nr

# _IOR(type, nr, size)
proc ior_cmd(cmd_type, nr, size):
    let type_val = ord(cmd_type)
    return (IOC_READ * 1073741824) + (size * 65536) + (type_val * 256) + nr

# _IOW(type, nr, size)
proc iow_cmd(cmd_type, nr, size):
    let type_val = ord(cmd_type)
    return (IOC_WRITE * 1073741824) + (size * 65536) + (type_val * 256) + nr

# _IOWR(type, nr, size)
proc iowr_cmd(cmd_type, nr, size):
    let type_val = ord(cmd_type)
    return (IOC_READWRITE * 1073741824) + (size * 65536) + (type_val * 256) + nr

# Test _IO
let cmd0 = io_cmd("S", 0)
let s_ord = ord("S")
if cmd0 == s_ord * 256:
    print "io_cmd"

# Test _IOR
let cmd1 = ior_cmd("S", 1, 4)
let expected_ior = (2 * 1073741824) + (4 * 65536) + (s_ord * 256) + 1
if cmd1 == expected_ior:
    print "ior_cmd"

# Test _IOW
let cmd2 = iow_cmd("S", 2, 8)
let expected_iow = (1 * 1073741824) + (8 * 65536) + (s_ord * 256) + 2
if cmd2 == expected_iow:
    print "iow_cmd"

# Test _IOWR
let cmd3 = iowr_cmd("S", 3, 16)
let expected_iowr = (3 * 1073741824) + (16 * 65536) + (s_ord * 256) + 3
if cmd3 == expected_iowr:
    print "iowr_cmd"

# Test ioctl set builder
proc create_ioctl_set(magic):
    let s = {}
    s["type"] = magic
    s["commands"] = []
    s["next_nr"] = 0
    return s

proc ioctl_add(s, name, direction, data_size):
    let cmd = {}
    cmd["name"] = name
    cmd["direction"] = direction
    cmd["nr"] = s["next_nr"]
    cmd["data_size"] = data_size
    push(s["commands"], cmd)
    s["next_nr"] = s["next_nr"] + 1
    return s

let iset = create_ioctl_set("S")
iset = ioctl_add(iset, "SAGE_GET_VERSION", IOC_READ, 4)
iset = ioctl_add(iset, "SAGE_SET_CONFIG", IOC_WRITE, 64)
iset = ioctl_add(iset, "SAGE_RESET", IOC_NONE, 0)
if len(iset["commands"]) == 3:
    if iset["commands"][0]["name"] == "SAGE_GET_VERSION":
        if iset["commands"][2]["direction"] == IOC_NONE:
            print "ioctl_set"

# Test header codegen
let nl = chr(10)
let hdr = ""
hdr = hdr + "#ifndef _IOCTL_CMDS_H" + nl
hdr = hdr + "#define _IOCTL_CMDS_H" + nl
hdr = hdr + "#include <linux/ioctl.h>" + nl
hdr = hdr + "#define SAGE_GET_VERSION _IOR(" + chr(39) + "S" + chr(39) + ", 0, 4)" + nl
hdr = hdr + "#define SAGE_SET_CONFIG _IOW(" + chr(39) + "S" + chr(39) + ", 1, 64)" + nl
hdr = hdr + "#define SAGE_RESET _IO(" + chr(39) + "S" + chr(39) + ", 2)" + nl
hdr = hdr + "#endif" + nl
if contains(hdr, "#define SAGE_GET_VERSION"):
    if contains(hdr, "_IOR"):
        if contains(hdr, "_IOW"):
            print "header_gen"

# Test handler codegen
let handler = ""
handler = handler + "static long sage_ioctl(struct file *filp, unsigned int cmd, unsigned long arg) {" + nl
handler = handler + "    switch (cmd) {" + nl
handler = handler + "    case SAGE_GET_VERSION:" + nl
handler = handler + "        break;" + nl
handler = handler + "    default:" + nl
handler = handler + "        return -ENOTTY;" + nl
handler = handler + "    }" + nl
handler = handler + "    return 0;" + nl
handler = handler + "}" + nl
if contains(handler, "switch (cmd)"):
    if contains(handler, "ENOTTY"):
        print "handler_gen"

print "PASS"
