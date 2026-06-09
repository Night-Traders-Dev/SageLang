gc_disable()

# devicetree.sage — Device Tree overlay and runtime interface
#
# Build and manipulate Device Tree overlays for Linux kernel configuration.
# Generates DTS (Device Tree Source) suitable for dtc compilation.

# ----- Node types -----
let DT_ROOT = "/"
let DT_SOC = "soc"
let DT_CHOSEN = "chosen"
let DT_MEMORY = "memory"
let DT_CPUS = "cpus"

# ========== DT Node ==========

proc create_dt_node(name):
    let node = {}
    node["name"] = name
    node["properties"] = []
    node["children"] = []
    node["label"] = ""
    node["phandle"] = 0
    return node
end

proc dt_set_label(node, label):
    node["label"] = label
    return node
end

proc dt_add_prop(node, name, value):
    let prop = {}
    prop["name"] = name
    prop["value"] = value
    append(node["properties"], prop)
    return node
end

proc dt_add_prop_str(node, name, value):
    let prop = {}
    prop["name"] = name
    prop["value"] = chr(34) + value + chr(34)
    prop["type"] = "string"
    append(node["properties"], prop)
    return node
end

proc dt_add_prop_u32(node, name, value):
    let prop = {}
    prop["name"] = name
    prop["value"] = "<" + str(value) + ">"
    prop["type"] = "u32"
    append(node["properties"], prop)
    return node
end

proc dt_add_prop_u32_array(node, name, values):
    let val_str = "<"
    let i = 0
    while i < len(values):
        if i > 0:
            val_str = val_str + " "
        end
        val_str = val_str + str(values[i])
        i = i + 1
    end
    val_str = val_str + ">"
    let prop = {}
    prop["name"] = name
    prop["value"] = val_str
    prop["type"] = "u32_array"
    append(node["properties"], prop)
    return node
end

proc dt_add_prop_empty(node, name):
    let prop = {}
    prop["name"] = name
    prop["value"] = ""
    prop["type"] = "empty"
    append(node["properties"], prop)
    return node
end

proc dt_add_child(node, child):
    append(node["children"], child)
    return node
end

# ========== DTS generation ==========

proc emit_dts_prop(prop, indent_str):
    if dict_has(prop, "type"):
        if prop["type"] == "empty":
            return indent_str + prop["name"] + ";"
        end
    end
    return indent_str + prop["name"] + " = " + str(prop["value"]) + ";"
end

proc emit_dts_node(node, indent_level):
    let nl = chr(10)
    let indent = ""
    let i = 0
    while i < indent_level:
        indent = indent + chr(9)
        i = i + 1
    end

    let code = ""

    # Node header
    if node["label"] != "":
        code = code + indent + node["label"] + ": " + node["name"] + " {" + nl
    else:
        code = code + indent + node["name"] + " {" + nl
    end

    # Properties
    let pi = 0
    while pi < len(node["properties"]):
        code = code + emit_dts_prop(node["properties"][pi], indent + chr(9)) + nl
        pi = pi + 1
    end

    # Children
    if len(node["children"]) > 0:
        code = code + nl
    end
    let ci = 0
    while ci < len(node["children"]):
        code = code + emit_dts_node(node["children"][ci], indent_level + 1) + nl
        ci = ci + 1
    end

    code = code + indent + "};"
    return code
end

# ========== Overlay generation ==========

proc create_overlay(target_path, overlay_node):
    let ov = {}
    ov["target_path"] = target_path
    ov["node"] = overlay_node
    return ov
end

proc emit_overlay_dts(overlays):
    let nl = chr(10)
    let code = "/dts-v1/;" + nl
    code = code + "/plugin/;" + nl + nl
    code = code + "/ {" + nl

    let i = 0
    while i < len(overlays):
        let ov = overlays[i]
        code = code + chr(9) + "fragment@" + str(i) + " {" + nl
        code = code + chr(9) + chr(9) + "target-path = " + chr(34) + ov["target_path"] + chr(34) + ";" + nl
        code = code + chr(9) + chr(9) + "__overlay__ {" + nl

        # Emit overlay node content
        let pi = 0
        while pi < len(ov["node"]["properties"]):
            code = code + emit_dts_prop(ov["node"]["properties"][pi], chr(9) + chr(9) + chr(9)) + nl
            pi = pi + 1
        end
        let ci = 0
        while ci < len(ov["node"]["children"]):
            code = code + emit_dts_node(ov["node"]["children"][ci], 3) + nl
            ci = ci + 1
        end

        code = code + chr(9) + chr(9) + "};" + nl
        code = code + chr(9) + "};" + nl + nl
        i = i + 1
    end

    code = code + "};" + nl
    return code
end

# ========== Common device nodes ==========

proc gpio_node(label, base_addr, ngpio):
    let node = create_dt_node("gpio@" + str(base_addr))
    node = dt_set_label(node, label)
    node = dt_add_prop_str(node, "compatible", "gpio-controller")
    node = dt_add_prop_u32_array(node, "reg", [base_addr, 4096])
    node = dt_add_prop_empty(node, "gpio-controller")
    node = dt_add_prop_u32(node, "#gpio-cells", 2)
    node = dt_add_prop_u32(node, "ngpios", ngpio)
    return node
end

proc i2c_device_node(name, addr, compatible):
    let node = create_dt_node(name + "@" + str(addr))
    node = dt_add_prop_str(node, "compatible", compatible)
    node = dt_add_prop_u32(node, "reg", addr)
    node = dt_add_prop_str(node, "status", "okay")
    return node
end

proc spi_device_node(name, cs, compatible, max_freq):
    let node = create_dt_node(name + "@" + str(cs))
    node = dt_add_prop_str(node, "compatible", compatible)
    node = dt_add_prop_u32(node, "reg", cs)
    node = dt_add_prop_u32(node, "spi-max-frequency", max_freq)
    return node
end

proc uart_node(label, base_addr, irq, clock_freq):
    let node = create_dt_node("serial@" + str(base_addr))
    node = dt_set_label(node, label)
    node = dt_add_prop_str(node, "compatible", "ns16550a")
    node = dt_add_prop_u32_array(node, "reg", [base_addr, 256])
    node = dt_add_prop_u32(node, "interrupts", irq)
    node = dt_add_prop_u32(node, "clock-frequency", clock_freq)
    node = dt_add_prop_str(node, "status", "okay")
    return node
end
