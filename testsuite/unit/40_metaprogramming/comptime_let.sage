# EXPECT: 3.14159
# EXPECT: [0, 1, 4, 9, 16]
# Test comptime block producing values used later

comptime:
    let PI = 3.14159

print PI

comptime:
    let squares = []
    for i in range(5):
        push(squares, i * i)

print squares
