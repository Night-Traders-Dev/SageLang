# EXPECT: 120
# EXPECT: 3628800
# Test comptime() expression form

proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

# comptime() as an expression evaluates at compile time
let five_fact = comptime(factorial(5))
print five_fact

let ten_fact = comptime(factorial(10))
print ten_fact
