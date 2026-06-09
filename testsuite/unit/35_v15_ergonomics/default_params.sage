# EXPECT: 8080
# EXPECT: 443
# EXPECT: 6
# EXPECT: 1
# Test default parameter values
proc connect(host, port=8080):
    print port

connect("localhost")
connect("example.com", 443)

proc add(a, b=0, c=0):
    print a + b + c

add(1, 2, 3)
add(1)
