gc_disable()
# EXPECT: module_created
# EXPECT: module_meta
# EXPECT: module_params
# EXPECT: module_functions
# EXPECT: procfs_entry
# EXPECT: init_exit_body
# EXPECT: codegen_output
# EXPECT: dkms_config
# EXPECT: kbuild_output
# EXPECT: PASS

# Test module creation
proc create_module(name):
    let m = {}
    m["name"] = name
    m["license"] = "GPL"
    m["author"] = ""
    m["description"] = ""
    m["version"] = "1.0.0"
    m["params"] = []
    m["init_body"] = []
    m["exit_body"] = []
    m["includes"] = []
    m["globals"] = []
    m["functions"] = []
    m["procfs_entries"] = []
    return m

let m = create_module("sage_test")
if m["name"] == "sage_test":
    if m["license"] == "GPL":
        print "module_created"

# Test metadata
m["author"] = "Test Author"
m["description"] = "A test module"
m["version"] = "2.0.0"
if m["author"] == "Test Author":
    if m["version"] == "2.0.0":
        print "module_meta"

# Test params
let p1 = {}
p1["name"] = "max_size"
p1["type"] = "int"
p1["default"] = 1024
p1["desc"] = "Maximum buffer size"
push(m["params"], p1)
let p2 = {}
p2["name"] = "verbose"
p2["type"] = "bool"
p2["default"] = false
p2["desc"] = "Enable verbose output"
push(m["params"], p2)
if len(m["params"]) == 2:
    if m["params"][0]["name"] == "max_size":
        print "module_params"

# Test functions
let f = {}
f["signature"] = "static int helper_func(int x)"
f["body"] = ["return x * 2;"]
push(m["functions"], f)
if len(m["functions"]) == 1:
    if m["functions"][0]["signature"] == "static int helper_func(int x)":
        print "module_functions"

# Test procfs entry
let pe = {}
pe["filename"] = "sage_info"
pe["read_func"] = "sage_info_show"
push(m["procfs_entries"], pe)
if len(m["procfs_entries"]) == 1:
    if m["procfs_entries"][0]["filename"] == "sage_info":
        print "procfs_entry"

# Test init/exit body
push(m["init_body"], "helper_func(42);")
push(m["exit_body"], "kfree(buffer);")
if len(m["init_body"]) == 1:
    if len(m["exit_body"]) == 1:
        print "init_exit_body"

# Test codegen produces valid C
let nl = chr(10)
let q = chr(34)
let code = ""
code = code + "#include <linux/module.h>" + nl
code = code + "MODULE_LICENSE(" + q + m["license"] + q + ");" + nl
code = code + "MODULE_AUTHOR(" + q + m["author"] + q + ");" + nl
code = code + "static int __init sage_test_init(void) { return 0; }" + nl
code = code + "module_init(sage_test_init);" + nl
if contains(code, "MODULE_LICENSE"):
    if contains(code, "module_init"):
        if contains(code, "__init"):
            print "codegen_output"

# Test DKMS config
let dkms = ""
dkms = dkms + "PACKAGE_NAME=" + q + m["name"] + q + nl
dkms = dkms + "PACKAGE_VERSION=" + q + m["version"] + q + nl
dkms = dkms + "AUTOINSTALL=" + q + "yes" + q + nl
if contains(dkms, "PACKAGE_NAME"):
    if contains(dkms, "AUTOINSTALL"):
        print "dkms_config"

# Test Kbuild output
let kb = "obj-m := " + m["name"] + ".o" + nl
kb = kb + "KDIR := /lib/modules/$(shell uname -r)/build" + nl
if contains(kb, "obj-m := sage_test.o"):
    print "kbuild_output"

print "PASS"
