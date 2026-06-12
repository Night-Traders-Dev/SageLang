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

## Writes a string to a sysfs attribute.
proc write_sysfs_attr(path, value):
    return io.writefile(path, str(value))
end

## Writes an integer to a sysfs attribute.
proc write_sysfs_int(path, value):
    return write_sysfs_attr(path, value)
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
    let info_net = {}
    let base_net = SYSFS_CLASS + "/net/" + dev_name
    info_net["name"] = dev_name
    info_net["mtu"] = read_sysfs_attr(base_net + "/mtu")
    info_net["address"] = read_sysfs_attr(base_net + "/address")
    info_net["operstate"] = read_sysfs_attr(base_net + "/operstate")
    info_net["carrier"] = read_sysfs_attr(base_net + "/carrier")
    info_net["speed"] = read_sysfs_attr(base_net + "/speed")
    info_net["duplex"] = read_sysfs_attr(base_net + "/duplex")
    return info_net
end

## Gets information about a CPU.
proc get_cpu_info(cpu_id):
    let info_cpu = {}
    let base_cpu = SYSFS_DEVICES + "/system/cpu/cpu" + str(cpu_id)
    info_cpu["id"] = cpu_id
    info_cpu["online"] = read_sysfs_attr(base_cpu + "/online")
    info_cpu["freq_cur"] = read_sysfs_attr(base_cpu + "/cpufreq/scaling_cur_freq")
    info_cpu["freq_min"] = read_sysfs_attr(base_cpu + "/cpufreq/scaling_min_freq")
    info_cpu["freq_max"] = read_sysfs_attr(base_cpu + "/cpufreq/scaling_max_freq")
    info_cpu["governor"] = read_sysfs_attr(base_cpu + "/cpufreq/scaling_governor")
    return info_cpu
end

## Gets information about a thermal zone.
proc get_thermal_zone(zone_id):
    let info_thermal = {}
    let base_thermal = SYSFS_CLASS + "/thermal/thermal_zone" + str(zone_id)
    info_thermal["id"] = zone_id
    info_thermal["type"] = read_sysfs_attr(base_thermal + "/type")
    info_thermal["temp"] = read_sysfs_attr(base_thermal + "/temp")
    info_thermal["policy"] = read_sysfs_attr(base_thermal + "/policy")
    return info_thermal
end

## Gets information about a power supply.
proc get_power_supply_info(name):
    let info_ps = {}
    let base_ps = SYSFS_CLASS + "/power_supply/" + name
    info_ps["name"] = name
    info_ps["type"] = read_sysfs_attr(base_ps + "/type")
    info_ps["status"] = read_sysfs_attr(base_ps + "/status")
    info_ps["capacity"] = read_sysfs_attr(base_ps + "/capacity")
    info_ps["voltage_now"] = read_sysfs_attr(base_ps + "/voltage_now")
    info_ps["current_now"] = read_sysfs_attr(base_ps + "/current_now")
    return info_ps
end

# ========== Module info ==========

## Gets information about a kernel module.
proc get_module_info(mod_name):
    let info_mod = {}
    let base_mod = SYSFS_MODULE + "/" + mod_name
    info_mod["name"] = mod_name
    info_mod["refcnt"] = read_sysfs_attr(base_mod + "/refcnt")
    return info_mod
end

# ========== Platform info ==========

## Gets DMI platform information.
proc get_dmi_info():
    let info_dmi = {}
    let base_dmi = SYSFS_DEVICES + "/virtual/dmi/id"
    info_dmi["board_name"] = read_sysfs_attr(base_dmi + "/board_name")
    info_dmi["board_vendor"] = read_sysfs_attr(base_dmi + "/board_vendor")
    info_dmi["product_name"] = read_sysfs_attr(base_dmi + "/product_name")
    info_dmi["bios_vendor"] = read_sysfs_attr(base_dmi + "/bios_vendor")
    info_dmi["bios_version"] = read_sysfs_attr(base_dmi + "/bios_version")
    return info_dmi
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
