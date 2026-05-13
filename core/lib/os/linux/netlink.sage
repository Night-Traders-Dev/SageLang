gc_disable()

# netlink.sage — Linux Netlink socket interface
#
# Build and parse Netlink messages for kernel-userspace communication.
# Supports: NETLINK_ROUTE, NETLINK_GENERIC, NETLINK_KOBJECT_UEVENT.

# ----- Netlink protocol families -----
let NETLINK_ROUTE = 0
let NETLINK_UNUSED = 1
let NETLINK_USERSOCK = 2
let NETLINK_FIREWALL = 3
let NETLINK_SOCK_DIAG = 4
let NETLINK_NFLOG = 5
let NETLINK_XFRM = 6
let NETLINK_SELINUX = 7
let NETLINK_ISCSI = 8
let NETLINK_AUDIT = 9
let NETLINK_FIB_LOOKUP = 10
let NETLINK_CONNECTOR = 11
let NETLINK_NETFILTER = 12
let NETLINK_IP6_FW = 13
let NETLINK_DNRTMSG = 14
let NETLINK_KOBJECT_UEVENT = 15
let NETLINK_GENERIC = 16

# ----- Netlink message types -----
let NLMSG_NOOP = 1
let NLMSG_ERROR = 2
let NLMSG_DONE = 3
let NLMSG_OVERRUN = 4

# ----- Netlink message flags -----
let NLM_F_REQUEST = 1
let NLM_F_MULTI = 2
let NLM_F_ACK = 4
let NLM_F_ECHO = 8
let NLM_F_DUMP_INTR = 16
let NLM_F_ROOT = 256
let NLM_F_MATCH = 512
let NLM_F_ATOMIC = 1024
let NLM_F_DUMP = 768

# ----- RTM message types (routing) -----
let RTM_NEWLINK = 16
let RTM_DELLINK = 17
let RTM_GETLINK = 18
let RTM_NEWADDR = 20
let RTM_DELADDR = 21
let RTM_GETADDR = 22
let RTM_NEWROUTE = 24
let RTM_DELROUTE = 25
let RTM_GETROUTE = 26
let RTM_NEWNEIGH = 28
let RTM_DELNEIGH = 29
let RTM_GETNEIGH = 30
let RTM_NEWRULE = 32
let RTM_DELRULE = 33
let RTM_GETRULE = 34

# ----- IFLA attribute types -----
let IFLA_UNSPEC = 0
let IFLA_ADDRESS = 1
let IFLA_BROADCAST = 2
let IFLA_IFNAME = 3
let IFLA_MTU = 4
let IFLA_LINK = 5
let IFLA_QDISC = 6
let IFLA_STATS = 7
let IFLA_OPERSTATE = 16
let IFLA_GROUP = 27

# ----- Interface flags -----
let IFF_UP = 1
let IFF_BROADCAST = 2
let IFF_LOOPBACK = 8
let IFF_POINTOPOINT = 16
let IFF_RUNNING = 64
let IFF_MULTICAST = 4096
let IFF_PROMISC = 256

# ----- Netlink header (16 bytes) -----
let NLMSG_HDR_LEN = 16

# ========== Message builder ==========

proc create_nlmsg(msg_type, flags):
    let msg = {}
    msg["type"] = msg_type
    msg["flags"] = flags
    msg["seq"] = 1
    msg["pid"] = 0
    msg["attrs"] = []
    msg["payload"] = []
    return msg
end

proc nlmsg_set_seq(msg, seq):
    msg["seq"] = seq
    return msg
end

proc nlmsg_add_attr(msg, attr_type, data):
    let attr = {}
    attr["type"] = attr_type
    attr["data"] = data
    append(msg["attrs"], attr)
    return msg
end

proc nlmsg_add_attr_u32(msg, attr_type, val):
    let attr = {}
    attr["type"] = attr_type
    attr["format"] = "u32"
    attr["value"] = val
    append(msg["attrs"], attr)
    return msg
end

proc nlmsg_add_attr_str(msg, attr_type, val):
    let attr = {}
    attr["type"] = attr_type
    attr["format"] = "string"
    attr["value"] = val
    append(msg["attrs"], attr)
    return msg
end

# ========== Message serialization ==========

proc nlmsg_attr_len(attr):
    # NLA header is 4 bytes (2 len + 2 type)
    if attr["format"] == "u32":
        return 8
    end
    if attr["format"] == "string":
        # 4 + string len + 1 (null terminator), padded to 4
        let slen = len(attr["value"]) + 1
        let total = 4 + slen
        # Align to 4
        while total % 4 != 0:
            total = total + 1
        end
        return total
    end
    return 4
end

proc nlmsg_total_len(msg):
    let total = NLMSG_HDR_LEN
    let i = 0
    while i < len(msg["attrs"]):
        total = total + nlmsg_attr_len(msg["attrs"][i])
        i = i + 1
    end
    # Add ifinfomsg (16 bytes) for link messages
    if msg["type"] == RTM_GETLINK:
        total = total + 16
    end
    if msg["type"] == RTM_NEWLINK:
        total = total + 16
    end
    if msg["type"] == RTM_GETADDR:
        total = total + 8
    end
    return total
end

proc nlmsg_serialize(msg):
    let bytes = []
    let total = nlmsg_total_len(msg)

    # nlmsghdr: len(4), type(2), flags(2), seq(4), pid(4)
    # Write length as LE u32
    append(bytes, total % 256)
    append(bytes, (total / 256) % 256)
    append(bytes, (total / 65536) % 256)
    append(bytes, (total / 16777216) % 256)

    # Type as LE u16
    append(bytes, msg["type"] % 256)
    append(bytes, (msg["type"] / 256) % 256)

    # Flags as LE u16
    append(bytes, msg["flags"] % 256)
    append(bytes, (msg["flags"] / 256) % 256)

    # Seq as LE u32
    append(bytes, msg["seq"] % 256)
    append(bytes, (msg["seq"] / 256) % 256)
    append(bytes, (msg["seq"] / 65536) % 256)
    append(bytes, (msg["seq"] / 16777216) % 256)

    # PID as LE u32
    append(bytes, msg["pid"] % 256)
    append(bytes, (msg["pid"] / 256) % 256)
    append(bytes, (msg["pid"] / 65536) % 256)
    append(bytes, (msg["pid"] / 16777216) % 256)

    return bytes
end

# ========== Message parser ==========

proc nlmsg_parse_header(bytes, offset):
    let hdr = {}
    if len(bytes) < offset + NLMSG_HDR_LEN:
        hdr["error"] = "too short"
        return hdr
    end
    hdr["len"] = bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536 + bytes[offset + 3] * 16777216
    hdr["type"] = bytes[offset + 4] + bytes[offset + 5] * 256
    hdr["flags"] = bytes[offset + 6] + bytes[offset + 7] * 256
    hdr["seq"] = bytes[offset + 8] + bytes[offset + 9] * 256 + bytes[offset + 10] * 65536 + bytes[offset + 11] * 16777216
    hdr["pid"] = bytes[offset + 12] + bytes[offset + 13] * 256 + bytes[offset + 14] * 65536 + bytes[offset + 15] * 16777216
    return hdr
end

# ========== Request builders ==========

proc build_getlink_request(seq):
    let msg = create_nlmsg(RTM_GETLINK, NLM_F_REQUEST + NLM_F_DUMP)
    msg = nlmsg_set_seq(msg, seq)
    return msg
end

proc build_getaddr_request(seq):
    let msg = create_nlmsg(RTM_GETADDR, NLM_F_REQUEST + NLM_F_DUMP)
    msg = nlmsg_set_seq(msg, seq)
    return msg
end

proc build_getroute_request(seq):
    let msg = create_nlmsg(RTM_GETROUTE, NLM_F_REQUEST + NLM_F_DUMP)
    msg = nlmsg_set_seq(msg, seq)
    return msg
end

# ========== Convenience: interface info ==========

proc interface_info(name, flags, mtu):
    let iface = {}
    iface["name"] = name
    iface["flags"] = flags
    iface["mtu"] = mtu
    iface["up"] = (flags % 2) == 1
    iface["running"] = false
    # Check IFF_RUNNING (bit 6 = 64)
    let shifted = flags / 64
    if shifted % 2 == 1:
        iface["running"] = true
    end
    iface["loopback"] = false
    let shifted_lb = flags / 8
    if shifted_lb % 2 == 1:
        iface["loopback"] = true
    end
    return iface
end
