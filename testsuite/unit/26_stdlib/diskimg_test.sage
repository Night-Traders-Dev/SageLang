gc_disable()
# EXPECT: image_created
# EXPECT: mbr_signature
# EXPECT: partition_entry
# EXPECT: PASS
let SECTOR_SIZE = 512
let MBR_SIG = 43605
let img = []
for i in range(SECTOR_SIZE):
    push(img, 0)
img[510] = 85
img[511] = 170
if len(img) == 512:
    print "image_created"
if img[510] == 85 and img[511] == 170:
    print "mbr_signature"
let part_type = 6
if part_type == 6:
    print "partition_entry"
print "PASS"
