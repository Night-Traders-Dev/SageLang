# EXPECT: chip_ok
# EXPECT: gpio_ok
# EXPECT: flash_ok
# EXPECT: wifi_ok
# EXPECT: PASS
import esp32

# Chip identity
if esp32.CHIP_NAME == "ESP32" and esp32.CPU_CORES == 2:
    if esp32.CPU_FREQ_MHZ == 240:
        print "chip_ok"

# GPIO model: absent pads rejected, input-only pads read-only
if esp32.pin_valid(2) == true and esp32.pin_valid(20) == false:
    if esp32.pin_can_output(2) == true and esp32.pin_can_output(34) == false:
        if esp32.pin_is_strapping(0) == true and esp32.pin_is_flash(6) == true:
            print "gpio_ok"

# Flash layout and image magics (verified against real esptool dumps)
if esp32.flash_offset("bootloader") == 4096:
    if esp32.flash_offset("app") == 65536 and esp32.flash_offset("nvs") == -1:
        if esp32.boot_magic_ok(233) == true and esp32.part_magic_ok(170, 80) == true:
            print "flash_ok"

# Radio: classic ESP32 is 2.4GHz-only (no 5GHz CYW43-style radio)
if esp32.WIFI_SUPPORTS_5GHZ == false and esp32.WIFI_BAND_GHZ == 2.4:
    print "wifi_ok"

print "PASS"
