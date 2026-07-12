# EXPECT: error: Unexpected character.
# EXPECT:   --> test_globals.sage:6:9
# EXPECT:   |
# EXPECT: 6 | print PI; print random(); print int(3.7)
# EXPECT:   |         ^
print PI; print random(); print int(3.7)
