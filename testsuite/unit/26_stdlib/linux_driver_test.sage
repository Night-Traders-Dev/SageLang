gc_disable()
# EXPECT: driver_created
# EXPECT: char_driver
# EXPECT: driver_meta
# EXPECT: driver_params
# EXPECT: fops_flags
# EXPECT: irq_io
# EXPECT: codegen_includes
# EXPECT: codegen_module
# EXPECT: codegen_char
# EXPECT: kbuild_gen
# EXPECT: PASS

# Test driver creation
proc create_driver(name, driver_type):
    let drv = {}
    drv["name"] = name
    drv["type"] = driver_type
    drv["major"] = 0
    drv["minor_start"] = 0
    drv["minor_count"] = 1
    drv["license"] = "GPL"
    drv["author"] = ""
    drv["description"] = ""
    drv["version"] = "1.0"
    drv["fops"] = 0
    drv["params"] = []
    drv["irq"] = -1
    drv["io_base"] = 0
    drv["io_size"] = 0
    return drv

let drv = create_driver("sage_dev", "char")
if drv["name"] == "sage_dev":
    if drv["type"] == "char":
        if drv["license"] == "GPL":
            print "driver_created"

# Test char driver type
if drv["type"] == "char":
    print "char_driver"

# Test metadata
drv["author"] = "SageLang Team"
drv["description"] = "Test device driver"
drv["version"] = "2.0"
if drv["author"] == "SageLang Team":
    if drv["description"] == "Test device driver":
        print "driver_meta"

# Test module params
proc add_param(drv, name, ptype, default_val, desc):
    let p = {}
    p["name"] = name
    p["type"] = ptype
    p["default"] = default_val
    p["description"] = desc
    push(drv["params"], p)
    return drv

drv = add_param(drv, "buffer_size", "int", 4096, "Buffer size in bytes")
drv = add_param(drv, "debug", "bool", false, "Enable debug mode")
if len(drv["params"]) == 2:
    if drv["params"][0]["name"] == "buffer_size":
        if drv["params"][1]["type"] == "bool":
            print "driver_params"

# Test file operation flags
let FOPS_READ = 1
let FOPS_WRITE = 2
let FOPS_IOCTL = 4
let FOPS_OPEN = 8
let FOPS_RELEASE = 16
drv["fops"] = FOPS_READ + FOPS_WRITE + FOPS_OPEN + FOPS_RELEASE
if drv["fops"] == 27:
    print "fops_flags"

# Test IRQ/IO
drv["irq"] = 10
drv["io_base"] = 768
drv["io_size"] = 8
if drv["irq"] == 10:
    if drv["io_base"] == 768:
        print "irq_io"

# Test C codegen (includes)
proc emit_includes():
    let nl = chr(10)
    let code = ""
    code = code + "#include <linux/module.h>" + nl
    code = code + "#include <linux/kernel.h>" + nl
    code = code + "#include <linux/fs.h>" + nl
    return code

let inc = emit_includes()
if contains(inc, "linux/module.h"):
    if contains(inc, "linux/fs.h"):
        print "codegen_includes"

# Test module info codegen
proc emit_module_info(drv_in):
    let nl = chr(10)
    let q = chr(34)
    let code = ""
    code = code + "MODULE_LICENSE(" + q + drv_in["license"] + q + ");" + nl
    if drv_in["author"] != "":
        code = code + "MODULE_AUTHOR(" + q + drv_in["author"] + q + ");" + nl
    return code

let mod_code = emit_module_info(drv)
if contains(mod_code, "MODULE_LICENSE"):
    if contains(mod_code, "MODULE_AUTHOR"):
        print "codegen_module"

# Test char device codegen
proc emit_char_stub(name):
    let nl = chr(10)
    let q = chr(34)
    let code = ""
    code = code + "static dev_t " + name + "_dev;" + nl
    code = code + "static struct cdev " + name + "_cdev;" + nl
    code = code + "static int " + name + "_open(struct inode *inode, struct file *filp) {" + nl
    code = code + "    return 0;" + nl
    code = code + "}" + nl
    return code

let char_code = emit_char_stub("sage_dev")
if contains(char_code, "sage_dev_dev"):
    if contains(char_code, "sage_dev_open"):
        print "codegen_char"

# Test Kbuild generation
proc generate_kbuild(name):
    let nl = chr(10)
    let code = ""
    code = code + "obj-m := " + name + ".o" + nl
    code = code + "KDIR := /lib/modules/$(shell uname -r)/build" + nl
    return code

let kb = generate_kbuild("sage_dev")
if contains(kb, "obj-m := sage_dev.o"):
    if contains(kb, "KDIR"):
        print "kbuild_gen"

print "PASS"
