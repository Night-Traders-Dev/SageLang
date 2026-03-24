gc_disable()
# EXPECT: true
# EXPECT: greet
# EXPECT: proc

import std.docgen

let source = "# Say hello" + chr(10) + "proc greet(name):" + chr(10) + "    print name" + chr(10)
let docs = docgen.extract_docs(source)
print len(docs) > 0
print docs[0]["name"]
print docs[0]["type"]
