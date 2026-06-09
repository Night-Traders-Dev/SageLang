# Test try/catch/raise in C backend
# Basic try/catch
try:
    raise "oops"
catch e:
    print e

# Try without exception
try:
    print "ok"
catch e:
    print "should not see this"

# Nested try/catch
try:
    try:
        raise "inner"
    catch e:
        print e
    print "after inner"
catch e:
    print "should not see this either"

# Finally block
try:
    print "in try"
catch e:
    print "caught"
finally:
    print "finally"
