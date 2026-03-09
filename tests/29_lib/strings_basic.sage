# EXPECT: [hello, world]
# EXPECT: hello world
# EXPECT: true
# EXPECT: 2
# EXPECT: ababab
# Test strings module: words, compact, contains, count_substring, repeat
from strings import words, compact, contains, count_substring, repeat

print words("  hello   world  ")
print compact("  hello   world  ")
print contains("hello world", "world")
print count_substring("abcabc", "abc")
print repeat("ab", 3)
