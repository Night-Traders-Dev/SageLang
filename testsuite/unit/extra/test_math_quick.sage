# EXPECT: (PI:, 3.14159)
# EXPECT: (random >= 0:, true)
# EXPECT: (int(3.7):, 3)
import math
print("PI:", math.PI)
print("random >= 0:", math.random() >= 0.0 and math.random() < 1.0)
print("int(3.7):", int(3.7))