gc_disable()

# qemu.sage — QEMU virtual machine launcher and configuration
#
# Build QEMU command lines for running bare-metal kernels, Linux images,
# and Sage-compiled binaries. Supports x86_64, aarch64, riscv64, and arm.

# ----- Architectures -----
let ARCH_X86_64 = "x86_64"
let ARCH_I386 = "i386"
let ARCH_AARCH64 = "aarch64"
let ARCH_ARM = "arm"
let ARCH_RISCV64 = "riscv64"
let ARCH_RISCV32 = "riscv32"

# ----- Machine types -----
let MACH_PC = "pc"
let MACH_Q35 = "q35"
let MACH_MICROVM = "microvm"
let MACH_VIRT = "virt"
let MACH_SIFIVE_U = "sifive_u"
let MACH_SIFIVE_E = "sifive_e"
let MACH_RASPI2B = "raspi2b"
let MACH_RASPI3B = "raspi3b"

# ----- CPU models -----
let CPU_HOST = "host"
let CPU_MAX = "max"
let CPU_QEMU64 = "qemu64"
let CPU_CORTEX_A53 = "cortex-a53"
let CPU_CORTEX_A57 = "cortex-a57"
let CPU_CORTEX_A72 = "cortex-a72"
let CPU_RV64 = "rv64"

# ----- Accelerators -----
let ACCEL_KVM = "kvm"
let ACCEL_TCG = "tcg"
let ACCEL_HVF = "hvf"
let ACCEL_WHPX = "whpx"

# ----- Display modes -----
let DISPLAY_NONE = "none"
let DISPLAY_GTK = "gtk"
let DISPLAY_SDL = "sdl"
let DISPLAY_VNC = "vnc"
let DISPLAY_CURSES = "curses"

# ----- Serial output -----
let SERIAL_STDIO = "stdio"
let SERIAL_NONE = "none"
let SERIAL_FILE = "file"
let SERIAL_PIPE = "pipe"
let SERIAL_TCP = "tcp"

# ----- Boot modes -----
let BOOT_KERNEL = "kernel"
let BOOT_DISK = "disk"
let BOOT_CDROM = "cdrom"
let BOOT_UEFI = "uefi"
let BOOT_PXE = "pxe"

# ----- Disk formats -----
let FMT_RAW = "raw"
let FMT_QCOW2 = "qcow2"
let FMT_VDI = "vdi"
let FMT_VMDK = "vmdk"

# ----- Network modes -----
let NET_USER = "user"
let NET_TAP = "tap"
let NET_BRIDGE = "bridge"
let NET_NONE = "none"

# ========== VM Configuration ==========

proc create_vm(name):
    let vm = {}
    vm["name"] = name
    vm["arch"] = ARCH_X86_64
    vm["machine"] = MACH_Q35
    vm["cpu"] = ""
    vm["smp"] = 1
    vm["memory"] = "256M"
    vm["accel"] = ""
    vm["display"] = DISPLAY_NONE
    vm["serial"] = SERIAL_STDIO
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

proc vm_set_arch(vm, arch):
    vm["arch"] = arch
    if arch == ARCH_AARCH64:
        vm["machine"] = MACH_VIRT
    end
    if arch == ARCH_RISCV64:
        vm["machine"] = MACH_VIRT
    end
    if arch == ARCH_ARM:
        vm["machine"] = MACH_VIRT
    end
    return vm
end

proc vm_set_machine(vm, machine):
    vm["machine"] = machine
    return vm
end

proc vm_set_cpu(vm, cpu):
    vm["cpu"] = cpu
    return vm
end

proc vm_set_smp(vm, cores):
    vm["smp"] = cores
    return vm
end

proc vm_set_memory(vm, mem):
    vm["memory"] = mem
    return vm
end

proc vm_set_accel(vm, accel):
    vm["accel"] = accel
    return vm
end

proc vm_set_display(vm, display):
    vm["display"] = display
    return vm
end

proc vm_set_serial(vm, serial):
    vm["serial"] = serial
    return vm
end

proc vm_set_gdb(vm, port):
    vm["gdb_port"] = port
    return vm
end

# ========== Boot configuration ==========

proc vm_boot_kernel(vm, kernel_path, cmdline):
    vm["boot_mode"] = BOOT_KERNEL
    vm["kernel"] = kernel_path
    vm["append"] = cmdline
    return vm
end

proc vm_set_initrd(vm, initrd_path):
    vm["initrd"] = initrd_path
    return vm
end

proc vm_boot_disk(vm, disk_path):
    vm["boot_mode"] = BOOT_DISK
    let drv = {}
    drv["file"] = disk_path
    drv["format"] = FMT_RAW
    drv["interface"] = "ide"
    drv["index"] = 0
    drv["media"] = "disk"
    drv["boot"] = true
    push(vm["drives"], drv)
    return vm
end

proc vm_boot_cdrom(vm, iso_path):
    vm["boot_mode"] = BOOT_CDROM
    let drv = {}
    drv["file"] = iso_path
    drv["format"] = FMT_RAW
    drv["interface"] = "ide"
    drv["index"] = 1
    drv["media"] = "cdrom"
    drv["boot"] = true
    push(vm["drives"], drv)
    return vm
end

proc vm_boot_uefi(vm, firmware_path):
    vm["boot_mode"] = BOOT_UEFI
    vm["bios"] = firmware_path
    return vm
end

# ========== Drive configuration ==========

proc vm_add_drive(vm, file, fmt, iface):
    let drv = {}
    drv["file"] = file
    drv["format"] = fmt
    drv["interface"] = iface
    drv["index"] = len(vm["drives"])
    drv["media"] = "disk"
    drv["boot"] = false
    push(vm["drives"], drv)
    return vm
end

proc vm_add_virtio_disk(vm, file, fmt):
    let drv = {}
    drv["file"] = file
    drv["format"] = fmt
    drv["interface"] = "virtio"
    drv["index"] = len(vm["drives"])
    drv["media"] = "disk"
    drv["boot"] = false
    push(vm["drives"], drv)
    return vm
end

# ========== Network configuration ==========

proc vm_add_net_user(vm, hostfwd):
    let net = {}
    net["type"] = NET_USER
    net["hostfwd"] = hostfwd
    net["model"] = "virtio-net-pci"
    push(vm["net"], net)
    return vm
end

proc vm_add_net_tap(vm, ifname, bridge):
    let net = {}
    net["type"] = NET_TAP
    net["ifname"] = ifname
    net["bridge"] = bridge
    net["model"] = "virtio-net-pci"
    push(vm["net"], net)
    return vm
end

proc vm_add_net_none(vm):
    let net = {}
    net["type"] = NET_NONE
    push(vm["net"], net)
    return vm
end

# ========== Device configuration ==========

proc vm_add_device(vm, device_str):
    push(vm["devices"], device_str)
    return vm
end

proc vm_add_virtio_serial(vm):
    push(vm["devices"], "virtio-serial-pci")
    return vm
end

proc vm_add_virtio_rng(vm):
    push(vm["devices"], "virtio-rng-pci")
    return vm
end

proc vm_add_virtio_balloon(vm):
    push(vm["devices"], "virtio-balloon-pci")
    return vm
end

proc vm_add_virtio_gpu(vm):
    push(vm["devices"], "virtio-gpu-pci")
    return vm
end

proc vm_add_usb(vm):
    push(vm["devices"], "qemu-xhci")
    push(vm["devices"], "usb-kbd")
    push(vm["devices"], "usb-mouse")
    return vm
end

proc vm_add_fw_cfg(vm, name, file):
    let cfg = {}
    cfg["name"] = name
    cfg["file"] = file
    push(vm["fw_cfg"], cfg)
    return vm
end

proc vm_add_9p_share(vm, tag, path, security):
    let share = "virtio-9p-pci,fsdev=fs_" + tag + ",mount_tag=" + tag
    push(vm["devices"], share)
    let chardev = "local,id=fs_" + tag + ",path=" + path + ",security_model=" + security
    push(vm["chardevs"], chardev)
    return vm
end

proc vm_add_extra(vm, arg):
    push(vm["extra_args"], arg)
    return vm
end

# ========== Command generation ==========

proc qemu_binary(arch):
    return "qemu-system-" + arch
end

proc vm_build_command(vm):
    let parts = []
    push(parts, qemu_binary(vm["arch"]))

    # Machine
    let machine_str = vm["machine"]
    if vm["accel"] != "":
        machine_str = machine_str + ",accel=" + vm["accel"]
    end
    push(parts, "-machine")
    push(parts, machine_str)

    # CPU
    if vm["cpu"] != "":
        push(parts, "-cpu")
        push(parts, vm["cpu"])
    end

    # SMP
    if vm["smp"] > 1:
        push(parts, "-smp")
        push(parts, str(vm["smp"]))
    end

    # Memory
    push(parts, "-m")
    push(parts, vm["memory"])

    # Display
    push(parts, "-display")
    push(parts, vm["display"])

    # Serial
    if vm["serial"] != "":
        push(parts, "-serial")
        push(parts, vm["serial"])
    end

    # Monitor
    if vm["monitor"] != "":
        push(parts, "-monitor")
        push(parts, vm["monitor"])
    end

    # Kernel boot
    if vm["kernel"] != "":
        push(parts, "-kernel")
        push(parts, vm["kernel"])
    end
    if vm["initrd"] != "":
        push(parts, "-initrd")
        push(parts, vm["initrd"])
    end
    if vm["append"] != "":
        push(parts, "-append")
        push(parts, chr(34) + vm["append"] + chr(34))
    end

    # BIOS/firmware
    if vm["bios"] != "":
        push(parts, "-bios")
        push(parts, vm["bios"])
    end

    # Drives
    let di = 0
    while di < len(vm["drives"]):
        let drv = vm["drives"][di]
        let dstr = "file=" + drv["file"]
        dstr = dstr + ",format=" + drv["format"]
        if drv["interface"] == "virtio":
            dstr = dstr + ",if=virtio"
        else:
            dstr = dstr + ",if=" + drv["interface"]
            dstr = dstr + ",index=" + str(drv["index"])
        end
        dstr = dstr + ",media=" + drv["media"]
        push(parts, "-drive")
        push(parts, dstr)
        di = di + 1
    end

    # Network
    let ni = 0
    while ni < len(vm["net"]):
        let net = vm["net"][ni]
        if net["type"] == NET_USER:
            let nstr = "user"
            if net["hostfwd"] != "":
                nstr = nstr + ",hostfwd=" + net["hostfwd"]
            end
            push(parts, "-netdev")
            push(parts, nstr + ",id=net" + str(ni))
            push(parts, "-device")
            push(parts, net["model"] + ",netdev=net" + str(ni))
        end
        if net["type"] == NET_TAP:
            push(parts, "-netdev")
            push(parts, "tap,id=net" + str(ni) + ",ifname=" + net["ifname"])
            push(parts, "-device")
            push(parts, net["model"] + ",netdev=net" + str(ni))
        end
        if net["type"] == NET_NONE:
            push(parts, "-nic")
            push(parts, "none")
        end
        ni = ni + 1
    end

    # Chardevs (for 9p shares etc)
    let ci = 0
    while ci < len(vm["chardevs"]):
        push(parts, "-fsdev")
        push(parts, vm["chardevs"][ci])
        ci = ci + 1
    end

    # Devices
    let dvi = 0
    while dvi < len(vm["devices"]):
        push(parts, "-device")
        push(parts, vm["devices"][dvi])
        dvi = dvi + 1
    end

    # Firmware config
    let fi = 0
    while fi < len(vm["fw_cfg"]):
        push(parts, "-fw_cfg")
        push(parts, "name=" + vm["fw_cfg"][fi]["name"] + ",file=" + vm["fw_cfg"][fi]["file"])
        fi = fi + 1
    end

    # GDB
    if vm["gdb_port"] > 0:
        push(parts, "-gdb")
        push(parts, "tcp::" + str(vm["gdb_port"]))
        push(parts, "-S")
    end

    # Flags
    if vm["daemonize"]:
        push(parts, "-daemonize")
    end
    if vm["snapshot"]:
        push(parts, "-snapshot")
    end
    if vm["no_reboot"]:
        push(parts, "-no-reboot")
    end
    if vm["no_shutdown"]:
        push(parts, "-no-shutdown")
    end

    # Extra args
    let ei = 0
    while ei < len(vm["extra_args"]):
        push(parts, vm["extra_args"][ei])
        ei = ei + 1
    end

    # Join into command string
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

# ========== QEMU disk image tools ==========

proc qemu_img_create(path, fmt, size):
    return "qemu-img create -f " + fmt + " " + path + " " + size
end

proc qemu_img_convert(src, src_fmt, dst, dst_fmt):
    return "qemu-img convert -f " + src_fmt + " -O " + dst_fmt + " " + src + " " + dst
end

proc qemu_img_resize(path, size):
    return "qemu-img resize " + path + " " + size
end

proc qemu_img_info(path):
    return "qemu-img info " + path
end

proc qemu_img_snapshot_create(path, snap_name):
    return "qemu-img snapshot -c " + snap_name + " " + path
end

proc qemu_img_snapshot_apply(path, snap_name):
    return "qemu-img snapshot -a " + snap_name + " " + path
end

proc qemu_img_snapshot_list(path):
    return "qemu-img snapshot -l " + path
end

# ========== Convenience VM presets ==========

proc baremetal_x86(name, kernel_elf):
    let vm = create_vm(name)
    vm = vm_set_arch(vm, ARCH_X86_64)
    vm = vm_set_machine(vm, MACH_Q35)
    vm = vm_set_memory(vm, "64M")
    vm = vm_boot_kernel(vm, kernel_elf, "")
    vm["no_reboot"] = true
    return vm
end

proc baremetal_arm64(name, kernel_elf):
    let vm = create_vm(name)
    vm = vm_set_arch(vm, ARCH_AARCH64)
    vm = vm_set_machine(vm, MACH_VIRT)
    vm = vm_set_cpu(vm, CPU_CORTEX_A72)
    vm = vm_set_memory(vm, "64M")
    vm = vm_boot_kernel(vm, kernel_elf, "")
    vm["no_reboot"] = true
    return vm
end

proc baremetal_riscv(name, kernel_elf):
    let vm = create_vm(name)
    vm = vm_set_arch(vm, ARCH_RISCV64)
    vm = vm_set_machine(vm, MACH_VIRT)
    vm = vm_set_memory(vm, "64M")
    vm = vm_boot_kernel(vm, kernel_elf, "")
    vm["no_reboot"] = true
    return vm
end

proc linux_vm(name, kernel, rootfs, cmdline):
    let vm = create_vm(name)
    vm = vm_set_arch(vm, ARCH_X86_64)
    vm = vm_set_machine(vm, MACH_Q35)
    vm = vm_set_cpu(vm, CPU_HOST)
    vm = vm_set_accel(vm, ACCEL_KVM)
    vm = vm_set_smp(vm, 2)
    vm = vm_set_memory(vm, "512M")
    vm = vm_boot_kernel(vm, kernel, cmdline)
    vm = vm_add_virtio_disk(vm, rootfs, FMT_QCOW2)
    vm = vm_add_net_user(vm, "tcp::2222-:22")
    vm = vm_add_virtio_rng(vm)
    return vm
end

proc dev_vm(name, kernel, rootfs, share_path):
    let vm = linux_vm(name, kernel, rootfs, "console=ttyS0 root=/dev/vda rw")
    vm = vm_add_9p_share(vm, "host_share", share_path, "mapped-xattr")
    vm = vm_add_virtio_serial(vm)
    return vm
end

proc test_kernel(kernel_elf, arch):
    let vm = create_vm("test")
    vm = vm_set_arch(vm, arch)
    vm = vm_set_memory(vm, "32M")
    vm = vm_set_display(vm, DISPLAY_NONE)
    vm = vm_set_serial(vm, SERIAL_STDIO)
    vm = vm_boot_kernel(vm, kernel_elf, "")
    vm["no_reboot"] = true
    vm["no_shutdown"] = true
    return vm
end

# ========== GDB integration ==========

proc gdb_connect_cmd(port):
    return "target remote :" + str(port)
end

proc gdb_script(kernel_elf, port):
    let nl = chr(10)
    let script = ""
    script = script + "file " + kernel_elf + nl
    script = script + "target remote :" + str(port) + nl
    script = script + "break kmain" + nl
    script = script + "continue" + nl
    return script
end

proc vm_debug(vm, port):
    vm = vm_set_gdb(vm, port)
    return vm
end
