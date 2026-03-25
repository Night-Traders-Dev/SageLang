gc_disable()
# EXPECT: btrfs_magic
# EXPECT: PASS

import os.btrfs

# Check that the BTRFS magic string constant exists
if btrfs.BTRFS_MAGIC_STR == "_BHRfS_M"
    print "btrfs_magic"
end

print "PASS"
