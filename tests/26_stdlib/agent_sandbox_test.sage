gc_disable()
# EXPECT: 1
# EXPECT: true
# EXPECT: 7
# EXPECT: false

import agent.sandbox

# Extract code blocks
let text = "Here is code:" + chr(10) + "```sage" + chr(10) + "print 42" + chr(10) + "```"
let blocks = sandbox.extract_code_blocks(text)
print len(blocks)

# Safety check
let safe = sandbox.is_safe("print 42")
print safe["safe"]

# Math eval
print sandbox.eval_math("3 + 4")

# Unsafe code
let unsafe = sandbox.is_safe("ffi_open(lib)")
print unsafe["safe"]
