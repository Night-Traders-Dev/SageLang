# EXPECT: normalize_ok
# EXPECT: join_ok
# EXPECT: dirname_ok
# EXPECT: basename_ok
# EXPECT: extension_ok
# EXPECT: mount_ok
# EXPECT: PASS
import os.vfs as vfs

# normalize_path
if vfs.normalize_path("/foo//bar/../baz") == "/foo/baz":
    if vfs.normalize_path("/") == "/":
        if vfs.normalize_path("/a/b/c/../../d") == "/a/d":
            print "normalize_ok"
        end
    end
end

# join_path
if vfs.join_path("/foo", "bar/baz") == "/foo/bar/baz":
    if vfs.join_path("/foo", "/abs") == "/abs":
        print "join_ok"
    end
end

# dirname
if vfs.dirname("/foo/bar/baz") == "/foo/bar":
    if vfs.dirname("/foo") == "/":
        print "dirname_ok"
    end
end

# basename
if vfs.basename("/foo/bar/baz") == "baz":
    if vfs.basename("/foo") == "foo":
        print "basename_ok"
    end
end

# extension
if vfs.extension("/foo/bar.txt") == "txt":
    if vfs.extension("/foo/bar.tar.gz") == "gz":
        if vfs.extension("/foo/noext") == "":
            print "extension_ok"
        end
    end
end

# mount/umount/resolve
let v = vfs.create_vfs()
let backend = {}
backend["name"] = "testfs"
vfs.mount(v, "/mnt", backend)
let resolved = vfs.resolve_mount(v, "/mnt/foo/bar")
if resolved != nil:
    if resolved["backend"]["name"] == "testfs":
        let rel = vfs.relative_path("/mnt", "/mnt/foo/bar")
        if rel == "/foo/bar":
            vfs.umount(v, "/mnt")
            let gone = vfs.resolve_mount(v, "/mnt/foo")
            if gone == nil:
                print "mount_ok"
            end
        end
    end
end

print "PASS"
