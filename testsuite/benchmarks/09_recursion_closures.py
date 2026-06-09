# Closures and higher-order functions — measures closure overhead
def make_adder(n):
    def add(x):
        return x + n
    return add

add5 = make_adder(5)
add10 = make_adder(10)

total = 0
i = 0
while i < 100000:
    total = total + add5(i) + add10(i)
    i = i + 1

print(total)
