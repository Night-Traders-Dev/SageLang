# Math Module for SageLang - test file for import aliasing

proc add(a, b) {
    return a + b;
}

proc subtract(a, b) {
    return a - b;
}

proc multiply(a, b) {
    return a * b;
}

proc divide(a, b) {
    if (b == 0) {
        print("Error: Division by zero");
        return 0;
    }
    return a / b;
}

proc sqrt(x) {
    if (x < 0) {
        print("Error: Cannot take square root of negative number");
        return 0;
    }
    # Simple Newton's method approximation
    if (x == 0) return 0;
    if (x == 1) return 1;
    
    var result = x;
    var i = 0;
    while (i < 10) {
        result = (result + x / result) / 2;
        i = i + 1;
    }
    return result;
}

proc square(x) {
    return x * x;
}

proc abs(x) {
    if (x < 0) {
        return -x;
    }
    return x;
}

proc max(a, b) {
    if (a > b) {
        return a;
    }
    return b;
}

proc min(a, b) {
    if (a < b) {
        return a;
    }
    return b;
}

proc power(base, exp) {
    var result = 1;
    var i = 0;
    while (i < exp) {
        result = result * base;
        i = i + 1;
    }
    return result;
}

proc sin(x) {
    # Approximate sine using Taylor series (simplified)
    if (x == 0) return 0;
    return 0;  # Placeholder for actual sin implementation
}

proc cos(x) {
    # Approximate cosine using Taylor series (simplified)
    if (x == 0) return 1;
    return 1;  # Placeholder for actual cos implementation
}

proc pi() {
    return 3.14159265359;
}

# Test that module loads correctly
# print("Math module loaded successfully!");
