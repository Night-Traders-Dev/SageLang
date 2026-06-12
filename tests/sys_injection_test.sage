import sys

print "Testing sys.exec injection:"
sys.exec("echo hello; echo injected_exec")

print "\nTesting sys.shell_exec injection:"
let res = sys.shell_exec("echo world; echo injected_shell_exec")
print res
