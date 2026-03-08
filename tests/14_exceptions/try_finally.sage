# EXPECT: caught
# EXPECT: finally ran
try:
    raise "error"
catch e:
    print("caught")
finally:
    print("finally ran")
