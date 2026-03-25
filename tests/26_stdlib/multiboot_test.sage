gc_disable()
# EXPECT: header_created
# EXPECT: tag_end_works
# EXPECT: serialize_works
# EXPECT: checksum_valid
# EXPECT: PASS

import os.boot.multiboot

# Create a multiboot2 header
let hdr = multiboot.create_header()
if hdr["magic"] == multiboot.MAGIC
    print "header_created"
end

# Create an end tag and verify its length
let et = multiboot.tag_end()
if len(et) == 8
    print "tag_end_works"
end

# Add a framebuffer tag then serialize the header
let fb = multiboot.tag_framebuffer(800, 600, 32)
push(hdr["tags"], fb)

let bytes = multiboot.serialize(hdr)
if len(bytes) >= 16
    print "serialize_works"
end

# Validate the serialized header (checksum must be correct)
let valid = multiboot.validate(bytes)
if valid
    print "checksum_valid"
end

print "PASS"
