gc_disable()
# EXPECT: kernel_created
# EXPECT: version_correct
# EXPECT: PASS

import os.kernel.kmain

# Create a kernel config struct
let k = kmain.create_kernel("TestOS", "1.0.0")

if k["name"] == "TestOS"
    print "kernel_created"
end

if k["version"] == "1.0.0"
    print "version_correct"
end

print "PASS"
