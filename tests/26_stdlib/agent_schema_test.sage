gc_disable()
# EXPECT: true
# EXPECT: false
# EXPECT: true
# EXPECT: true

import agent.schema

# Create a schema
let s = schema.tool_schema("read_file", "Read a file", [schema.param("path", "string", true, "File path")], "string")
print s["name"] == "read_file"

# Validate args - missing required
let r1 = schema.validate_args(s, {})
print r1["valid"]

# Validate args - correct
let args = {}
args["path"] = "/tmp/test.txt"
let r2 = schema.validate_args(s, args)
print r2["valid"]

# Registry
let reg = schema.create_registry()
proc mock_read(a):
    return "file contents"
schema.register(reg, s, mock_read)
let result = schema.execute(reg, "read_file", args)
print result["success"]
