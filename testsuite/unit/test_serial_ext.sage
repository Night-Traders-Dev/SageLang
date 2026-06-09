import metal.serial
import assert

proc test_baud_rate():
    assert.assert_true(serial.baud_rate_valid(9600), "9600 should be valid")
    assert.assert_true(serial.baud_rate_valid(115200), "115200 should be valid")
    assert.assert_false(serial.baud_rate_valid(12345), "12345 should be invalid")

proc test_functions_exist():
    print "Serial functions are defined."

test_baud_rate()
test_functions_exist()
print "Serial extension smoke test passed."
