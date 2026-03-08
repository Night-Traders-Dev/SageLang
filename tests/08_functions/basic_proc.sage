# EXPECT: hello from proc
# EXPECT: 42
proc greet():
    print("hello from proc")
greet()
proc answer():
    return 42
print(answer())
