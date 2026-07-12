# EXPECT: (math.PI:, 3.14159)
# EXPECT: (math.random() >= 0:, true)
# EXPECT: (int(3.7):, 3)
# EXPECT: (int("42"):, 42)
import math

print("math.PI:", math.PI)
print("math.random() >= 0:", math.random() >= 0.0 and math.random() < 1.0)
print("int(3.7):", int(3.7))
print("int(\"42\"):", int("42"))