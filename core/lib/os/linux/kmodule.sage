gc_disable()

# kmodule.sage — Linux kernel module builder for Sage
#
# Generates complete kernel module source, Kbuild files, and DKMS configs.
# Supports module parameters, init/exit handlers, and procfs entries.

# ----- Module state -----
let MOD_STATE_UNLOADED = 0
let MOD_STATE_LOADING = 1
let MOD_STATE_LIVE = 2
let MOD_STATE_UNLOADING = 3

# ========== Module descriptor ==========

proc create_module(name):
    let m = {}
    m["name"] = name
    m["license"] = "GPL"
    m["author"] = ""
    m["description"] = ""
    m["version"] = "1.0.0"
    m["depends"] = []
    m["params"] = []
    m["init_body"] = []
    m["exit_body"] = []
    m["includes"] = []
    m["globals"] = []
    m["functions"] = []
    m["procfs_entries"] = []
    m["sysfs_attrs"] = []
    return m
end

proc mod_set_meta(m, license, author, desc, ver):
    m["license"] = license
    m["author"] = author
    m["description"] = desc
    m["version"] = ver
    return m
end

proc mod_add_depend(m, dep):
    append(m["depends"], dep)
    return m
end

proc mod_add_param(m, name, ptype, default_val, desc):
    let p = {}
    p["name"] = name
    p["type"] = ptype
    p["default"] = default_val
    p["desc"] = desc
    append(m["params"], p)
    return m
end

proc mod_add_include(m, header):
    append(m["includes"], header)
    return m
end

proc mod_add_global(m, decl):
    append(m["globals"], decl)
    return m
end

proc mod_add_function(m, signature, body_lines):
    let f = {}
    f["signature"] = signature
    f["body"] = body_lines
    append(m["functions"], f)
    return m
end

proc mod_add_init_line(m, line):
    append(m["init_body"], line)
    return m
end

proc mod_add_exit_line(m, line):
    append(m["exit_body"], line)
    return m
end

# ========== Procfs entry ==========

proc mod_add_procfs(m, filename, read_func):
    let entry = {}
    entry["filename"] = filename
    entry["read_func"] = read_func
    append(m["procfs_entries"], entry)
    return m
end

# ========== Sysfs attribute ==========

proc mod_add_sysfs_attr(m, attr_name, show_func, store_func):
    let attr = {}
    attr["name"] = attr_name
    attr["show"] = show_func
    attr["store"] = store_func
    append(m["sysfs_attrs"], attr)
    return m
end

# ========== Code generation ==========

proc generate_module_c(m):
    let nl = chr(10)
    let q = chr(34)
    let code = ""
    let name = m["name"]

    # Standard includes
    code = code + "#include <linux/module.h>" + nl
    code = code + "#include <linux/kernel.h>" + nl
    code = code + "#include <linux/init.h>" + nl

    # Procfs includes if needed
    if len(m["procfs_entries"]) > 0:
        code = code + "#include <linux/proc_fs.h>" + nl
        code = code + "#include <linux/seq_file.h>" + nl
    end

    # Custom includes
    let ii = 0
    while ii < len(m["includes"]):
        code = code + "#include <" + m["includes"][ii] + ">" + nl
        ii = ii + 1
    end
    code = code + nl

    # Module info
    code = code + "MODULE_LICENSE(" + q + m["license"] + q + ");" + nl
    if m["author"] != "":
        code = code + "MODULE_AUTHOR(" + q + m["author"] + q + ");" + nl
    end
    if m["description"] != "":
        code = code + "MODULE_DESCRIPTION(" + q + m["description"] + q + ");" + nl
    end
    code = code + "MODULE_VERSION(" + q + m["version"] + q + ");" + nl
    code = code + nl

    # Module parameters
    let pi = 0
    while pi < len(m["params"]):
        let p = m["params"][pi]
        if p["type"] == "int":
            code = code + "static int " + p["name"] + " = " + str(p["default"]) + ";" + nl
            code = code + "module_param(" + p["name"] + ", int, 0644);" + nl
        end
        if p["type"] == "bool":
            let bval = "false"
            if p["default"]:
                bval = "true"
            end
            code = code + "static bool " + p["name"] + " = " + bval + ";" + nl
            code = code + "module_param(" + p["name"] + ", bool, 0644);" + nl
        end
        if p["type"] == "string":
            code = code + "static char *" + p["name"] + " = " + q + str(p["default"]) + q + ";" + nl
            code = code + "module_param(" + p["name"] + ", charp, 0644);" + nl
        end
        code = code + "MODULE_PARM_DESC(" + p["name"] + ", " + q + p["desc"] + q + ");" + nl
        pi = pi + 1
    end
    code = code + nl

    # Global variables
    let gi = 0
    while gi < len(m["globals"]):
        code = code + m["globals"][gi] + nl
        gi = gi + 1
    end
    code = code + nl

    # Custom functions
    let fi = 0
    while fi < len(m["functions"]):
        let f = m["functions"][fi]
        code = code + f["signature"] + " {" + nl
        let bi = 0
        while bi < len(f["body"]):
            code = code + "    " + f["body"][bi] + nl
            bi = bi + 1
        end
        code = code + "}" + nl + nl
        fi = fi + 1
    end

    # Procfs entries
    if len(m["procfs_entries"]) > 0:
        let pe = 0
        while pe < len(m["procfs_entries"]):
            let entry = m["procfs_entries"][pe]
            code = code + "static int " + entry["read_func"] + "(struct seq_file *sf, void *v) {" + nl
            code = code + "    seq_printf(sf, " + q + name + " proc entry" + chr(92) + "n" + q + ");" + nl
            code = code + "    return 0;" + nl
            code = code + "}" + nl + nl
            code = code + "static int " + entry["filename"] + "_open(struct inode *inode, struct file *file) {" + nl
            code = code + "    return single_open(file, " + entry["read_func"] + ", NULL);" + nl
            code = code + "}" + nl + nl
            code = code + "static const struct proc_ops " + entry["filename"] + "_pops = {" + nl
            code = code + "    .proc_open = " + entry["filename"] + "_open," + nl
            code = code + "    .proc_read = seq_read," + nl
            code = code + "    .proc_lseek = seq_lseek," + nl
            code = code + "    .proc_release = single_release," + nl
            code = code + "};" + nl + nl
            pe = pe + 1
        end
    end

    # Init function
    code = code + "static int __init " + name + "_init(void) {" + nl
    code = code + "    pr_info(" + q + name + ": module loaded" + q + ");" + nl
    # Procfs creation
    let pei = 0
    while pei < len(m["procfs_entries"]):
        let pe2 = m["procfs_entries"][pei]
        code = code + "    proc_create(" + q + pe2["filename"] + q + ", 0444, NULL, &" + pe2["filename"] + "_pops);" + nl
        pei = pei + 1
    end
    # Custom init body
    let ini = 0
    while ini < len(m["init_body"]):
        code = code + "    " + m["init_body"][ini] + nl
        ini = ini + 1
    end
    code = code + "    return 0;" + nl
    code = code + "}" + nl + nl

    # Exit function
    code = code + "static void __exit " + name + "_exit(void) {" + nl
    code = code + "    pr_info(" + q + name + ": module unloaded" + q + ");" + nl
    # Procfs removal
    let peri = 0
    while peri < len(m["procfs_entries"]):
        let pe3 = m["procfs_entries"][peri]
        code = code + "    remove_proc_entry(" + q + pe3["filename"] + q + ", NULL);" + nl
        peri = peri + 1
    end
    # Custom exit body
    let exi = 0
    while exi < len(m["exit_body"]):
        code = code + "    " + m["exit_body"][exi] + nl
        exi = exi + 1
    end
    code = code + "}" + nl + nl

    code = code + "module_init(" + name + "_init);" + nl
    code = code + "module_exit(" + name + "_exit);" + nl

    return code
end

# ========== DKMS config generation ==========

proc generate_dkms_conf(m):
    let nl = chr(10)
    let q = chr(34)
    let name = m["name"]
    let conf = ""
    conf = conf + "PACKAGE_NAME=" + q + name + q + nl
    conf = conf + "PACKAGE_VERSION=" + q + m["version"] + q + nl
    conf = conf + "MAKE[0]=" + q + "make -C /lib/modules/${kernelver}/build M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build modules" + q + nl
    conf = conf + "CLEAN=" + q + "make -C /lib/modules/${kernelver}/build M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build clean" + q + nl
    conf = conf + "BUILT_MODULE_NAME[0]=" + q + name + q + nl
    conf = conf + "DEST_MODULE_LOCATION[0]=" + q + "/extra" + q + nl
    conf = conf + "AUTOINSTALL=" + q + "yes" + q + nl
    return conf
end

# ========== Kbuild generation ==========

proc generate_kbuild(m):
    let nl = chr(10)
    let code = ""
    code = code + "obj-m := " + m["name"] + ".o" + nl
    code = code + nl
    code = code + "KDIR := /lib/modules/$(shell uname -r)/build" + nl
    code = code + nl
    code = code + "all:" + nl
    code = code + chr(9) + "$(MAKE) -C $(KDIR) M=$(PWD) modules" + nl
    code = code + nl
    code = code + "clean:" + nl
    code = code + chr(9) + "$(MAKE) -C $(KDIR) M=$(PWD) clean" + nl
    code = code + nl
    code = code + "install:" + nl
    code = code + chr(9) + "$(MAKE) -C $(KDIR) M=$(PWD) modules_install" + nl
    return code
end
