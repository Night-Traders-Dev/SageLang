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
    let max_iter = 100
    let i = 0
    
    while i < max_iter:
        let new_guess = (guess + x / guess) / 2
        let diff = guess - new_guess
        
        # Check if close enough (use abs)
        let check_diff = diff
        if check_diff < 0:
            check_diff = 0 - check_diff
        
        if check_diff < epsilon:
            return new_guess
        
        guess = new_guess
        i = i + 1
    
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
    let count = 1
    
    while count < exp:
        result = result * base
        count = count + 1
    
    return result

# Math constants
let PI = 3.14159265359
let E = 2.71828182846
