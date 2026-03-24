# Loop summation — measures raw loop and arithmetic throughput
let n = 100000
let total = 0
let i = 0
while i < n:
    total = total + i
    i = i + 1
print total
