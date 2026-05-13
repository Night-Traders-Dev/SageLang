gc_disable()
# EXPECT: script_generated
# EXPECT: has_entry
# EXPECT: has_text
# EXPECT: PASS
let script = "ENTRY(_start)" + chr(10) + "SECTIONS {" + chr(10) + "  .text : { *(.text) }" + chr(10) + "}"
if len(script) > 10:
    print "script_generated"
if contains(script, "ENTRY"):
    print "has_entry"
if contains(script, ".text"):
    print "has_text"
print "PASS"

proc contains(h, n):
    if len(n) > len(h):
        return false
    for i in range(len(h) - len(n) + 1):
        let found = true
        for j in range(len(n)):
            if h[i + j] != n[j]:
                found = false
                break
        if found:
            return true
    return false
