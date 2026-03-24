gc_disable()
# EXPECT: /foo/bar
# EXPECT: /
# EXPECT: /a/b
# EXPECT: bar.txt
# EXPECT: /foo
# EXPECT: txt
# EXPECT: true
# EXPECT: hello
# EXPECT: 5
# EXPECT: true

import os.vfs

# Path utilities
print vfs.normalize_path("//foo///bar")
print vfs.normalize_path("/a/b/../..")
print vfs.join_path("/a", "b")
print vfs.basename("/foo/bar.txt")
print vfs.dirname("/foo/bar.txt")
print vfs.extension("/foo/bar.txt")

# In-memory filesystem
let memfs = vfs.create_memfs()
let v = vfs.create_vfs()
vfs.mount(v, "/", memfs)

# Write a file and read it back
vfs.memfs_write(memfs, "/hello.txt", [104, 101, 108, 108, 111])

let st = vfs.vfs_stat(v, "/hello.txt")
print st["is_file"]

let fh = vfs.vfs_open(v, "/hello.txt", 1)
let data = vfs.vfs_read(fh, 5)
let text = ""
for i in range(len(data)):
    text = text + chr(data[i])
print text
print vfs.vfs_tell(fh)
vfs.vfs_close(fh)
print fh["closed"]
