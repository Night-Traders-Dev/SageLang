gc_disable()
# EXPECT: 1
# EXPECT: true
# EXPECT: true
# EXPECT: true

import llm.rag

let store = rag.create_store()
rag.add_document(store, "Sage uses a concurrent tri-color mark-sweep garbage collector with SATB write barriers for sub-millisecond STW pauses.", {"topic": "gc"})
print len(store["documents"])

# Retrieve
let results = rag.retrieve(store, "garbage collector", 3)
print len(results) > 0

# Context building
let ctx = rag.build_context(store, "garbage collector", 3)
print len(ctx) > 0

# Chunking
let chunks = rag.chunk_text("abcdefghij", 4, 1)
print len(chunks) > 0
