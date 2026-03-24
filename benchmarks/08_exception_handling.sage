# Exception handling — measures try/catch overhead
gc_disable()
let caught = 0
let i = 0
while i < 5000:
    try:
        if i % 3 == 0:
            raise "divisible by three"
    catch e:
        caught = caught + 1
    i = i + 1

print caught
