gc_disable()
# EXPECT: syscall_init
# EXPECT: registered
# EXPECT: dispatch_works
# EXPECT: PASS
let table = []
for i in range(10):
    push(table, nil)
print "syscall_init"
let SYS_WRITE = 1
table[SYS_WRITE] = "write"
if table[SYS_WRITE] == "write":
    print "registered"
let result = table[SYS_WRITE]
if result == "write":
    print "dispatch_works"
print "PASS"
