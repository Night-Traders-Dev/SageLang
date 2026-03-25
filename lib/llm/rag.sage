gc_disable()
# Retrieval-Augmented Generation (RAG)
# Provides document chunking, embedding-based retrieval, and context assembly
# for grounding LLM responses in factual knowledge

# ============================================================================
# Document store
# ============================================================================

proc create_store():
    let store = {}
    store["documents"] = []
    store["chunks"] = []
    store["index"] = {}
    store["next_id"] = 1
    return store

# Add a document and auto-chunk it
proc add_document(store, content, metadata):
    let doc_id = store["next_id"]
    store["next_id"] = store["next_id"] + 1
    let doc = {}
    doc["id"] = doc_id
    doc["content"] = content
    doc["metadata"] = metadata
    push(store["documents"], doc)
    # Chunk the document
    let chunks = chunk_text(content, 256, 64)
    for i in range(len(chunks)):
        let chunk = {}
        chunk["id"] = len(store["chunks"]) + 1
        chunk["doc_id"] = doc_id
        chunk["text"] = chunks[i]
        chunk["metadata"] = metadata
        # Build keyword index
        let words = extract_keywords(chunks[i])
        for j in range(len(words)):
            let w = words[j]
            if not dict_has(store["index"], w):
                store["index"][w] = []
            push(store["index"][w], chunk["id"] - 1)
        push(store["chunks"], chunk)
    return doc_id

# ============================================================================
# Text chunking strategies
# ============================================================================

# Fixed-size chunking with overlap
proc chunk_text(text, chunk_size, overlap):
    let chunks = []
    let i = 0
    while i < len(text):
        let end_pos = i + chunk_size
        if end_pos > len(text):
            end_pos = len(text)
        let chunk = ""
        for j in range(end_pos - i):
            chunk = chunk + text[i + j]
        push(chunks, chunk)
        i = i + chunk_size - overlap
        if i >= len(text):
            i = len(text)
    return chunks

# Sentence-aware chunking (split on periods/newlines, then group)
proc chunk_sentences(text, max_chunk_size):
    let sentences = []
    let current = ""
    for i in range(len(text)):
        current = current + text[i]
        if text[i] == "." or text[i] == chr(10):
            if len(current) > 1:
                push(sentences, current)
            current = ""
    if len(current) > 0:
        push(sentences, current)
    # Group sentences into chunks
    let chunks = []
    let chunk = ""
    for i in range(len(sentences)):
        if len(chunk) + len(sentences[i]) > max_chunk_size and len(chunk) > 0:
            push(chunks, chunk)
            chunk = ""
        chunk = chunk + sentences[i]
    if len(chunk) > 0:
        push(chunks, chunk)
    return chunks

# ============================================================================
# Keyword extraction and retrieval
# ============================================================================

proc extract_keywords(text):
    let words = []
    let current = ""
    let lower_text = to_lower(text)
    for i in range(len(lower_text)):
        let c = lower_text[i]
        let code = ord(c)
        if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95:
            current = current + c
        else:
            if len(current) >= 3:
                push(words, current)
            current = ""
    if len(current) >= 3:
        push(words, current)
    return words

# Retrieve chunks matching a query (keyword-based BM25-style scoring)
proc retrieve(store, query, top_k):
    let query_words = extract_keywords(to_lower(query))
    let scores = {}
    for i in range(len(query_words)):
        let word = query_words[i]
        if dict_has(store["index"], word):
            let chunk_ids = store["index"][word]
            for j in range(len(chunk_ids)):
                let cid = str(chunk_ids[j])
                if dict_has(scores, cid):
                    scores[cid] = scores[cid] + 1
                else:
                    scores[cid] = 1
    # Rank by score
    let scored = []
    let keys = dict_keys(scores)
    for i in range(len(keys)):
        let entry = {}
        entry["chunk_idx"] = tonumber(keys[i])
        entry["score"] = scores[keys[i]]
        push(scored, entry)
    # Sort descending
    for i in range(len(scored)):
        let max_idx = i
        for j in range(len(scored) - i):
            if scored[i + j]["score"] > scored[max_idx]["score"]:
                max_idx = i + j
        let temp = scored[i]
        scored[i] = scored[max_idx]
        scored[max_idx] = temp
    # Return top-k chunks
    let results = []
    for i in range(top_k):
        if i < len(scored):
            let idx = scored[i]["chunk_idx"]
            if idx < len(store["chunks"]):
                let r = {}
                r["chunk"] = store["chunks"][idx]
                r["score"] = scored[i]["score"]
                push(results, r)
    return results

# ============================================================================
# Context assembly for LLM prompts
# ============================================================================

# Build a context string from retrieved chunks
proc build_context(store, query, top_k):
    let results = retrieve(store, query, top_k)
    if len(results) == 0:
        return ""
    let context = "Relevant information:" + chr(10)
    for i in range(len(results)):
        context = context + "---" + chr(10)
        context = context + results[i]["chunk"]["text"] + chr(10)
    context = context + "---" + chr(10)
    return context

# Build a RAG prompt: context + question
proc rag_prompt(store, question, top_k, system_prompt):
    let context = build_context(store, question, top_k)
    let prompt = system_prompt + chr(10) + chr(10)
    if len(context) > 0:
        prompt = prompt + context + chr(10)
    prompt = prompt + "Question: " + question + chr(10)
    prompt = prompt + "Answer: "
    return prompt

# ============================================================================
# Summarization for context compression
# ============================================================================

# Extract the most important sentences (extractive summarization)
proc summarize_extractive(text, max_sentences):
    let sentences = []
    let current = ""
    for i in range(len(text)):
        current = current + text[i]
        if text[i] == "." or text[i] == chr(10):
            if len(current) > 10:
                push(sentences, current)
            current = ""
    if len(current) > 10:
        push(sentences, current)
    # Score sentences by keyword density
    let all_keywords = extract_keywords(text)
    let keyword_freq = {}
    for i in range(len(all_keywords)):
        let w = all_keywords[i]
        if dict_has(keyword_freq, w):
            keyword_freq[w] = keyword_freq[w] + 1
        else:
            keyword_freq[w] = 1
    let scored_sentences = []
    for i in range(len(sentences)):
        let words = extract_keywords(sentences[i])
        let score = 0
        for j in range(len(words)):
            if dict_has(keyword_freq, words[j]):
                score = score + keyword_freq[words[j]]
        let entry = {}
        entry["text"] = sentences[i]
        entry["score"] = score
        entry["index"] = i
        push(scored_sentences, entry)
    # Sort by score
    for i in range(len(scored_sentences)):
        let max_idx = i
        for j in range(len(scored_sentences) - i):
            if scored_sentences[i + j]["score"] > scored_sentences[max_idx]["score"]:
                max_idx = i + j
        let temp = scored_sentences[i]
        scored_sentences[i] = scored_sentences[max_idx]
        scored_sentences[max_idx] = temp
    # Take top sentences, re-sort by original order
    let selected = []
    for i in range(max_sentences):
        if i < len(scored_sentences):
            push(selected, scored_sentences[i])
    for i in range(len(selected)):
        let min_idx = i
        for j in range(len(selected) - i):
            if selected[i + j]["index"] < selected[min_idx]["index"]:
                min_idx = i + j
        let temp = selected[i]
        selected[i] = selected[min_idx]
        selected[min_idx] = temp
    let summary = ""
    for i in range(len(selected)):
        summary = summary + selected[i]["text"]
    return summary

# ============================================================================
# Store statistics
# ============================================================================

proc store_stats(store):
    let s = {}
    s["documents"] = len(store["documents"])
    s["chunks"] = len(store["chunks"])
    s["index_terms"] = len(dict_keys(store["index"]))
    return s

proc to_lower(s):
    let result = ""
    for i in range(len(s)):
        let code = ord(s[i])
        if code >= 65 and code <= 90:
            result = result + chr(code + 32)
        else:
            result = result + s[i]
    return result
