## Unit test for metal.core RP2040 SIO features
import metal.core

## Unit test for SIO operations
proc test_sio():
    let id = core.rp2040_cpuid()
    let cid = core.cpu_id()
    if id != cid:
        print "FAIL: rp2040_cpuid mismatch"
        return false

    core.sio_gpio_set_mask(3)
    core.sio_gpio_clr_mask(2)
    core.sio_gpio_xor_mask(1)

    core.sio_gpio_set_oe_mask(3)
    core.sio_gpio_clr_mask_oe(2)
    core.sio_gpio_xor_oe_mask(1)

    print "sio_unit_ok"
    return true

## Main entry point for unit test
proc main():
    if not test_sio():
        return
    print "PASS"

main()
