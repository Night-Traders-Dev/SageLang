# Array operations — measures dynamic array growth and iteration
let arr = []
let i = 0
while i < 50000:
    push(arr, i * 2)
    i = i + 1

let total = 0
for x in arr:
    total = total + x

print total
print len(arr)
