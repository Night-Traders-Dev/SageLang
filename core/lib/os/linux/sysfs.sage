gc_disable()
import io

# sysfs.sage — Linux /sys filesystem interface
#
# Read and navigate sysfs entries for device/driver/platform information.

# ----- Sysfs paths -----
let SYSFS_ROOT = "/sys"
let SYSFS_CLASS = "/sys/class"
let SYSFS_BLOCK = "/sys/block"
let SYSFS_BUS = "/sys/bus"
let SYSFS_DEVICES = "/sys/devices"
let SYSFS_MODULE = "/sys/module"
let SYSFS_FIRMWARE = "/sys/firmware"
let SYSFS_POWER = "/sys/power"
let SYSFS_KERNEL = "/sys/kernel"

# ========== Sysfs readers ==========

## Reads a sysfs attribute and trims whitespace.
proc read_sysfs_attr(path):
    let content = io.readfile(path)
    # Trim trailing whitespace and newlines
    return strip(content)
end

## Reads a sysfs attribute as an integer.
proc read_sysfs_int(path):
    let val = read_sysfs_attr(path)
    return int(val)
end

## Returns true if the given sysfs path exists.
proc device_exists(path):
    return io.exists(path)
end

# ========== Device info ==========

## Gets information about a block device.
proc get_block_device_info(dev_name):
    let info = {}
    let base = SYSFS_BLOCK + "/" + dev_name
    info["name"] = dev_name
    info["size_sectors"] = read_sysfs_attr(base + "/size")
    info["removable"] = read_sysfs_attr(base + "/removable")
    info["ro"] = read_sysfs_attr(base + "/ro")
    return info
end

## Gets information about a network device.
proc get_net_device_info(dev_name):
    let info = {}
    let base = SYSFS_CLASS + "/net/" + dev_name
    info["name"] = dev_name
    info["mtu"] = read_sysfs_attr(base + "/mtu")
    info["address"] = read_sysfs_attr(base + "/address")
    info["operstate"] = read_sysfs_attr(base + "/operstate")
    info["carrier"] = read_sysfs_attr(base + "/carrier")
    info["speed"] = read_sysfs_attr(base + "/speed")
    info["duplex"] = read_sysfs_attr(base + "/duplex")
    return info
end

## Gets information about a CPU.
proc get_cpu_info(cpu_id):
    let info = {}
    let base = SYSFS_DEVICES + "/system/cpu/cpu" + str(cpu_id)
    info["id"] = cpu_id
    info["online"] = read_sysfs_attr(base + "/online")
    info["freq_cur"] = read_sysfs_attr(base + "/cpufreq/scaling_cur_freq")
    info["freq_min"] = read_sysfs_attr(base + "/cpufreq/scaling_min_freq")
    info["freq_max"] = read_sysfs_attr(base + "/cpufreq/scaling_max_freq")
    info["governor"] = read_sysfs_attr(base + "/cpufreq/scaling_governor")
    return info
end

## Gets information about a thermal zone.
proc get_thermal_zone(zone_id):
    let info = {}
    let base = SYSFS_CLASS + "/thermal/thermal_zone" + str(zone_id)
    info["id"] = zone_id
    info["type"] = read_sysfs_attr(base + "/type")
    info["temp"] = read_sysfs_attr(base + "/temp")
    info["policy"] = read_sysfs_attr(base + "/policy")
    return info
end

## Gets information about a power supply.
proc get_power_supply_info(name):
    let info = {}
    let base = SYSFS_CLASS + "/power_supply/" + name
    info["name"] = name
    info["type"] = read_sysfs_attr(base + "/type")
    info["status"] = read_sysfs_attr(base + "/status")
    info["capacity"] = read_sysfs_attr(base + "/capacity")
    info["voltage_now"] = read_sysfs_attr(base + "/voltage_now")
    info["current_now"] = read_sysfs_attr(base + "/current_now")
    return info
end

# ========== Module info ==========

## Gets information about a kernel module.
proc get_module_info(mod_name):
    let info = {}
    let base = SYSFS_MODULE + "/" + mod_name
    info["name"] = mod_name
    info["refcnt"] = read_sysfs_attr(base + "/refcnt")
    return info
end

# ========== Platform info ==========

## Gets DMI platform information.
proc get_dmi_info():
    let info = {}
    let base = SYSFS_DEVICES + "/virtual/dmi/id"
    info["board_name"] = read_sysfs_attr(base + "/board_name")
    info["board_vendor"] = read_sysfs_attr(base + "/board_vendor")
    info["product_name"] = read_sysfs_attr(base + "/product_name")
    info["bios_vendor"] = read_sysfs_attr(base + "/bios_vendor")
    info["bios_version"] = read_sysfs_attr(base + "/bios_version")
    return info
end

# ========== Sysfs attribute codegen (for kernel modules) ==========

## Creates a sysfs attribute descriptor.
proc create_sysfs_attr(name, show_body, store_body):
    let s_attr = {}
    s_attr["name"] = name
    s_attr["show_body"] = show_body
    s_attr["store_body"] = store_body
    s_attr["mode"] = 420
    return s_attr
end

## Creates a read-only sysfs attribute descriptor.
proc create_sysfs_attr_ro(name, show_body):
    let sr_attr = {}
    sr_attr["name"] = name
    sr_attr["show_body"] = show_body
    sr_attr["store_body"] = []
    sr_attr["mode"] = 292
    return sr_attr
end

## Emits C code for a sysfs attribute.
proc emit_sysfs_attr_c(attr):
    let nl = chr(10)
    let name = attr["name"]
    let code = ""

    # Show function
    code = code + "static ssize_t " + name + "_show(struct device *dev, "
    code = code + "struct device_attribute *da, char *buf) {" + nl
    let si = 0
    while si < len(attr["show_body"]):
        code = code + "    " + attr["show_body"][si] + nl
        si = si + 1
    end
    code = code + "}" + nl + nl

    # Store function (if writable)
    if len(attr["store_body"]) > 0:
        code = code + "static ssize_t " + name + "_store(struct device *dev, "
        code = code + "struct device_attribute *da, const char *buf, size_t count) {" + nl
        let sti = 0
        while sti < len(attr["store_body"]):
            code = code + "    " + attr["store_body"][sti] + nl
            sti = sti + 1
        end
        code = code + "}" + nl + nl
        code = code + "static DEVICE_ATTR_RW(" + name + ");" + nl
    else:
        code = code + "static DEVICE_ATTR_RO(" + name + ");" + nl
    end

    return code
end
