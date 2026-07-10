# EXPECT: hello
# EXPECT: world
@VM
proc vm_forced():
    print "hello"

@no_vm
proc ast_forced():
    print "world"

vm_forced()
ast_forced()
