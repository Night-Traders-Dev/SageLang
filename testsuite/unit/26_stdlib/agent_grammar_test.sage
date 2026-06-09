gc_disable()
# EXPECT: true
# EXPECT: read_file
# EXPECT: false
# EXPECT: true

import agent.grammar

# Valid tool call
let r1 = grammar.validate_tool_call("TOOL: read_file(/tmp/test.txt)")
print r1["valid"]
print r1["name"]

# Invalid format
let r2 = grammar.validate_tool_call("just some text")
print r2["valid"]

# Sage code validation
let r3 = grammar.validate_sage_code("proc hello():" + chr(10) + "    print 42")
print r3["valid"]
