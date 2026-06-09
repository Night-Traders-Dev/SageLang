# EXPECT: 6
# EXPECT: true
# EXPECT: true
# EXPECT: olleh
# Test string module operations
import string
print string.find("hello world", "world")
print string.startswith("hello", "he")
print string.endswith("hello", "lo")
print string.reverse("hello")
