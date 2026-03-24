gc_disable()
# EXPECT: A
# EXPECT: AAAA
# EXPECT: NXDOMAIN
# EXPECT: 13
# EXPECT: example.com
# EXPECT: true
# EXPECT: 1

import net.dns

print dns.type_name(1)
print dns.type_name(28)
print dns.rcode_name(3)

# Test name encoding
let encoded = dns.encode_name("example.com")
print len(encoded)

# Test name reading from encoded bytes
let nr = dns.read_name(encoded, 0)
print nr["name"]

# Test query building
let query = dns.build_query("example.com", 1, 1234)
print len(query) > 0

# Parse the query we just built
let msg = dns.parse_message(query)
print msg["header"]["qdcount"]
