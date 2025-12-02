# lib/math.sage
# Math utilities module

proc sqrt(n):
    # Simple Newton-Raphson square root approximation
    if n < 0:
        raise "Cannot compute square root of negative number"
    
    if n == 0:
        return 0
    
    let guess = n / 2
    let epsilon = 0.0001
    let iterations = 0
    let max_iterations = 100
    
    while iterations < max_iterations:
        let next_guess = (guess + n / guess) / 2
        let diff = guess - next_guess
        if diff < 0:
            diff = 0 - diff
        
        if diff < epsilon:
            return next_guess
        
        guess = next_guess
        iterations = iterations + 1
    
    return guess

proc abs(n):
    # Return absolute value
    if n < 0:
        return 0 - n
    return n

proc max(a, b):
    # Return maximum of two numbers
    if a > b:
        return a
    return b

proc min(a, b):
    # Return minimum of two numbers
    if a < b:
        return a
    return b

proc pow(base, exponent):
    # Calculate base^exponent
    if exponent == 0:
        return 1
    
    let result = 1
    let i = 0
    while i < exponent:
        result = result * base
        i = i + 1
    
    return result

proc factorial(n):
    # Calculate factorial
    if n < 0:
        raise "Factorial not defined for negative numbers"
    
    if n == 0:
        return 1
    
    let result = 1
    let i = 1
    while i <= n:
        result = result * i
        i = i + 1
    
    return result

# Module constants
let PI = 3.14159265359
let E = 2.71828182846
