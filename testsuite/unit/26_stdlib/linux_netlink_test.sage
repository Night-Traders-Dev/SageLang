gc_disable()
# EXPECT: nl_protocols
# EXPECT: nl_msg_types
# EXPECT: nl_flags
# EXPECT: rtm_types
# EXPECT: msg_create
# EXPECT: msg_attr
# EXPECT: attr_len
# EXPECT: serialize_header
# EXPECT: parse_header
# EXPECT: interface_info
# EXPECT: PASS

# Test Netlink protocols
let NETLINK_ROUTE = 0
let NETLINK_GENERIC = 16
let NETLINK_KOBJECT_UEVENT = 15
if NETLINK_ROUTE == 0:
    if NETLINK_GENERIC == 16:
        print "nl_protocols"
    end
end

# Test message types
let NLMSG_NOOP = 1
let NLMSG_ERROR = 2
let NLMSG_DONE = 3
if NLMSG_ERROR == 2:
    if NLMSG_DONE == 3:
        print "nl_msg_types"
    end
end

# Test flags
let NLM_F_REQUEST = 1
let NLM_F_MULTI = 2
let NLM_F_ACK = 4
let NLM_F_DUMP = 768
if NLM_F_REQUEST == 1:
    if NLM_F_DUMP == 768:
        print "nl_flags"
    end
end

# Test RTM types
let RTM_NEWLINK = 16
let RTM_GETLINK = 18
let RTM_NEWADDR = 20
let RTM_GETADDR = 22
let RTM_GETROUTE = 26
if RTM_GETLINK == 18:
    if RTM_GETROUTE == 26:
        print "rtm_types"
    end
end

# Test message creation
proc create_nlmsg(msg_type, flags):
    let msg = {}
    msg["type"] = msg_type
    msg["flags"] = flags
    msg["seq"] = 1
    msg["pid"] = 0
    msg["attrs"] = []
    return msg
end

let msg = create_nlmsg(RTM_GETLINK, NLM_F_REQUEST + NLM_F_DUMP)
if msg["type"] == 18:
    if msg["flags"] == 769:
        if msg["seq"] == 1:
            print "msg_create"
        end
    end
end

# Test attribute adding
proc nlmsg_add_attr_u32(msg, atype, val):
    let attr = {}
    attr["type"] = atype
    attr["format"] = "u32"
    attr["value"] = val
    push(msg["attrs"], attr)
    return msg
end

proc nlmsg_add_attr_str(msg, atype, val):
    let attr = {}
    attr["type"] = atype
    attr["format"] = "string"
    attr["value"] = val
    push(msg["attrs"], attr)
    return msg
end

msg = nlmsg_add_attr_u32(msg, 4, 1500)
msg = nlmsg_add_attr_str(msg, 3, "eth0")
if len(msg["attrs"]) == 2:
    if msg["attrs"][0]["value"] == 1500:
        if msg["attrs"][1]["value"] == "eth0":
            print "msg_attr"
        end
    end
end

# Test attribute length calculation
proc nlmsg_attr_len(attr):
    if attr["format"] == "u32":
        return 8
    end
    if attr["format"] == "string":
        let slen = len(attr["value"]) + 1
        let total = 4 + slen
        while total % 4 != 0:
            total = total + 1
        end
        return total
    end
    return 4
end

let u32_len = nlmsg_attr_len(msg["attrs"][0])
let str_len = nlmsg_attr_len(msg["attrs"][1])
if u32_len == 8:
    if str_len == 12:
        print "attr_len"
    end
end

# Test serialization (nlmsghdr: 16 bytes)
proc nlmsg_serialize(msg_in):
    let bytes = []
    let total = 16
    # len as LE u32
    push(bytes, total & 255)
    push(bytes, (total >> 8) & 255)
    push(bytes, 0)
    push(bytes, 0)
    # type as LE u16
    push(bytes, msg_in["type"] & 255)
    push(bytes, (msg_in["type"] >> 8) & 255)
    # flags as LE u16
    push(bytes, msg_in["flags"] & 255)
    push(bytes, (msg_in["flags"] >> 8) & 255)
    # seq as LE u32
    push(bytes, msg_in["seq"] & 255)
    push(bytes, 0)
    push(bytes, 0)
    push(bytes, 0)
    # pid as LE u32
    push(bytes, 0)
    push(bytes, 0)
    push(bytes, 0)
    push(bytes, 0)
    return bytes
end

let raw = nlmsg_serialize(msg)
if len(raw) == 16:
    if raw[0] == 16:
        if raw[4] == 18:
            print "serialize_header"
        end
    end
end

# Test header parsing
proc nlmsg_parse_header(bytes, offset):
    let hdr = {}
    hdr["len"] = bytes[offset] + bytes[offset + 1] * 256
    hdr["type"] = bytes[offset + 4] + bytes[offset + 5] * 256
    hdr["flags"] = bytes[offset + 6] + bytes[offset + 7] * 256
    hdr["seq"] = bytes[offset + 8]
    return hdr
end

let parsed = nlmsg_parse_header(raw, 0)
if parsed["len"] == 16:
    if parsed["type"] == 18:
        if parsed["seq"] == 1:
            print "parse_header"
        end
    end
end

# Test interface_info
let IFF_UP = 1
let IFF_RUNNING = 64
let IFF_LOOPBACK = 8
proc interface_info(name, flags, mtu):
    let iface = {}
    iface["name"] = name
    iface["flags"] = flags
    iface["mtu"] = mtu
    iface["up"] = (flags & 1) == 1
    iface["running"] = false
    if (flags & 64) == 64:
        iface["running"] = true
    end
    iface["loopback"] = false
    if (flags & 8) == 8:
        iface["loopback"] = true
    end
    return iface
end

let eth = interface_info("eth0", IFF_UP + IFF_RUNNING, 1500)
if eth["name"] == "eth0":
    if eth["up"]:
        if eth["running"]:
            if eth["mtu"] == 1500:
                print "interface_info"
            end
        end
    end
end

print "PASS"
