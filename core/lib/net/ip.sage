# IP address parsing, validation, and subnet utilities

# Parse an IPv4 address string into a 32-bit integer
proc parse_v4(addr):
    let octets = []
    let current = ""
    for i in range(len(addr)):
        if addr[i] == ".":
            push(octets, tonumber(current))
            current = ""
        else:
            current = current + addr[i]
    if len(current) > 0:
        push(octets, tonumber(current))
    if len(octets) != 4:
        return -1
    for i in range(4):
        if octets[i] < 0 or octets[i] > 255:
            return -1
    return octets[0] * 16777216 + octets[1] * 65536 + octets[2] * 256 + octets[3]

# Convert a 32-bit integer back to dotted-quad string
proc to_string_v4(ip):
    let a = (ip >> 24) & 255
    let b = (ip >> 16) & 255
    let c = (ip >> 8) & 255
    let d = ip & 255
    return str(a) + "." + str(b) + "." + str(c) + "." + str(d)

# Validate an IPv4 address string
@inline
proc is_valid_v4(addr):
    return parse_v4(addr) >= 0

# Parse CIDR notation "192.168.1.0/24" into {network, mask, prefix_len}
proc parse_cidr(cidr):
    let slash_pos = -1
    for i in range(len(cidr)):
        if slash_pos < 0 and cidr[i] == "/":
            slash_pos = i
    if slash_pos < 0:
        return nil
    let addr_str = ""
    for i in range(slash_pos):
        addr_str = addr_str + cidr[i]
    let prefix_str = ""
    for i in range(len(cidr) - slash_pos - 1):
        prefix_str = prefix_str + cidr[slash_pos + 1 + i]
    let prefix_len = tonumber(prefix_str)
    if prefix_len < 0 or prefix_len > 32:
        return nil
    let ip = parse_v4(addr_str)
    if ip < 0:
        return nil
    let result = {}
    # Build netmask from prefix length
    let net_mask = 0
    if prefix_len > 0:
        net_mask = (4294967295 << (32 - prefix_len)) & 4294967295
    result["network"] = ip & net_mask
    result["mask"] = net_mask
    result["prefix_len"] = prefix_len
    result["broadcast"] = (ip & net_mask) | (4294967295 ^ net_mask)
    result["network_str"] = to_string_v4(ip & net_mask)
    result["mask_str"] = to_string_v4(net_mask)
    result["broadcast_str"] = to_string_v4(result["broadcast"])
    # Number of usable host addresses
    let host_bits = 32 - prefix_len
    if host_bits >= 2:
        result["host_count"] = (1 << host_bits) - 2
    else:
        result["host_count"] = 0
    return result

# Check if an IP is in a CIDR range
proc in_subnet(ip_str, cidr_str):
    let ip = parse_v4(ip_str)
    let cidr = parse_cidr(cidr_str)
    if ip < 0 or cidr == nil:
        return false
    return (ip & cidr["mask"]) == cidr["network"]

# Check if an address is a private/RFC1918 address
@inline
proc is_private(addr):
    let ip = parse_v4(addr)
    if ip < 0:
        return false
    # 10.0.0.0/8
    if (ip & 4278190080) == 167772160:
        return true
    # 172.16.0.0/12
    if (ip & 4293918720) == 2886729728:
        return true
    # 192.168.0.0/16
    if (ip & 4294901760) == 3232235520:
        return true
    return false

# Check if an address is loopback (127.0.0.0/8)
@inline
proc is_loopback(addr):
    let ip = parse_v4(addr)
    if ip < 0:
        return false
    return (ip & 4278190080) == 2130706432

# Check if an address is link-local (169.254.0.0/16)
@inline
proc is_link_local(addr):
    let ip = parse_v4(addr)
    if ip < 0:
        return false
    return (ip & 4294901760) == 2851995648

# Check if an address is multicast (224.0.0.0/4)
@inline
proc is_multicast(addr):
    let ip = parse_v4(addr)
    if ip < 0:
        return false
    return (ip & 4026531840) == 3758096384

# Check if an address is broadcast
@inline
proc is_broadcast(addr):
    let ip = parse_v4(addr)
    return ip == 4294967295

# Get the class of an IPv4 address (A/B/C/D/E)
proc address_class(addr):
    let ip = parse_v4(addr)
    if ip < 0:
        return "invalid"
    let first_octet = (ip >> 24) & 255
    if first_octet < 128:
        return "A"
    if first_octet < 192:
        return "B"
    if first_octet < 224:
        return "C"
    if first_octet < 240:
        return "D"
    return "E"

# Convert a netmask to prefix length
proc mask_to_prefix(mask_str):
    let mask = parse_v4(mask_str)
    if mask < 0:
        return -1
    let count = 0
    let m = mask
    while m > 0:
        if (m & 2147483648) != 0:
            count = count + 1
        else:
            return count
        m = (m << 1) & 4294967295
    return count

# Convert a prefix length to netmask string
proc prefix_to_mask(prefix_len):
    if prefix_len < 0 or prefix_len > 32:
        return "0.0.0.0"
    let mask = 0
    if prefix_len > 0:
        mask = (4294967295 << (32 - prefix_len)) & 4294967295
    return to_string_v4(mask)

# Well-known addresses
comptime:
    let LOCALHOST = "127.0.0.1"
    let ANY = "0.0.0.0"
    let BROADCAST = "255.255.255.255"
    let DNS_GOOGLE = "8.8.8.8"
    let DNS_CLOUDFLARE = "1.1.1.1"
