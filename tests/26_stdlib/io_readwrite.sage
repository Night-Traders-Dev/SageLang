# EXPECT: hello sage
# EXPECT: true
# EXPECT: false
# Test io module read/write/exists/remove
import io
io.writefile("/tmp/sage_io_test.txt", "hello sage")
print io.readfile("/tmp/sage_io_test.txt")
print io.exists("/tmp/sage_io_test.txt")
io.remove("/tmp/sage_io_test.txt")
print io.exists("/tmp/sage_io_test.txt")
