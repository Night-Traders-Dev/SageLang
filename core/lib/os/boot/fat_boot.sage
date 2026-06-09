## os.boot.fat_boot — Minimal FAT Reader for Bootloader Context
## No GC, no dynamic allocation — designed to work in pre-kernel environments.

## Mount a FAT volume from a disk device and partition start LBA
proc mount(disk_dev, partition_start_lba):
    # Read BPB
    return {
        "disk": disk_dev,
        "lba_start": partition_start_lba,
        # ... BPB info ...
    }
end

## Open and read a file from the volume into a destination buffer
proc open_file(vol, path, dest_buf):
    # Traversal logic
    # ...
    return 0 # Size of file read
end

## Read a directory entry
proc get_entry(vol, dir_cluster, name):
    return nil
end
