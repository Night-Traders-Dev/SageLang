# Exception handling — measures try/catch overhead
caught = 0
i = 0
while i < 5000:
    try:
        if i % 3 == 0:
            raise Exception("divisible by three")
    except Exception:
        caught = caught + 1
    i = i + 1

print(caught)
