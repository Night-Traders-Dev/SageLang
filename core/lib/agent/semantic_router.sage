gc_disable()
# Semantic Router - Fast command dispatch that bypasses the LLM
# Routes trivial commands to deterministic functions, reserving the
# heavy supervisor-worker architecture for complex/ambiguous tasks.
# Sub-millisecond latency, zero hallucination on matched commands.

# ============================================================================
# Route definition
# ============================================================================

proc create_route(name, keywords, handler, description):
    let route = {}
    route["name"] = name
    route["keywords"] = keywords
    route["handler"] = handler
    route["description"] = description
    route["hits"] = 0
    route["total_time"] = 0
    return route

# ============================================================================
# Router
# ============================================================================

proc create_router(threshold):
    let router = {}
    router["routes"] = []
    router["threshold"] = threshold
    router["fallback"] = nil
    router["total_queries"] = 0
    router["direct_hits"] = 0
    router["fallback_hits"] = 0
    return router

# Add a route
proc add_route(router, name, keywords, handler, description):
    push(router["routes"], create_route(name, keywords, handler, description))

# Set the fallback handler (LLM-based, for complex queries)
proc set_fallback(router, handler):
    router["fallback"] = handler

# ============================================================================
# Matching engine
# ============================================================================

# Score how well a query matches a route's keywords
proc score_match(query, keywords):
    let query_lower = to_lower(query)
    let score = 0
    let total_keywords = len(keywords)
    for i in range(total_keywords):
        if contains(query_lower, to_lower(keywords[i])):
            score = score + 1
    if total_keywords == 0:
        return 0
    return score / total_keywords

# Route a query — returns {matched, route_name, result} or falls back to LLM
proc route(router, query):
    router["total_queries"] = router["total_queries"] + 1
    let start = clock()
    # Score all routes
    let best_route = nil
    let best_score = 0
    for i in range(len(router["routes"])):
        let r = router["routes"][i]
        let score = score_match(query, r["keywords"])
        if score > best_score:
            best_score = score
            best_route = r
    # Check if best score exceeds threshold
    if best_route != nil and best_score >= router["threshold"]:
        best_route["hits"] = best_route["hits"] + 1
        router["direct_hits"] = router["direct_hits"] + 1
        let result = best_route["handler"](query)
        let elapsed = clock() - start
        best_route["total_time"] = best_route["total_time"] + elapsed
        let outcome = {}
        outcome["matched"] = true
        outcome["route"] = best_route["name"]
        outcome["result"] = result
        outcome["score"] = best_score
        outcome["latency_ms"] = elapsed * 1000
        return outcome
    # Fall back to LLM
    if router["fallback"] != nil:
        router["fallback_hits"] = router["fallback_hits"] + 1
        let result = router["fallback"](query)
        let elapsed = clock() - start
        let outcome = {}
        outcome["matched"] = false
        outcome["route"] = "fallback"
        outcome["result"] = result
        outcome["score"] = best_score
        outcome["latency_ms"] = elapsed * 1000
        return outcome
    let outcome = {}
    outcome["matched"] = false
    outcome["route"] = "none"
    outcome["result"] = nil
    outcome["score"] = 0
    return outcome

# ============================================================================
# Pre-built routes for common Sage commands
# ============================================================================

proc _rt_help(q):
    return "Commands: help, version, test, build, format, lint, repl"
proc _rt_version(q):
    return "Sage v1.0.0"
proc _rt_test(q):
    return "Run: bash tests/run_tests.sh"
proc _rt_build(q):
    return "Run: make or cmake -B build -DBUILD_SAGE=ON"
proc _rt_format(q):
    return "Run: sage fmt <file.sage>"
proc _rt_lint(q):
    return "Run: sage lint <file.sage>"
proc _rt_repl(q):
    return "Run: sage or sage --repl"
proc _rt_modules(q):
    return "127 library modules across 11 subdirectories"

proc add_sage_routes(router):
    add_route(router, "help", ["help", "what can", "commands"], _rt_help, "Show help")
    add_route(router, "version", ["version", "what version"], _rt_version, "Show version")
    add_route(router, "test", ["run test", "test suite"], _rt_test, "Run tests")
    add_route(router, "build", ["build", "compile", "make"], _rt_build, "Build Sage")
    add_route(router, "format", ["format", "fmt"], _rt_format, "Format code")
    add_route(router, "lint", ["lint", "linter"], _rt_lint, "Lint code")
    add_route(router, "repl", ["repl", "interactive"], _rt_repl, "Start REPL")
    add_route(router, "modules", ["how many modules", "module count"], _rt_modules, "Module count")

# ============================================================================
# Statistics
# ============================================================================

proc stats(router):
    let s = {}
    s["total_queries"] = router["total_queries"]
    s["direct_hits"] = router["direct_hits"]
    s["fallback_hits"] = router["fallback_hits"]
    if router["total_queries"] > 0:
        s["direct_rate"] = router["direct_hits"] / router["total_queries"]
    else:
        s["direct_rate"] = 0
    s["routes"] = len(router["routes"])
    return s

proc format_stats(router):
    let s = stats(router)
    let nl = chr(10)
    let out = "Semantic Router:" + nl
    out = out + "  Queries: " + str(s["total_queries"]) + nl
    out = out + "  Direct hits: " + str(s["direct_hits"]) + " (" + str((s["direct_rate"] * 100) | 0) + "%)" + nl
    out = out + "  Fallback: " + str(s["fallback_hits"]) + nl
    out = out + "  Routes: " + str(s["routes"]) + nl
    for i in range(len(router["routes"])):
        let r = router["routes"][i]
        if r["hits"] > 0:
            let avg = 0
            if r["hits"] > 0:
                avg = r["total_time"] / r["hits"] * 1000
            out = out + "    " + r["name"] + ": " + str(r["hits"]) + " hits, " + str(avg) + "ms avg" + nl
    return out

# ============================================================================
# Helpers
# ============================================================================

proc to_lower(s):
    let r = ""
    for i in range(len(s)):
        let c = ord(s[i])
        if c >= 65 and c <= 90:
            r = r + chr(c + 32)
        else:
            r = r + s[i]
    return r

proc contains(h, n):
    if len(n) > len(h):
        return false
    for i in range(len(h) - len(n) + 1):
        let f = true
        for j in range(len(n)):
            if not f:
                j = len(n)
            if f and h[i + j] != n[j]:
                f = false
        if f:
            return true
    return false
