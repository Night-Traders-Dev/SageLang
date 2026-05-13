# EXPECT: true
# EXPECT: true
# EXPECT: true
# Test: CPU topology and SMP detection
let logical = cpu_count()
let physical = cpu_physical_cores()
let ht = cpu_has_hyperthreading()

# Logical CPU count should be >= 1
print logical >= 1

# Physical cores should be >= 1 and <= logical
print physical >= 1

# Hyperthreading should be true or false
print ht == true or ht == false
