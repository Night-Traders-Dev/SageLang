gc_disable()
# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: 123
# EXPECT: h-llo
# EXPECT: 3

import std.regex

# Basic match
print regex.test("hello", "say hello world")
print regex.full_match("abc", "abc")
print regex.full_match("abc", "abcd")

# Digit match
let m = regex.search("[0-9]+", "abc123def")
print m["text"]

# Replace
print regex.replace_first("e", "hello", "-")

# Find all
let matches = regex.find_all("[a-z]+", "hello world foo")
print len(matches)
