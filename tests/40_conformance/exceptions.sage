# Conformance: Exceptions (Spec §9)
# EXPECT: caught: bad
# EXPECT: cleanup
# EXPECT: instance error: oops
# String exceptions
try:
    raise "bad"
catch e:
    print "caught: " + e
finally:
    print "cleanup"

# Instance exceptions
class AppError:
    proc init(self, msg):
        self.msg = msg

try:
    raise AppError("oops")
catch e:
    print "instance error: " + e.msg
