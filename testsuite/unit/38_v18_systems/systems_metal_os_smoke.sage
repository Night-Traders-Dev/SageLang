# EXPECT: metal gpio init ok
# EXPECT: os sync mutex locked
# EXPECT: os sync semaphore wait ok
# EXPECT: systems smoke test complete

import metal.gpio as gpio
import os.sync as sync

# Metal GPIO pin test
gpio.gpio_init(0x4000, 16)
gpio.pin_mode(0, gpio.PIN_OUTPUT)
gpio.digital_write(0, gpio.PIN_HIGH)
if gpio.pin_get_mode(0) == gpio.PIN_OUTPUT:
    print "metal gpio init ok"

# OS sync mutex test
let m = sync.mutex_create()
if sync.mutex_try_lock(m) == true:
    print "os sync mutex locked"
    sync.mutex_unlock(m)

# OS sync semaphore test
let s = sync.semaphore_create(1)
if sync.semaphore_try_wait(s) == true:
    print "os sync semaphore wait ok"
    sync.semaphore_post(s)

print "systems smoke test complete"
