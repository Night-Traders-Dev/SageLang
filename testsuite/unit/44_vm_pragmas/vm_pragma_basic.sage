# EXPECT: 42
@no_vm
proc ast_only():
    return 42

print(ast_only())
