gc_disable()
# EXPECT: true
# EXPECT: true
# EXPECT: true

import agent.semantic_router

let router = semantic_router.create_router(0.3)

proc help_handler(q):
    return "help response"

proc version_handler(q):
    return "v1.0.0"

semantic_router.add_route(router, "help", ["help", "commands"], help_handler, "Show help")
semantic_router.add_route(router, "version", ["version", "what version"], version_handler, "Show version")

# Direct match
let r1 = semantic_router.route(router, "help me please")
print r1["matched"]

# Version match
let r2 = semantic_router.route(router, "what version is this")
print r2["matched"]

# Stats
let s = semantic_router.stats(router)
print s["direct_hits"] > 0
