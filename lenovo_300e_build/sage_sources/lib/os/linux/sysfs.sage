gc_disable()

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

proc read_sysfs_attr(path):
    let content = readfile(path)
    # Trim trailing newline
    let result = ""
    let i = 0
    while i < len(content):
        if content[i] != chr(10):
            result = result + content[i]
        end
        i = i + 1
    end
    return result
end

proc read_sysfs_int(path):
    let val = read_sysfs_attr(path)
    return int(val)
end

# ========== Device info ==========

proc get_block_device_info(dev_name):
    let info = {}
    let base = SYSFS_BLOCK + "/" + dev_name
    info["name"] = dev_name
    info["size_sectors"] = read_sysfs_attr(base + "/size")
    info["removable"] = read_sysfs_attr(base + "/removable")
    info["ro"] = read_sysfs_attr(base + "/ro")
    return info
end

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

proc get_thermal_zone(zone_id):
    let info = {}
    let base = SYSFS_CLASS + "/thermal/thermal_zone" + str(zone_id)
    info["id"] = zone_id
    info["type"] = read_sysfs_attr(base + "/type")
    info["temp"] = read_sysfs_attr(base + "/temp")
    info["policy"] = read_sysfs_attr(base + "/policy")
    return info
end

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

proc get_module_info(mod_name):
    let info = {}
    let base = SYSFS_MODULE + "/" + mod_name
    info["name"] = mod_name
    info["refcnt"] = read_sysfs_attr(base + "/refcnt")
    return info
end

# ========== Platform info ==========

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

proc create_sysfs_attr(name, show_body, store_body):
    let attr = {}
    attr["name"] = name
    attr["show_body"] = show_body
    attr["store_body"] = store_body
    attr["mode"] = 420
    return attr
end

proc create_sysfs_attr_ro(name, show_body):
    let attr = {}
    attr["name"] = name
    attr["show_body"] = show_body
    attr["store_body"] = []
    attr["mode"] = 292
    return attr
end

proc emit_sysfs_attr_c(attr):
    let nl = chr(10)
    let q = chr(34)
    let name = attr["name"]
    let code = ""

    # Show function
    code = code + "static ssize_t " + name + "_show(struct device *dev, struct device_attribute *da, char *buf) {" + nl
    let si = 0
    while si < len(attr["show_body"]):
        code = code + "    " + attr["show_body"][si] + nl
        si = si + 1
    end
    code = code + "}" + nl + nl

    # Store function (if writable)
    if len(attr["store_body"]) > 0:
        code = code + "static ssize_t " + name + "_store(struct device *dev, struct device_attribute *da, const char *buf, size_t count) {" + nl
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
