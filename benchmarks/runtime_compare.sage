proc lcg_step(x):
    return ((x * 1103515245) + 12345) % 2147483647

proc mix(seed, rounds):
    let value = seed
    let i = 0
    while i < rounds:
        value = lcg_step(value)
        value = (value + ((i * 97) % 89)) % 2147483647
        i = i + 1
    return value

proc benchmark():
    let passes = 12
    let data = [17, 31, 43, 59, 61, 73, 89, 97, 101, 109, 127, 131, 149, 157, 173, 181, 191, 199, 211, 223, 239, 251, 263, 271, 283, 293, 307, 313, 331, 347, 359, 373]

    let total = 0
    let pass = 0
    while pass < passes:
        let i = 0
        while i < 32:
            let seed = data[i] + total + pass
            total = (total + mix(seed, 16)) % 2147483647
            i = i + 1
        pass = pass + 1
    return total

print benchmark()
