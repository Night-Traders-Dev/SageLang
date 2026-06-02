import dicts
import arrays
import strings

print "--- Truthiness ---"
if 0:
    print "0 is truthy"
else:
    print "0 is falsy"
end

print "--- Atomic Initialization ---"
let a = atomic_new(42)
print "atomic_load before store: " + str(atomic_load(a))
atomic_store(a, 100)
print "atomic_load after store: " + str(atomic_load(a))

print "--- Dictionary Size Optimization ---"
let d = {"x": 1, "y": 2, "z": 3}
print "dicts.size: " + str(dicts.size(d))
print "len(d): " + str(len(d))

print "--- Array Unique ---"
let arr = [1, "1", 1, "1", 2]
print "arrays.unique: " + str(arrays.unique(arr))

print "--- String Repeat Optimization ---"
print "strings.repeat('abc', 3): " + strings.repeat("abc", 3)
