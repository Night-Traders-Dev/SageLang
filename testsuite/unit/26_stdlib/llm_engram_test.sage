gc_disable()
# EXPECT: 1
# EXPECT: true
# EXPECT: true
# EXPECT: 1
# EXPECT: true

import llm.engram

let mem = engram.create(engram.default_config())

# Store to working memory
engram.store_working(mem, "Sage uses indentation blocks", 0.8)
print len(mem["working"])

# Store to semantic memory
engram.store_semantic(mem, "GC is concurrent tri-color", 0.9)
print len(mem["semantic"]) == 1

# Recall by keyword
let results = engram.recall(mem, "GC", 5)
print len(results) > 0

# Consolidation
engram.store_episodic(mem, "Fixed parser bug", 0.7)
mem["episodic"][0]["access_count"] = 5
let consolidated = engram.consolidate(mem)
print consolidated

# Stats
let s = engram.stats(mem)
print s["total_stores"] > 0
