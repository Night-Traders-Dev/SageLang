gc_disable()

# driver.sage — Linux kernel driver framework for Sage
#
# Provides structures and helpers for building Linux-compatible device drivers.
# Supports char, block, and network device types.
# Generates C stubs suitable for kernel module compilation.

# ----- Driver types -----
let DRIVER_CHAR = "char"
let DRIVER_BLOCK = "block"
let DRIVER_NET = "net"
let DRIVER_PLATFORM = "platform"
let DRIVER_USB = "usb"
let DRIVER_I2C = "i2c"
let DRIVER_SPI = "spi"
let DRIVER_PCI_DRIVER = "pci"

# ----- Device major numbers -----
let MAJOR_DYNAMIC = 0
let MAJOR_MEM = 1
let MAJOR_TTY = 4
let MAJOR_LP = 6
let MAJOR_LOOP = 7
let MAJOR_SCSI = 8
let MAJOR_INPUT = 13
let MAJOR_FB = 29
let MAJOR_MISC = 10

# ----- File operation flags -----
let FOPS_READ = 1
let FOPS_WRITE = 2
let FOPS_IOCTL = 4
let FOPS_OPEN = 8
let FOPS_RELEASE = 16
let FOPS_MMAP = 32
let FOPS_POLL = 64
let FOPS_LLSEEK = 128
let FOPS_FASYNC = 256

# ========== Driver descriptor ==========

proc create_driver(name, driver_type):
    let drv = {}
    drv["name"] = name
    drv["type"] = driver_type
    drv["major"] = MAJOR_DYNAMIC
    drv["minor_start"] = 0
    drv["minor_count"] = 1
    drv["license"] = "GPL"
    drv["author"] = ""
    drv["description"] = ""
    drv["version"] = "1.0"
    drv["fops"] = 0
    drv["ops"] = []
    drv["params"] = []
    drv["irq"] = -1
    drv["io_base"] = 0
    drv["io_size"] = 0
    drv["dma_capable"] = false
    drv["probe"] = nil
    drv["remove"] = nil
    return drv
end

proc set_license(drv, license):
    drv["license"] = license
    return drv
end

proc set_author(drv, author):
    drv["author"] = author
    return drv
end

proc set_description(drv, desc):
    drv["description"] = desc
    return drv
end

proc add_fops(drv, flags):
    drv["fops"] = drv["fops"] + flags
    return drv
end

# ========== Module parameter ==========

proc add_param(drv, name, param_type, default_val, desc):
    let p = {}
    p["name"] = name
    p["type"] = param_type
    p["default"] = default_val
    p["description"] = desc
    append(drv["params"], p)
    return drv
end

# ========== IRQ / IO region ==========

proc set_irq(drv, irq_num):
    drv["irq"] = irq_num
    return drv
end

proc set_io_region(drv, base, size):
    drv["io_base"] = base
    drv["io_size"] = size
    return drv
end

# ========== Char device operations ==========

proc add_op(drv, op_name, body_lines):
    let op = {}
    op["name"] = op_name
    op["body"] = body_lines
    append(drv["ops"], op)
    return drv
end

# ========== C code generation ==========

proc emit_includes():
    let nl = chr(10)
    let code = ""
    code = code + "#include <linux/module.h>" + nl
    code = code + "#include <linux/kernel.h>" + nl
    code = code + "#include <linux/init.h>" + nl
    code = code + "#include <linux/fs.h>" + nl
    code = code + "#include <linux/cdev.h>" + nl
    code = code + "#include <linux/device.h>" + nl
    code = code + "#include <linux/uaccess.h>" + nl
    code = code + "#include <linux/slab.h>" + nl
    code = code + "#include <linux/ioctl.h>" + nl
    code = code + "#include <linux/poll.h>" + nl
    return code
end

proc emit_module_info(drv):
    let nl = chr(10)
    let q = chr(34)
    let code = ""
    code = code + "MODULE_LICENSE(" + q + drv["license"] + q + ");" + nl
    if drv["author"] != "":
        code = code + "MODULE_AUTHOR(" + q + drv["author"] + q + ");" + nl
    end
    if drv["description"] != "":
        code = code + "MODULE_DESCRIPTION(" + q + drv["description"] + q + ");" + nl
    end
    code = code + "MODULE_VERSION(" + q + drv["version"] + q + ");" + nl
    return code
end

proc emit_params(drv):
    let nl = chr(10)
    let q = chr(34)
    let code = ""
    let i = 0
    while i < len(drv["params"]):
        let p = drv["params"][i]
        if p["type"] == "int":
            code = code + "static int " + p["name"] + " = " + str(p["default"]) + ";" + nl
            code = code + "module_param(" + p["name"] + ", int, 0644);" + nl
        end
        if p["type"] == "string":
            code = code + "static char *" + p["name"] + " = " + q + str(p["default"]) + q + ";" + nl
            code = code + "module_param(" + p["name"] + ", charp, 0644);" + nl
        end
        if p["type"] == "bool":
            let bval = "false"
            if p["default"]:
                bval = "true"
            end
            code = code + "static bool " + p["name"] + " = " + bval + ";" + nl
            code = code + "module_param(" + p["name"] + ", bool, 0644);" + nl
        end
        code = code + "MODULE_PARM_DESC(" + p["name"] + ", " + q + p["description"] + q + ");" + nl
        i = i + 1
    end
    return code
end

proc emit_char_device(drv):
    let nl = chr(10)
    let q = chr(34)
    let name = drv["name"]
    let code = ""

    # Device state
    code = code + "static dev_t " + name + "_dev;" + nl
    code = code + "static struct cdev " + name + "_cdev;" + nl
    code = code + "static struct class *" + name + "_class;" + nl
    code = code + nl

    # Open
    code = code + "static int " + name + "_open(struct inode *inode, struct file *filp) {" + nl
    code = code + "    pr_info(" + q + name + ": opened" + q + ");" + nl
    code = code + "    return 0;" + nl
    code = code + "}" + nl + nl

    # Release
    code = code + "static int " + name + "_release(struct inode *inode, struct file *filp) {" + nl
    code = code + "    pr_info(" + q + name + ": released" + q + ");" + nl
    code = code + "    return 0;" + nl
    code = code + "}" + nl + nl

    # Read
    code = code + "static ssize_t " + name + "_read(struct file *filp, char __user *buf, size_t count, loff_t *pos) {" + nl
    code = code + "    return 0;" + nl
    code = code + "}" + nl + nl

    # Write
    code = code + "static ssize_t " + name + "_write(struct file *filp, const char __user *buf, size_t count, loff_t *pos) {" + nl
    code = code + "    return count;" + nl
    code = code + "}" + nl + nl

    # File operations
    code = code + "static struct file_operations " + name + "_fops = {" + nl
    code = code + "    .owner = THIS_MODULE," + nl
    code = code + "    .open = " + name + "_open," + nl
    code = code + "    .release = " + name + "_release," + nl
    code = code + "    .read = " + name + "_read," + nl
    code = code + "    .write = " + name + "_write," + nl
    code = code + "};" + nl + nl

    return code
end

proc emit_init_exit(drv):
    let nl = chr(10)
    let q = chr(34)
    let name = drv["name"]
    let code = ""

    # Init
    code = code + "static int __init " + name + "_init(void) {" + nl
    code = code + "    int ret;" + nl
    code = code + "    pr_info(" + q + name + ": loading module" + q + ");" + nl
    if drv["type"] == DRIVER_CHAR:
        code = code + "    ret = alloc_chrdev_region(&" + name + "_dev, "
        code = code + str(drv["minor_start"]) + ", "
        code = code + str(drv["minor_count"]) + ", "
        code = code + q + name + q + ");" + nl
        code = code + "    if (ret < 0) return ret;" + nl
        code = code + "    cdev_init(&" + name + "_cdev, &" + name + "_fops);" + nl
        code = code + "    ret = cdev_add(&" + name + "_cdev, " + name + "_dev, " + str(drv["minor_count"]) + ");" + nl
        code = code + "    if (ret < 0) { unregister_chrdev_region(" + name + "_dev, " + str(drv["minor_count"]) + "); return ret; }" + nl
        code = code + "    " + name + "_class = class_create(" + q + name + q + ");" + nl
        code = code + "    device_create(" + name + "_class, NULL, " + name + "_dev, NULL, " + q + name + q + ");" + nl
    end
    code = code + "    return 0;" + nl
    code = code + "}" + nl + nl

    # Exit
    code = code + "static void __exit " + name + "_exit(void) {" + nl
    code = code + "    pr_info(" + q + name + ": unloading module" + q + ");" + nl
    if drv["type"] == DRIVER_CHAR:
        code = code + "    device_destroy(" + name + "_class, " + name + "_dev);" + nl
        code = code + "    class_destroy(" + name + "_class);" + nl
        code = code + "    cdev_del(&" + name + "_cdev);" + nl
        code = code + "    unregister_chrdev_region(" + name + "_dev, " + str(drv["minor_count"]) + ");" + nl
    end
    code = code + "}" + nl + nl

    code = code + "module_init(" + name + "_init);" + nl
    code = code + "module_exit(" + name + "_exit);" + nl

    return code
end

# ========== Full driver codegen ==========

proc generate_driver_c(drv):
    let code = ""
    code = code + emit_includes()
    code = code + chr(10)
    code = code + emit_module_info(drv)
    code = code + chr(10)
    code = code + emit_params(drv)
    code = code + chr(10)
    if drv["type"] == DRIVER_CHAR:
        code = code + emit_char_device(drv)
    end
    code = code + emit_init_exit(drv)
    return code
end

# ========== Kbuild Makefile generation ==========

proc generate_kbuild(drv):
    let nl = chr(10)
    let code = ""
    code = code + "obj-m := " + drv["name"] + ".o" + nl
    code = code + nl
    code = code + "KDIR := /lib/modules/$(shell uname -r)/build" + nl
    code = code + nl
    code = code + "all:" + nl
    code = code + chr(9) + "$(MAKE) -C $(KDIR) M=$(PWD) modules" + nl
    code = code + nl
    code = code + "clean:" + nl
    code = code + chr(9) + "$(MAKE) -C $(KDIR) M=$(PWD) clean" + nl
    return code
end

# ========== Convenience builders ==========

proc simple_char_driver(name, author, desc):
    let drv = create_driver(name, DRIVER_CHAR)
    drv = set_author(drv, author)
    drv = set_description(drv, desc)
    drv = add_fops(drv, FOPS_READ + FOPS_WRITE + FOPS_OPEN + FOPS_RELEASE)
    return drv
end
