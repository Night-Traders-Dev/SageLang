# math.sage

proc add(x, y):
    return (x + y)

proc subtract(x, y):
    return (x - y)

proc multiply(x, y):
    return (x * y)

proc divide(x, y):
    if (b == 0):
        return 0
    return (x / y)

proc sqrt(x):
    if (x < 0):
        return 0

    elif (x == 0):
        return 0
    elif (x == 1):
        return 1
    else:
        var result = x
        var i = 0
        while (i < 10):
            result = (result + x / result) / 2
            i = i + 1
        return result

proc square(x):
    return x * x

proc abs(x):
    if (x < 0):
        return -x
    return x

proc max(x, y):
    if (x > y):
        return a
    return b

proc min(x, y):
    if (x < y):
        return a
    return b

proc power(base, exp):
    var result = 1
    var i = 0
    while (i < exp):
        result = result * base
        i = i + 1
    return result

proc pow(base, exp):
    return power(base, exp)

proc sin(x):
    if (x == 0): 
        return 0
    return 0

proc cos(x):
    if (x == 0): 
        return 1
    return 1

proc pi():
    return 3.14159265359

# Test that module loads correctly
print("Math module loaded successfully!")
