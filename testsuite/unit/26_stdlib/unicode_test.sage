gc_disable()
# EXPECT: HELLO
# EXPECT: hello
# EXPECT: Hello World
# EXPECT: hello
# EXPECT: true
# EXPECT: true

import std.unicode

print unicode.to_upper("hello")
print unicode.to_lower("HELLO")
print unicode.to_title("hello world")
print unicode.trim("  hello  ")
print unicode.starts_with("hello world", "hello")
print unicode.ends_with("hello world", "world")
