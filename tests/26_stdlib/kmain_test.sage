gc_disable()
# EXPECT: kernel_created
# EXPECT: version_correct
# EXPECT: PASS
let kernel = {}
kernel["name"] = "SageOS"
kernel["version"] = "0.1.0"
kernel["running"] = false
if kernel["name"] == "SageOS":
    print "kernel_created"
if kernel["version"] == "0.1.0":
    print "version_correct"
print "PASS"
