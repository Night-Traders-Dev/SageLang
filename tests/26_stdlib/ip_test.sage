gc_disable()
# EXPECT: true
# EXPECT: 192.168.1.0
# EXPECT: 255.255.255.0
# EXPECT: 254
# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: C
# EXPECT: 24
# EXPECT: 255.255.255.0

import net.ip

print ip.is_valid_v4("192.168.1.1")

let cidr = ip.parse_cidr("192.168.1.0/24")
print cidr["network_str"]
print cidr["mask_str"]
print cidr["host_count"]

print ip.in_subnet("192.168.1.100", "192.168.1.0/24")
print ip.is_private("10.0.0.1")
print ip.is_private("8.8.8.8")

print ip.address_class("192.168.1.1")
print ip.mask_to_prefix("255.255.255.0")
print ip.prefix_to_mask(24)
