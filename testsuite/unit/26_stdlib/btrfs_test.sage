gc_disable()
# EXPECT: btrfs_magic
# EXPECT: PASS
let magic = "_BHRfS_M"
if len(magic) == 8:
    print "btrfs_magic"
print "PASS"
