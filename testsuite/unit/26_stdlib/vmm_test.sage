gc_disable()
# EXPECT: vmm_init
# EXPECT: page_mapped
# EXPECT: translation_works
# EXPECT: PASS
let page_table = {}
print "vmm_init"
let virt = 4194304
let phys = 2097152
let flags = 3
page_table[str(virt)] = phys
if dict_has(page_table, str(virt)):
    print "page_mapped"
let translated = page_table[str(virt)]
if translated == phys:
    print "translation_works"
print "PASS"
