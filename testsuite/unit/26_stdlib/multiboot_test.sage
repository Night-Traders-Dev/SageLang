gc_disable()
# EXPECT: header_created
# EXPECT: magic_correct
# EXPECT: checksum_valid
# EXPECT: PASS
let MAGIC = 3897507926
let ARCH = 0
let checksum = (0 - MAGIC - ARCH - 16) & 4294967295
let header = {}
header["magic"] = MAGIC
header["arch"] = ARCH
header["length"] = 16
header["checksum"] = checksum
if header["magic"] == MAGIC:
    print "header_created"
if MAGIC == 3897507926:
    print "magic_correct"
let sum = (header["magic"] + header["arch"] + header["length"] + header["checksum"]) & 4294967295
if sum == 0:
    print "checksum_valid"
print "PASS"
