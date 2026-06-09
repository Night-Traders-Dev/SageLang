import os.vfs
let memfs = vfs.create_memfs()
let v = vfs.create_vfs()
vfs.mount(v, "/", memfs)

# 1. create /tmp
vfs.memfs_mkdir(memfs, "/tmp")

# 2. write a file without updating parent
vfs.memfs_write(memfs, "/tmp/file", [104, 101, 108, 108, 111])

# 3. try to rmdir
let res = vfs.vfs_rmdir(v, "/tmp")
print "rmdir result: " + str(res)
