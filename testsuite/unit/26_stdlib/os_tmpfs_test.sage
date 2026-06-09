# EXPECT: create_ok
# EXPECT: file_ok
# EXPECT: dir_ok
# EXPECT: symlink_ok
# EXPECT: overwrite_ok
# EXPECT: delete_ok
# EXPECT: size_limit_ok
# EXPECT: PASS
import os.tmpfs as tmpfs

# Create filesystem
let fs = tmpfs.create_tmpfs(65536)
print "create_ok"

# Create and read file
let f = tmpfs.create_file(fs, "/hello.txt", "hello world", 420)
if f != nil:
    let data = tmpfs.read_file(fs, "/hello.txt")
    if data == "hello world":
        print "file_ok"
    end
end

# Create directory and nested file
tmpfs.mkdir(fs, "/subdir", 493)
let f2 = tmpfs.create_file(fs, "/subdir/nested.txt", "nested", 420)
if f2 != nil:
    if tmpfs.read_file(fs, "/subdir/nested.txt") == "nested":
        print "dir_ok"
    end
end

# Symlink
tmpfs.symlink(fs, "/link.txt", "/hello.txt")
let ldata = tmpfs.read_file(fs, "/link.txt")
if ldata == "hello world":
    print "symlink_ok"
end

# Overwrite file
tmpfs.write_file(fs, "/hello.txt", "updated")
if tmpfs.read_file(fs, "/hello.txt") == "updated":
    print "overwrite_ok"
end

# Delete file
let ok = tmpfs.delete(fs, "/hello.txt")
if ok == true:
    if tmpfs.read_file(fs, "/hello.txt") == nil:
        print "delete_ok"
    end
end

# Size limit: create a filesystem with tiny limit
let small_fs = tmpfs.create_tmpfs(100)
let big_data = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
let big = tmpfs.create_file(small_fs, "/big.txt", big_data, 420)
if big == nil:
    print "size_limit_ok"
end

print "PASS"
