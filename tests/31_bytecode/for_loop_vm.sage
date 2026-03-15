# RUN: bytecode-run
# EXPECT: 6
# EXPECT: outer

let item = "outer"
let total = 0

for item in [1, 2, 3]:
    total = total + item

print total
print item
