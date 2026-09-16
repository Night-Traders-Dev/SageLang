## esp32.sage — ESP32 (classic) board support for SageLang
##
## Covers the original ESP32 (e.g. ESP32-D0WD-V3, ESP-WROOM-32 / DevKitC):
## dual-core Xtensa LX6 @ 240MHz, 2.4GHz-only WiFi, 4MB SPI flash.
##
##   import esp32
##   if esp32.pin_can_output(2):
##       print "LED pin usable"
##   print esp32.describe()
##
## All helpers are pure (host-runnable); hardware access stays in `metal.*`.

import math

## ============================================================
## Chip identity (verified via esptool: ESP32-D0WD-V3 rev v3.1)
## ============================================================

let CHIP_NAME = "ESP32"
let CHIP_VARIANT = "ESP32-D0WD-V3"
let CPU_ARCH = "Xtensa LX6"
let CPU_CORES = 2
let CPU_FREQ_MHZ = 240
let HAS_LP_CORE = true

## ============================================================
## Radio: 2.4GHz WiFi only — the CYW43-style 5GHz radio does not
## exist on classic ESP32. Boards must join a 2.4GHz SSID.
## ============================================================

let WIFI_BAND_GHZ = 2.4
let WIFI_SUPPORTS_5GHZ = false
let HAS_BT = true
let HAS_BLE = true

## ============================================================
## SPI flash layout (standard 4MB DevKit map, byte offsets)
## ============================================================

let FLASH_SIZE_BYTES = 4194304
let FLASH_BOOTLOADER_OFFSET = 4096
let FLASH_PART_TABLE_OFFSET = 32768
let FLASH_APP_OFFSET = 65536

## First byte of a valid second-stage bootloader image.
let FLASH_BOOT_MAGIC = 233

## First two bytes of a valid partition table.
let FLASH_PART_MAGIC_0 = 170
let FLASH_PART_MAGIC_1 = 80

## ============================================================
## GPIO model: pads are numbered 0..39, but 20, 24, 28, 29, 30
## and 31 do not exist. 34..39 are input-only. 6, 7, 8 and 11
## are wired to the SPI flash — do not use them.
## ============================================================

let GPIO_MIN = 0
let GPIO_MAX = 39
let GPIO_ABSENT = [20, 24, 28, 29, 30, 31]
let GPIO_INPUT_ONLY_FIRST = 34
let GPIO_STRAPPING = [0, 2, 5, 12, 15]
let GPIO_FLASH_PINS = [6, 7, 8, 11]
let GPIO_ADC1_PINS = [32, 33, 34, 35, 36, 37, 38, 39]
let GPIO_DAC_PINS = [25, 26]

## UART0 is the USB-serial console on most DevKits.
let UART0_TX_PIN = 1
let UART0_RX_PIN = 3

## ============================================================
## esptool recipe verified against real hardware
## (CP2102 bridge, ROM bootloader, --no-stub at 115200).
## ============================================================

let ESPTOOL_BAUD = 460800
let ESPTOOL_FALLBACK_BAUD = 115200
let ESPTOOL_FLASH_MODE = "dio"
let ESPTOOL_FLASH_FREQ = "40m"
let ESPTOOL_WRITE_OFFSET = 0

## True when pin names a real ESP32 pad.
@inline
proc pin_valid(pin):
    if pin < GPIO_MIN or pin > GPIO_MAX:
        return false
    for missing in GPIO_ABSENT:
        if pin == missing:
            return false
    return true

## True when pin exists and can drive an output.
@inline
proc pin_can_output(pin):
    if pin_valid(pin) == false:
        return false
    if pin >= GPIO_INPUT_ONLY_FIRST:
        return false
    return true

## True for input-only pads (34..39, e.g. ADC1 sense inputs).
@inline
proc pin_is_input_only(pin):
    if pin_valid(pin) == false:
        return false
    return pin >= GPIO_INPUT_ONLY_FIRST

## True for boot strapping pins (must be safe at reset).
@inline
proc pin_is_strapping(pin):
    for s in GPIO_STRAPPING:
        if pin == s:
            return true
    return false

## True for pads wired to the SPI flash (must stay untouched).
@inline
proc pin_is_flash(pin):
    for f in GPIO_FLASH_PINS:
        if pin == f:
            return true
    return false

## True for ADC1-capable pads (ADC2 clashes with WiFi, so only
## ADC1 is listed here).
@inline
proc adc1_capable(pin):
    for a in GPIO_ADC1_PINS:
        if pin == a:
            return true
    return false

## True for the two DAC pads.
@inline
proc dac_capable(pin):
    for d in GPIO_DAC_PINS:
        if pin == d:
            return true
    return false

## Byte offset of a named flash region, or -1 when unknown.
proc flash_offset(name):
    if name == "bootloader":
        return FLASH_BOOTLOADER_OFFSET
    elif name == "partitions":
        return FLASH_PART_TABLE_OFFSET
    elif name == "app":
        return FLASH_APP_OFFSET
    return -1

## True when a byte equals the bootloader image magic (0xE9).
@inline
proc boot_magic_ok(magic):
    return magic == FLASH_BOOT_MAGIC

## True for the two partition-table magic bytes (0xAA, 0x50).
@inline
proc part_magic_ok(b0, b1):
    return b0 == FLASH_PART_MAGIC_0 and b1 == FLASH_PART_MAGIC_1

## True for esptool flash modes the classic ESP32 accepts.
@inline
proc valid_flash_mode(mode):
    return mode == "qio" or mode == "qout" or mode == "dio" or mode == "dout"

## ============================================================
## ADC: 12-bit SAR, use ADC1 (ADC2 clashes with WiFi).
## Channel map for GPIO32..39 (CH4..CH7, CH0..CH3).
## ============================================================

let ADC_BITS = 12
let ADC_MAX_RAW = 4095

## ADC1 channel for a pad, or -1 when the pad has no ADC1 channel.
proc adc1_channel(pin):
    if pin == 36:
        return 0
    elif pin == 37:
        return 1
    elif pin == 38:
        return 2
    elif pin == 39:
        return 3
    elif pin == 32:
        return 4
    elif pin == 33:
        return 5
    elif pin == 34:
        return 6
    elif pin == 35:
        return 7
    return -1

## Approximate full-scale input in millivolts for an attenuation
## setting in dB (0, 2.5, 6 or 11). Returns -1 when unknown.
proc adc_fullscale_mv(atten_db):
    if atten_db == 0:
        return 1100
    elif atten_db == 2.5:
        return 1500
    elif atten_db == 6:
        return 2200
    elif atten_db == 11:
        return 3900
    return -1

## Convert a raw 12-bit ADC reading to millivolts. Returns -1 on
## bad input (out-of-range raw value or unknown attenuation).
proc adc_to_mv(raw, atten_db):
    let fs = adc_fullscale_mv(atten_db)
    if fs < 0:
        return -1
    if raw < 0 or raw > ADC_MAX_RAW:
        return -1
    return raw * fs / ADC_MAX_RAW

## ============================================================
## Touch pads T0..T9 and RTC-capable pads.
## ============================================================

## Touch channel for a pad (T0..T9), or -1 when not touch-capable.
proc touch_channel(pin):
    if pin == 4:
        return 0
    elif pin == 0:
        return 1
    elif pin == 2:
        return 2
    elif pin == 15:
        return 3
    elif pin == 13:
        return 4
    elif pin == 12:
        return 5
    elif pin == 14:
        return 6
    elif pin == 27:
        return 7
    elif pin == 33:
        return 8
    elif pin == 32:
        return 9
    return -1

let GPIO_RTC_PADS = [0, 2, 4, 12, 13, 14, 15, 25, 26, 27, 32, 33, 34, 35, 36, 37, 38, 39]

## True for pads usable as RTC GPIOs (deep-sleep wake sources).
@inline
proc rtc_capable(pin):
    for r in GPIO_RTC_PADS:
        if pin == r:
            return true
    return false

## ============================================================
## LEDC PWM: 16 channels; duty range depends on timer bit width.
## ============================================================

let PWM_CHANNELS = 16
let PWM_MAX_BITS = 20

## Duty count for percent (0..100) at a given timer width in bits.
## Values outside 0..100 clamp to the rails; fractions floor down
## because hardware duty registers take integers.
proc pwm_duty(percent, bits):
    let top = 1
    var i = 0
    while i < bits:
        top = top * 2
        i = i + 1
    top = top - 1
    if percent <= 0:
        return 0
    if percent >= 100:
        return top
    return math.floor(percent * top / 100)

## ============================================================
## UART: only UART0 is wired to the USB-serial bridge by default.
## UART1 defaults (TX 10 / RX 9) sit on flash pads and must be
## remapped; UART2 defaults (TX 17 / RX 16) are free to use.
## ============================================================

let UART0_DEFAULT_TX = 1
let UART0_DEFAULT_RX = 3
let UART1_DEFAULT_TX = 10
let UART1_DEFAULT_RX = 9
let UART2_DEFAULT_TX = 17
let UART2_DEFAULT_RX = 16

## True when a UART's default pins collide with SPI flash and the
## peripheral must be remapped before use (only UART1).
proc uart_needs_remap(uart):
    return uart == 1

## ============================================================
## Flashing helpers.
## ============================================================

## True for a firmware image size that fits the 4MB flash.
@inline
proc image_size_ok(size_bytes):
    return size_bytes > 0 and size_bytes <= FLASH_SIZE_BYTES

## The verified esptool write command for a full image at 0x0.
proc esptool_write_cmd(port, image):
    return "esptool --port " + port + " --baud " + str(ESPTOOL_BAUD) + " --no-stub --before default-reset --after hard-reset write-flash --flash-mode " + ESPTOOL_FLASH_MODE + " --flash-size detect --flash-freq " + ESPTOOL_FLASH_FREQ + " -z 0x0 " + image

## One-line human summary of the supported chip.
proc describe():
    return CHIP_NAME + " " + CHIP_VARIANT + " (" + CPU_ARCH + " x" + str(CPU_CORES) + " @" + str(CPU_FREQ_MHZ) + "MHz, WiFi " + str(WIFI_BAND_GHZ) + "GHz only)"
