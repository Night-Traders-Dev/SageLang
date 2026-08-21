let n = 100
let steps = 0
while n != 1:
    if n % 2 == 0:
        n = n / 2
    else:
        n = 3 * n + 1
    end
    steps = steps + 1
end
print steps
