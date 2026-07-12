# EXPECT: Runtime Error: Only instances and modules have properties.
# EXPECT: object: 
# EXPECT: hello worldobject: 
# EXPECT: hello worldRuntime Error: '.find' is not callable (type=2).
# EXPECT: Runtime Error: Only instances and modules have properties.
# EXPECT: object: 
# EXPECT: nil
# EXPECT: hello worldobject: 
# EXPECT: hello worldRuntime Error: '.find' is not callable (type=2).
# EXPECT: nil
# EXPECT: hello
let s = "hello world"
print s.find("world")
print s.find("xyz")
print s[0:5]
