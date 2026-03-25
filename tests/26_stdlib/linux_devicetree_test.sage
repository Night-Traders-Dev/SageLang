gc_disable()
# EXPECT: node_created
# EXPECT: node_props
# EXPECT: node_children
# EXPECT: dts_output
# EXPECT: overlay_gen
# EXPECT: gpio_node
# EXPECT: i2c_device
# EXPECT: PASS

# Test DT node creation
proc create_dt_node(name):
    let node = {}
    node["name"] = name
    node["properties"] = []
    node["children"] = []
    node["label"] = ""
    return node

let root = create_dt_node("/")
if root["name"] == "/":
    if len(root["properties"]) == 0:
        print "node_created"

# Test adding properties
proc dt_add_prop_str(node, name, value):
    let prop = {}
    prop["name"] = name
    prop["value"] = chr(34) + value + chr(34)
    prop["type"] = "string"
    push(node["properties"], prop)
    return node

proc dt_add_prop_u32(node, name, value):
    let prop = {}
    prop["name"] = name
    prop["value"] = "<" + str(value) + ">"
    prop["type"] = "u32"
    push(node["properties"], prop)
    return node

proc dt_add_prop_empty(node, name):
    let prop = {}
    prop["name"] = name
    prop["value"] = ""
    prop["type"] = "empty"
    push(node["properties"], prop)
    return node

let soc = create_dt_node("soc")
soc = dt_add_prop_str(soc, "compatible", "simple-bus")
soc = dt_add_prop_u32(soc, "#address-cells", 1)
soc = dt_add_prop_empty(soc, "ranges")
if len(soc["properties"]) == 3:
    if soc["properties"][0]["type"] == "string":
        if soc["properties"][2]["type"] == "empty":
            print "node_props"

# Test children
proc dt_add_child(parent, child):
    push(parent["children"], child)
    return parent

let uart = create_dt_node("serial@10000000")
uart = dt_add_prop_str(uart, "compatible", "ns16550a")
uart = dt_add_prop_u32(uart, "clock-frequency", 1843200)
soc = dt_add_child(soc, uart)
if len(soc["children"]) == 1:
    if soc["children"][0]["name"] == "serial@10000000":
        print "node_children"

# Test DTS output
let nl = chr(10)
let tab = chr(9)
let dts = ""
dts = dts + "soc {" + nl
let pi = 0
while pi < len(soc["properties"]):
    let p = soc["properties"][pi]
    if p["type"] == "empty":
        dts = dts + tab + p["name"] + ";" + nl
    else:
        dts = dts + tab + p["name"] + " = " + str(p["value"]) + ";" + nl
    pi = pi + 1
dts = dts + "};" + nl
if contains(dts, "soc {"):
    if contains(dts, "ranges;"):
        if contains(dts, "compatible"):
            print "dts_output"

# Test overlay generation
let overlay_node = create_dt_node("overlay")
overlay_node = dt_add_prop_str(overlay_node, "status", "okay")
let ov_dts = "/dts-v1/;" + nl
ov_dts = ov_dts + "/plugin/;" + nl
ov_dts = ov_dts + "/ {" + nl
ov_dts = ov_dts + tab + "fragment@0 {" + nl
ov_dts = ov_dts + tab + tab + "target-path = " + chr(34) + "/soc/serial@10000000" + chr(34) + ";" + nl
ov_dts = ov_dts + tab + tab + "__overlay__ {" + nl
ov_dts = ov_dts + tab + tab + tab + "status = " + chr(34) + "okay" + chr(34) + ";" + nl
ov_dts = ov_dts + tab + tab + "};" + nl
ov_dts = ov_dts + tab + "};" + nl
ov_dts = ov_dts + "};" + nl
if contains(ov_dts, "/plugin/"):
    if contains(ov_dts, "__overlay__"):
        if contains(ov_dts, "target-path"):
            print "overlay_gen"

# Test GPIO node builder
proc gpio_node(label, base_addr, ngpio):
    let node = create_dt_node("gpio@" + str(base_addr))
    node["label"] = label
    node = dt_add_prop_str(node, "compatible", "gpio-controller")
    node = dt_add_prop_empty(node, "gpio-controller")
    node = dt_add_prop_u32(node, "ngpios", ngpio)
    return node

let gpio = gpio_node("gpio0", 1048576, 32)
if gpio["name"] == "gpio@1048576":
    if gpio["label"] == "gpio0":
        if len(gpio["properties"]) == 3:
            print "gpio_node"

# Test I2C device node
proc i2c_device_node(name, addr, compat):
    let node = create_dt_node(name + "@" + str(addr))
    node = dt_add_prop_str(node, "compatible", compat)
    node = dt_add_prop_u32(node, "reg", addr)
    return node

let sensor = i2c_device_node("bme280", 118, "bosch,bme280")
if sensor["name"] == "bme280@118":
    if sensor["properties"][0]["type"] == "string":
        print "i2c_device"

print "PASS"
