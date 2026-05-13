# Array operations — measures dynamic array growth and iteration
arr = []
i = 0
while i < 50000:
    arr.append(i * 2)
    i = i + 1

total = 0
for x in arr:
    total = total + x

print(total)
print(len(arr))
