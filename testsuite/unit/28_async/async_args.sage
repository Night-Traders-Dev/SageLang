# EXPECT: 30
# Test async proc with arguments
async proc add(a, b):
    return a + b

let future = add(10, 20)
print await future
