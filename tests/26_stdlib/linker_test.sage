gc_disable()
# EXPECT: script_generated
# EXPECT: has_entry
# EXPECT: has_text
# EXPECT: uefi_script_works
# EXPECT: PASS

import os.boot.linker

# Generate a default linker script
let cfg = linker.default_config()
let script = linker.generate_script(cfg)

if len(script) > 0
    print "script_generated"
end

# Check script contains ENTRY directive
if contains(script, "ENTRY(_start)")
    print "has_entry"
end

# Check script contains .text section
if contains(script, ".text")
    print "has_text"
end

# Generate UEFI linker script
let uefi = linker.generate_uefi_script()
if contains(uefi, "efi_main")
    print "uefi_script_works"
end

print "PASS"
