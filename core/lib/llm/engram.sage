gc_disable()
# Engram - Persistent neural memory system for LLMs
# Provides episodic memory, semantic memory, working memory, and memory consolidation
# Inspired by human memory architecture for agentic LLM systems
#
# Memory types:
# - Working Memory: Active context window, decays rapidly
# - Episodic Memory: Specific events/interactions, timestamped
# - Semantic Memory: Distilled knowledge/facts, long-lived
# - Procedural Memory: Learned skills/procedures, pattern-based

# ============================================================================
# Memory entry
# ============================================================================

proc create_entry(content, memory_type, importance):
    let entry = {}
    entry["content"] = content
    entry["type"] = memory_type
    entry["importance"] = importance
    entry["timestamp"] = 0
    entry["access_count"] = 0
    entry["last_accessed"] = 0
    entry["decay"] = 1.0
    entry["embedding"] = nil
    entry["tags"] = []
    entry["associations"] = []
    return entry

proc tag_entry(entry, tag):
    push(entry["tags"], tag)

proc associate(entry, other_id):
    push(entry["associations"], other_id)

# ============================================================================
# Engram memory store
# ============================================================================

proc create(config):
    let mem = {}
    mem["working"] = []
    mem["episodic"] = []
    mem["semantic"] = []
    mem["procedural"] = []
    mem["working_capacity"] = 7
    mem["max_episodic"] = 1000
    mem["max_semantic"] = 500
    mem["decay_rate"] = 0.95
    mem["consolidation_threshold"] = 3
    mem["next_id"] = 1
    mem["total_stores"] = 0
    mem["total_recalls"] = 0
    mem["total_consolidations"] = 0
    if config != nil:
        if dict_has(config, "working_capacity"):
            mem["working_capacity"] = config["working_capacity"]
        if dict_has(config, "max_episodic"):
            mem["max_episodic"] = config["max_episodic"]
        if dict_has(config, "max_semantic"):
            mem["max_semantic"] = config["max_semantic"]
        if dict_has(config, "decay_rate"):
            mem["decay_rate"] = config["decay_rate"]
    return mem

# Default config
proc default_config():
    let cfg = {}
    cfg["working_capacity"] = 7
    cfg["max_episodic"] = 1000
    cfg["max_semantic"] = 500
    cfg["decay_rate"] = 0.95
    cfg["consolidation_threshold"] = 3
    return cfg

# ============================================================================
# Store operations
# ============================================================================

# Store to working memory (FIFO with capacity limit)
proc store_working(mem, content, importance):
    let entry = create_entry(content, "working", importance)
    entry["timestamp"] = mem["next_id"]
    mem["next_id"] = mem["next_id"] + 1
    push(mem["working"], entry)
    # Evict oldest if over capacity
    while len(mem["working"]) > mem["working_capacity"]:
        let oldest = mem["working"][0]
        # Before evicting, check if it should be promoted to episodic
        if oldest["importance"] > 0.5 or oldest["access_count"] >= 2:
            store_episodic(mem, oldest["content"], oldest["importance"])
        let new_working = []
        for i in range(len(mem["working"]) - 1):
            push(new_working, mem["working"][i + 1])
        mem["working"] = new_working
    mem["total_stores"] = mem["total_stores"] + 1
    return entry

# Store to episodic memory (specific events)
proc store_episodic(mem, content, importance):
    let entry = create_entry(content, "episodic", importance)
    entry["timestamp"] = mem["next_id"]
    mem["next_id"] = mem["next_id"] + 1
    push(mem["episodic"], entry)
    # Evict least important if over capacity
    if len(mem["episodic"]) > mem["max_episodic"]:
        let min_idx = 0
        let min_score = score_entry(mem["episodic"][0])
        for i in range(len(mem["episodic"])):
            let s = score_entry(mem["episodic"][i])
            if s < min_score:
                min_score = s
                min_idx = i
        let new_ep = []
        for i in range(len(mem["episodic"])):
            if i != min_idx:
                push(new_ep, mem["episodic"][i])
        mem["episodic"] = new_ep
    mem["total_stores"] = mem["total_stores"] + 1
    return entry

# Store to semantic memory (distilled knowledge)
proc store_semantic(mem, content, importance):
    let entry = create_entry(content, "semantic", importance)
    entry["timestamp"] = mem["next_id"]
    mem["next_id"] = mem["next_id"] + 1
    push(mem["semantic"], entry)
    if len(mem["semantic"]) > mem["max_semantic"]:
        let min_idx = 0
        let min_score = score_entry(mem["semantic"][0])
        for i in range(len(mem["semantic"])):
            let s = score_entry(mem["semantic"][i])
            if s < min_score:
                min_score = s
                min_idx = i
        let new_sem = []
        for i in range(len(mem["semantic"])):
            if i != min_idx:
                push(new_sem, mem["semantic"][i])
        mem["semantic"] = new_sem
    mem["total_stores"] = mem["total_stores"] + 1
    return entry

# Store a procedure/skill
proc store_procedural(mem, name, steps, importance):
    let entry = create_entry(name, "procedural", importance)
    entry["steps"] = steps
    entry["timestamp"] = mem["next_id"]
    mem["next_id"] = mem["next_id"] + 1
    push(mem["procedural"], entry)
    mem["total_stores"] = mem["total_stores"] + 1
    return entry

# ============================================================================
# Recall operations
# ============================================================================

# Score an entry for relevance (combines importance, recency, access frequency)
proc score_entry(entry):
    let recency_bonus = entry["decay"]
    let frequency_bonus = entry["access_count"] * 0.1
    return entry["importance"] * recency_bonus + frequency_bonus

# Recall from working memory (most recent, highest importance)
proc recall_working(mem, query):
    let best = nil
    let best_score = -1
    for i in range(len(mem["working"])):
        let entry = mem["working"][i]
        let s = score_entry(entry)
        # Simple keyword match boost
        if contains_keyword(entry["content"], query):
            s = s + 1.0
        if s > best_score:
            best_score = s
            best = entry
    if best != nil:
        best["access_count"] = best["access_count"] + 1
        mem["total_recalls"] = mem["total_recalls"] + 1
    return best

# Search all memory types
proc recall(mem, query, max_results):
    let results = []
    # Search working memory
    for i in range(len(mem["working"])):
        let entry = mem["working"][i]
        if contains_keyword(entry["content"], query):
            entry["access_count"] = entry["access_count"] + 1
            let r = {}
            r["entry"] = entry
            r["score"] = score_entry(entry) + 1.0
            r["source"] = "working"
            push(results, r)
    # Search episodic memory
    for i in range(len(mem["episodic"])):
        let entry = mem["episodic"][i]
        if contains_keyword(entry["content"], query):
            entry["access_count"] = entry["access_count"] + 1
            let r = {}
            r["entry"] = entry
            r["score"] = score_entry(entry) + 0.5
            r["source"] = "episodic"
            push(results, r)
    # Search semantic memory
    for i in range(len(mem["semantic"])):
        let entry = mem["semantic"][i]
        if contains_keyword(entry["content"], query):
            entry["access_count"] = entry["access_count"] + 1
            let r = {}
            r["entry"] = entry
            r["score"] = score_entry(entry) + 0.8
            r["source"] = "semantic"
            push(results, r)
    # Sort by score (selection sort descending)
    for i in range(len(results)):
        let max_idx = i
        for j in range(len(results) - i):
            if results[i + j]["score"] > results[max_idx]["score"]:
                max_idx = i + j
        let temp = results[i]
        results[i] = results[max_idx]
        results[max_idx] = temp
    # Limit results
    let limited = []
    for i in range(max_results):
        if i < len(results):
            push(limited, results[i])
    mem["total_recalls"] = mem["total_recalls"] + 1
    return limited

# ============================================================================
# Memory consolidation (episodic -> semantic)
# ============================================================================

# Consolidate frequently accessed episodic memories into semantic knowledge
proc consolidate(mem):
    let threshold = mem["consolidation_threshold"]
    let consolidated = 0
    let remaining = []
    for i in range(len(mem["episodic"])):
        let entry = mem["episodic"][i]
        if entry["access_count"] >= threshold:
            store_semantic(mem, entry["content"], entry["importance"] * 1.2)
            consolidated = consolidated + 1
        else:
            push(remaining, entry)
    mem["episodic"] = remaining
    mem["total_consolidations"] = mem["total_consolidations"] + consolidated
    return consolidated

# ============================================================================
# Decay (simulate memory fading over time)
# ============================================================================

proc apply_decay(mem):
    let rate = mem["decay_rate"]
    for i in range(len(mem["working"])):
        mem["working"][i]["decay"] = mem["working"][i]["decay"] * rate
    for i in range(len(mem["episodic"])):
        mem["episodic"][i]["decay"] = mem["episodic"][i]["decay"] * rate
    # Semantic memories decay much slower
    for i in range(len(mem["semantic"])):
        mem["semantic"][i]["decay"] = mem["semantic"][i]["decay"] * (1 - (1 - rate) * 0.1)

# Forget memories that have decayed below threshold
proc forget(mem, threshold):
    let forgotten = 0
    let new_ep = []
    for i in range(len(mem["episodic"])):
        if mem["episodic"][i]["decay"] >= threshold:
            push(new_ep, mem["episodic"][i])
        else:
            forgotten = forgotten + 1
    mem["episodic"] = new_ep
    return forgotten

# ============================================================================
# Context generation for LLM prompts
# ============================================================================

# Build a context string from relevant memories for an LLM prompt
proc build_context(mem, query, max_entries):
    let results = recall(mem, query, max_entries)
    if len(results) == 0:
        return ""
    let ctx = "Relevant memories:" + chr(10)
    for i in range(len(results)):
        let r = results[i]
        ctx = ctx + "  [" + r["source"] + "] " + r["entry"]["content"] + chr(10)
    return ctx

# Get all working memory as context
proc working_context(mem):
    if len(mem["working"]) == 0:
        return ""
    let ctx = "Current context:" + chr(10)
    for i in range(len(mem["working"])):
        ctx = ctx + "  - " + mem["working"][i]["content"] + chr(10)
    return ctx

# Get all semantic facts as context
proc knowledge_context(mem):
    if len(mem["semantic"]) == 0:
        return ""
    let ctx = "Known facts:" + chr(10)
    for i in range(len(mem["semantic"])):
        ctx = ctx + "  - " + mem["semantic"][i]["content"] + chr(10)
    return ctx

# ============================================================================
# Utilities
# ============================================================================

proc contains_keyword(text, query):
    if len(query) == 0:
        return true
    if len(query) > len(text):
        return false
    # Simple substring search
    for i in range(len(text) - len(query) + 1):
        let found = true
        for j in range(len(query)):
            if not found:
                j = len(query)
            if found and text[i + j] != query[j]:
                found = false
        if found:
            return true
    return false

proc stats(mem):
    let s = {}
    s["working_count"] = len(mem["working"])
    s["episodic_count"] = len(mem["episodic"])
    s["semantic_count"] = len(mem["semantic"])
    s["procedural_count"] = len(mem["procedural"])
    s["total_entries"] = len(mem["working"]) + len(mem["episodic"]) + len(mem["semantic"]) + len(mem["procedural"])
    s["total_stores"] = mem["total_stores"]
    s["total_recalls"] = mem["total_recalls"]
    s["total_consolidations"] = mem["total_consolidations"]
    return s

proc summary(mem):
    let s = stats(mem)
    let nl = chr(10)
    let out = "=== Engram Memory ===" + nl
    out = out + "Working: " + str(s["working_count"]) + "/" + str(mem["working_capacity"]) + nl
    out = out + "Episodic: " + str(s["episodic_count"]) + "/" + str(mem["max_episodic"]) + nl
    out = out + "Semantic: " + str(s["semantic_count"]) + "/" + str(mem["max_semantic"]) + nl
    out = out + "Procedural: " + str(s["procedural_count"]) + nl
    out = out + "Stores: " + str(s["total_stores"]) + nl
    out = out + "Recalls: " + str(s["total_recalls"]) + nl
    out = out + "Consolidations: " + str(s["total_consolidations"]) + nl
    out = out + "===================" + nl
    return out

# Clear all memories
proc clear_all(mem):
    mem["working"] = []
    mem["episodic"] = []
    mem["semantic"] = []
    mem["procedural"] = []

# Clear only working memory
proc clear_working(mem):
    mem["working"] = []
