# EXPECT: found
# EXPECT: not found
proc find_val(arr, target):
    for x in arr:
        if x == target:
            return "found"
    return "not found"
print(find_val([1, 2, 3], 2))
print(find_val([1, 2, 3], 9))
