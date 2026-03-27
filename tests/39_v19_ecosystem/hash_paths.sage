# EXPECT: true
# EXPECT: true
# EXPECT: usr/local/bin
# EXPECT: /home/user
# EXPECT: file.sage
# EXPECT: .sage
# Test hash
print hash("hello") == hash("hello")
print hash("hello") != hash("world")

# Test path utilities
print path_join("usr", "local", "bin")
print path_dirname("/home/user/file.sage")
print path_basename("/home/user/file.sage")
print path_ext("/home/user/file.sage")
