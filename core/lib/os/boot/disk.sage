## os.boot.disk — Abstract Disk I/O Backend
## Provides a layer for fetching raw sectors from BIOS, UEFI, or direct hardware.

## Open a disk device by ID
proc open(drive):
    # detect if bios/uefi/ata
    return {
        "id": drive,
        "type": "bios" # or "uefi", "ata"
    }
end

## Read a single sector from the device
proc read_sector(dev, lba):
    if dev["type"] == "bios":
        # Generate assembly for INT 0x13
        return nil
    end
    return nil
end

## Read multiple sectors from the device
proc read_sectors(dev, lba, count):
    return nil
end

## Probe for ATA PIO drives
proc probe_ata():
    import metal.core as metal
    # Probe ports 0x1F0, 0x170...
    return []
end

## Probe for AHCI (SATA) controllers
proc probe_ahci():
    return []
end
