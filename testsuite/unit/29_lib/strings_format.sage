# EXPECT: 00042
# EXPECT: hi---
# EXPECT: [hello]
# EXPECT: a,b,c
# EXPECT: hello-world
# EXPECT: hello_world
# Test strings module: pad_left, pad_right, surround, csv, dash_case, snake_case
from strings import pad_left, pad_right, surround, csv, dash_case, snake_case

print pad_left("42", 5, "0")
print pad_right("hi", 5, "-")
print surround("hello", "[", "]")
print csv(["a", "b", "c"])
print dash_case("hello world")
print snake_case("hello-world")
