# Math Library Module
# Basic mathematical functions

proc sqrt(x):
    # Simple Newton's method for square root
    if x < 0:
        raise "Cannot compute square root of negative number"
    
    if x == 0:
        return 0
    
    let guess = x / 2
    let epsilon = 0.00001
    let iterations = 0
    let max_iter = 100
    
    while iterations < max_iter:
        let new_guess = (guess + x / guess) / 2
        let diff = guess - new_guess
        if diff < 0:
            diff = 0 - diff
        
        if diff < epsilon:
            return new_guess
        
        guess = new_guess
        iterations = iterations + 1
    
    return guess

proc abs(x):
    if x < 0:
        return 0 - x
    return x

proc max(a, b):
    if a > b:
        return a
    return b

proc min(a, b):
    if a < b:
        return a
    return b

proc pow(base, exp):
    if exp == 0:
        return 1
    
    let result = base
    let i = 1
    
    while i < exp:
        result = result * base
        i = i + 1
    
    return result

# Math constants
let PI = 3.14159265359
let E = 2.71828182846
