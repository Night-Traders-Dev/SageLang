gc_disable()
# EXPECT: f2fs_magic
# EXPECT: block_size
# EXPECT: PASS
let F2FS_MAGIC = 4076150800
let BLOCK_SIZE = 4096
if F2FS_MAGIC > 0:
    print "f2fs_magic"
if BLOCK_SIZE == 4096:
    print "block_size"
print "PASS"
