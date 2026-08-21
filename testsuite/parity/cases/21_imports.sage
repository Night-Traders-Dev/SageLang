# PARITY: interp-only
import math
print math.sqrt(16)
import io
print "io-imported"
io.writefile("/tmp/sage_parity_io.txt", "parity")
print io.readfile("/tmp/sage_parity_io.txt")
print io.exists("/tmp/sage_parity_io.txt")
import option
let s = option.Some(42)
print option.is_some(s)
print option.unwrap(s)
