import os.vfs as vfs

proc assert_eq(actual, expected, msg):
    if actual == expected:
        print("PASS: " + msg)
    else:
        print("FAIL: " + msg + " (expected " + str(expected) + ", got " + str(actual) + ")")
    end
end

proc test_extension():
    print("Testing extension()...")
    assert_eq(vfs.extension(".profile"), "", "extension of .profile should be empty")
    assert_eq(vfs.extension("test.sage"), "sage", "extension of test.sage should be sage")
    assert_eq(vfs.extension(".config.yaml"), "yaml", "extension of .config.yaml should be yaml")
    assert_eq(vfs.extension("no_ext"), "", "extension of no_ext should be empty")
end

proc test_append_mode():
    print("Testing VFS_APPEND...")
    let my_vfs = vfs.create_vfs()
    let mem = vfs.create_memfs()
    vfs.mount(my_vfs, "/", mem)

    # Create a file with some content
    let h1 = vfs.vfs_open(my_vfs, "/log", vfs.VFS_WRITE | vfs.VFS_CREATE)
    vfs.vfs_write(h1, [65, 66, 67]) # "ABC"
    vfs.vfs_close(h1)

    # Open with APPEND
    let h2 = vfs.vfs_open(my_vfs, "/log", vfs.VFS_APPEND | vfs.VFS_WRITE)
    assert_eq(vfs.vfs_tell(h2), 3, "position after opening with VFS_APPEND should be at end")
    vfs.vfs_write(h2, [68, 69, 70]) # "DEF"
    vfs.vfs_close(h2)

    # Verify content
    let h3 = vfs.vfs_open(my_vfs, "/log", vfs.VFS_READ)
    let content = vfs.vfs_read(h3, 10)
    vfs.vfs_close(h3)
    assert_eq(len(content), 6, "appended file should have length 6")
    assert_eq(content[3], 68, "fourth byte should be 'D' (68)")
end

proc test_mkdir_listing():
    print("Testing vfs_mkdir parent listing...")
    let my_vfs = vfs.create_vfs()
    let mem = vfs.create_memfs()
    vfs.mount(my_vfs, "/", mem)

    vfs.vfs_mkdir(my_vfs, "/tmp")
    
    let entries = vfs.vfs_readdir(my_vfs, "/")
    let found = false
    for e in entries:
        if e["name"] == "tmp":
            found = true
        end
    end
    assert_eq(found, true, "/tmp should be found in / listing")
    
    vfs.vfs_open(my_vfs, "/file.txt", vfs.VFS_CREATE | vfs.VFS_WRITE)
    let entries2 = vfs.vfs_readdir(my_vfs, "/")
    let found_file = false
    for e in entries2:
        if e["name"] == "file.txt":
            found_file = true
        end
    end
    assert_eq(found_file, true, "/file.txt should be found in / listing")
end

test_extension()
test_append_mode()
test_mkdir_listing()
print("VFS tests completed.")
