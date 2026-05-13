# EXPECT: hello	world
# EXPECT: line1
# EXPECT: line2
# EXPECT: she said "hi"
# EXPECT: back\slash
# EXPECT: A
# Tab escape
print "hello\tworld"
# Newline escape
print "line1\nline2"
# Quote escape
print "she said \"hi\""
# Backslash escape
print "back\\slash"
# Hex escape
print "\x41"
