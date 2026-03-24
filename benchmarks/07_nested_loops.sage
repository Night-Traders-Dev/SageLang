# Nested loops with break/continue — measures control flow
let count = 0
let i = 0
while i < 500:
    let j = 0
    while j < 500:
        if (i + j) % 7 == 0:
            j = j + 1
            continue
        if j > 400:
            break
        count = count + 1
        j = j + 1
    i = i + 1

print count
