import sys
import assert

# Verify safe commands work
let res1 = sys.exec("echo hello")
assert.assert_true(res1 == 0, "Normal command should succeed")

# Verify leading option hyphen is rejected
let res2 = sys.exec("-la")
assert.assert_true(res2 == -1, "Leading option flag should be rejected")

# Verify leading whitespace followed by option hyphen is rejected
let res3 = sys.exec(" -la")
assert.assert_true(res3 == -1, "Leading space before option flag should be rejected")

let res4 = sys.exec("\t--option")
assert.assert_true(res4 == -1, "Leading tab before option flag should be rejected")

print("sys.exec security tests passed!")
