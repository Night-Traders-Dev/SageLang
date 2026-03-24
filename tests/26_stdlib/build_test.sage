gc_disable()
# EXPECT: myapp
# EXPECT: 1.0.0
# EXPECT: 1
# EXPECT: 2.0.0
# EXPECT: true

import std.build

let proj = build.create_project("myapp", "1.0.0")
print proj["name"]
print proj["version"]

build.add_dep(proj, "json", ">=1.0")
print len(proj["dependencies"])

# Version parsing
let v = build.parse_version("1.5.3")
let v2 = build.bump_major(v)
print v2["string"]

# Serialization
let output = build.to_string(proj)
print len(output) > 0
