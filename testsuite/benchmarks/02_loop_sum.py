# Loop summation — measures raw loop and arithmetic throughput
n = 100000
total = 0
i = 0
while i < n:
    total = total + i
    i = i + 1
print(total)
