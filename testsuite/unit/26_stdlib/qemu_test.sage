gc_disable()
# EXPECT: vm_created
# EXPECT: arch_x86
# EXPECT: arch_arm64
# EXPECT: arch_riscv
# EXPECT: boot_kernel
# EXPECT: boot_disk
# EXPECT: drives_added
# EXPECT: net_user
# EXPECT: devices_added
# EXPECT: cmd_basic
# EXPECT: cmd_kernel
# EXPECT: cmd_kvm
# EXPECT: baremetal_preset
# EXPECT: linux_preset
# EXPECT: gdb_debug
# EXPECT: qemu_img_cmds
# EXPECT: PASS

# Test VM creation
proc create_vm(name):
    let vm = {}
    vm["name"] = name
    vm["arch"] = "x86_64"
    vm["machine"] = "q35"
    vm["cpu"] = ""
    vm["smp"] = 1
    vm["memory"] = "256M"
    vm["accel"] = ""
    vm["display"] = "none"
    vm["serial"] = "stdio"
    vm["monitor"] = ""
    vm["boot_mode"] = ""
    vm["kernel"] = ""
    vm["initrd"] = ""
    vm["append"] = ""
    vm["bios"] = ""
    vm["drives"] = []
    vm["net"] = []
    vm["devices"] = []
    vm["chardevs"] = []
    vm["fw_cfg"] = []
    vm["extra_args"] = []
    vm["gdb_port"] = 0
    vm["daemonize"] = false
    vm["snapshot"] = false
    vm["no_reboot"] = false
    vm["no_shutdown"] = false
    return vm
end

let vm = create_vm("test_vm")
if vm["name"] == "test_vm":
    if vm["arch"] == "x86_64":
        if vm["memory"] == "256M":
            print "vm_created"
        end
    end
end

# Test architecture settings
if vm["arch"] == "x86_64":
    if vm["machine"] == "q35":
        print "arch_x86"
    end
end

vm["arch"] = "aarch64"
vm["machine"] = "virt"
vm["cpu"] = "cortex-a72"
if vm["arch"] == "aarch64":
    if vm["machine"] == "virt":
        if vm["cpu"] == "cortex-a72":
            print "arch_arm64"
        end
    end
end

vm["arch"] = "riscv64"
vm["machine"] = "virt"
vm["cpu"] = ""
if vm["arch"] == "riscv64":
    if vm["machine"] == "virt":
        print "arch_riscv"
    end
end

# Reset to x86_64
vm["arch"] = "x86_64"
vm["machine"] = "q35"

# Test kernel boot
vm["boot_mode"] = "kernel"
vm["kernel"] = "kernel.elf"
vm["append"] = "console=ttyS0"
if vm["kernel"] == "kernel.elf":
    if vm["append"] == "console=ttyS0":
        print "boot_kernel"
    end
end

# Test disk boot
let drv = {}
drv["file"] = "disk.img"
drv["format"] = "raw"
drv["interface"] = "ide"
drv["index"] = 0
drv["media"] = "disk"
drv["boot"] = true
push(vm["drives"], drv)
if len(vm["drives"]) == 1:
    if vm["drives"][0]["file"] == "disk.img":
        print "boot_disk"
    end
end

# Test adding drives
let drv2 = {}
drv2["file"] = "data.qcow2"
drv2["format"] = "qcow2"
drv2["interface"] = "virtio"
drv2["index"] = 1
drv2["media"] = "disk"
drv2["boot"] = false
push(vm["drives"], drv2)
if len(vm["drives"]) == 2:
    if vm["drives"][1]["format"] == "qcow2":
        if vm["drives"][1]["interface"] == "virtio":
            print "drives_added"
        end
    end
end

# Test user networking
let net = {}
net["type"] = "user"
net["hostfwd"] = "tcp::2222-:22"
net["model"] = "virtio-net-pci"
push(vm["net"], net)
if len(vm["net"]) == 1:
    if vm["net"][0]["hostfwd"] == "tcp::2222-:22":
        print "net_user"
    end
end

# Test devices
push(vm["devices"], "virtio-rng-pci")
push(vm["devices"], "virtio-balloon-pci")
push(vm["devices"], "virtio-gpu-pci")
if len(vm["devices"]) == 3:
    if vm["devices"][0] == "virtio-rng-pci":
        print "devices_added"
    end
end

# Test command building
proc join_parts(parts):
    let cmd = ""
    let pi = 0
    while pi < len(parts):
        if pi > 0:
            cmd = cmd + " "
        end
        cmd = cmd + parts[pi]
        pi = pi + 1
    end
    return cmd
end

# Basic command
let basic_parts = []
push(basic_parts, "qemu-system-x86_64")
push(basic_parts, "-machine")
push(basic_parts, "q35")
push(basic_parts, "-m")
push(basic_parts, "256M")
push(basic_parts, "-display")
push(basic_parts, "none")
let basic_cmd = join_parts(basic_parts)
if contains(basic_cmd, "qemu-system-x86_64"):
    if contains(basic_cmd, "-machine q35"):
        if contains(basic_cmd, "-m 256M"):
            print "cmd_basic"
        end
    end
end

# Kernel command
let kern_parts = []
push(kern_parts, "qemu-system-x86_64")
push(kern_parts, "-kernel")
push(kern_parts, "bzImage")
push(kern_parts, "-append")
push(kern_parts, chr(34) + "console=ttyS0 root=/dev/vda" + chr(34))
let kern_cmd = join_parts(kern_parts)
if contains(kern_cmd, "-kernel bzImage"):
    if contains(kern_cmd, "-append"):
        if contains(kern_cmd, "console=ttyS0"):
            print "cmd_kernel"
        end
    end
end

# KVM command
let kvm_parts = []
push(kvm_parts, "qemu-system-x86_64")
push(kvm_parts, "-machine")
push(kvm_parts, "q35,accel=kvm")
push(kvm_parts, "-cpu")
push(kvm_parts, "host")
let kvm_cmd = join_parts(kvm_parts)
if contains(kvm_cmd, "accel=kvm"):
    if contains(kvm_cmd, "-cpu host"):
        print "cmd_kvm"
    end
end

# Test baremetal preset
proc baremetal_x86(name, kernel_elf):
    let bm = create_vm(name)
    bm["arch"] = "x86_64"
    bm["machine"] = "q35"
    bm["memory"] = "64M"
    bm["kernel"] = kernel_elf
    bm["no_reboot"] = true
    return bm
end

let bm = baremetal_x86("sage_kernel", "kernel.elf")
if bm["memory"] == "64M":
    if bm["kernel"] == "kernel.elf":
        if bm["no_reboot"]:
            print "baremetal_preset"
        end
    end
end

# Test linux preset
proc linux_vm(name, kernel, rootfs, cmdline):
    let lvm = create_vm(name)
    lvm["arch"] = "x86_64"
    lvm["machine"] = "q35"
    lvm["cpu"] = "host"
    lvm["accel"] = "kvm"
    lvm["smp"] = 2
    lvm["memory"] = "512M"
    lvm["kernel"] = kernel
    lvm["append"] = cmdline
    let rd = {}
    rd["file"] = rootfs
    rd["format"] = "qcow2"
    rd["interface"] = "virtio"
    rd["index"] = 0
    rd["media"] = "disk"
    rd["boot"] = false
    push(lvm["drives"], rd)
    return lvm
end

let lvm = linux_vm("dev", "bzImage", "rootfs.qcow2", "console=ttyS0")
if lvm["smp"] == 2:
    if lvm["memory"] == "512M":
        if lvm["accel"] == "kvm":
            if len(lvm["drives"]) == 1:
                print "linux_preset"
            end
        end
    end
end

# Test GDB debugging
vm["gdb_port"] = 1234
if vm["gdb_port"] == 1234:
    let gdb_cmd = "target remote :1234"
    let gdb_script = "file kernel.elf" + chr(10) + "target remote :1234" + chr(10)
    if contains(gdb_script, "target remote"):
        if contains(gdb_script, "file kernel.elf"):
            print "gdb_debug"
        end
    end
end

# Test qemu-img commands
proc qemu_img_create(path, fmt, size):
    return "qemu-img create -f " + fmt + " " + path + " " + size
end

proc qemu_img_convert(src, sf, dst, df):
    return "qemu-img convert -f " + sf + " -O " + df + " " + src + " " + dst
end

let create_cmd = qemu_img_create("disk.qcow2", "qcow2", "10G")
let convert_cmd = qemu_img_convert("disk.raw", "raw", "disk.qcow2", "qcow2")
if contains(create_cmd, "qemu-img create -f qcow2 disk.qcow2 10G"):
    if contains(convert_cmd, "-f raw -O qcow2"):
        print "qemu_img_cmds"
    end
end

print "PASS"
