# EXPECT: chip_ok
# EXPECT: gpio_ok
# EXPECT: flash_ok
# EXPECT: wifi_ok
# EXPECT: adc_ok
# EXPECT: periph_ok
# EXPECT: esptool_ok
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

# ADC1 channels, attenuation tables, and raw-to-mV conversion
if esp32.adc1_channel(36) == 0 and esp32.adc1_channel(32) == 4:
    if esp32.adc1_channel(27) == -1 and esp32.adc_fullscale_mv(11) == 3900:
        if esp32.adc_to_mv(4095, 11) == 3900 and esp32.adc_to_mv(-1, 11) == -1:
            print "adc_ok"

# Touch, RTC, PWM, and UART defaults
if esp32.touch_channel(4) == 0 and esp32.touch_channel(32) == 9:
    if esp32.rtc_capable(0) == true and esp32.rtc_capable(5) == false:
        if esp32.pwm_duty(100, 8) == 255 and esp32.pwm_duty(50, 8) == 127:
            if esp32.uart_needs_remap(1) == true and esp32.uart_needs_remap(2) == false:
                print "periph_ok"

# Flashing helpers: image fit check and the verified esptool recipe
let cmd = esp32.esptool_write_cmd("/dev/ttyUSB0", "firmware.bin")
if esp32.image_size_ok(1810976) == true and esp32.image_size_ok(0) == false:
    if contains(cmd, "460800") and contains(cmd, "dio") and contains(cmd, "firmware.bin"):
        print "esptool_ok"

print "PASS"
