# EXPECT: uart_init_ok
# EXPECT: pl011_consts_ok
# EXPECT: baud_valid_ok
# EXPECT: baud_invalid_ok
# EXPECT: PASS
import metal.serial as serial

# NS16550A constants
if serial.COM1 == 1016 and serial.COM2 == 760:
    print "uart_init_ok"
end

# PL011 constants
if serial.PL011_DR == 0 and serial.PL011_FR == 24 and serial.PL011_CR == 48:
    print "pl011_consts_ok"
end

# baud_rate_valid
if serial.baud_rate_valid(115200) == true:
    if serial.baud_rate_valid(9600) == true:
        print "baud_valid_ok"
    end
end

if serial.baud_rate_valid(99999) == false:
    print "baud_invalid_ok"
end

print "PASS"
