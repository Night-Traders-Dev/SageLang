# lib/utils.sage
# General utility functions

proc reverse_string(s):
    # Reverse a string (simple character-by-character)
    let length = len(s)
    let result = ""
    let i = length - 1
    
    while i >= 0:
        # Note: This is a simplified version
        # In a real implementation, we'd need string indexing
        i = i - 1
    
    return s  # Temporary - just return original

proc is_even(n):
    # Check if number is even
    let half = n / 2
    return half * 2 == n

proc is_odd(n):
    # Check if number is odd
    return not is_even(n)

proc clamp(value, min_val, max_val):
    # Clamp value between min and max
    if value < min_val:
        return min_val
    if value > max_val:
        return max_val
    return value

proc sum_array(arr):
    # Sum all elements in an array
    let total = 0
    for item in arr:
        total = total + item
    return total

proc average(arr):
    # Calculate average of array elements
    let total = sum_array(arr)
    let count = len(arr)
    if count == 0:
        return 0
    return total / count
