import os.linux.sysfs as sysfs
import assert

## Test device_exists helper in sysfs
proc test_sysfs_device_exists():
    let exists_root = sysfs.device_exists("/sys")
    let exists_nonexistent = sysfs.device_exists("/nonexistent_sysfs_device_path_12345")

    assert.assert_true(exists_root, "/sys should exist")
    assert.assert_false(exists_nonexistent, "/nonexistent_sysfs_device_path_12345 should not exist")
    print "test_sysfs_device_exists PASSED"

test_sysfs_device_exists()
