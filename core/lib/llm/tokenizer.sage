gc_disable()
# Tokenizer: BPE (Byte Pair Encoding), character-level, and word-level tokenization

# ============================================================================
# Character-level tokenizer (simplest, good for testing)
# ============================================================================

proc char_tokenizer():
    let tok = {}
    tok["type"] = "char"
    tok["vocab"] = {}
    tok["id_to_token"] = {}
    tok["vocab_size"] = 0
    # Initialize with ASCII
    for i in range(128):
        let ch = chr(i)
        tok["vocab"][ch] = i
        tok["id_to_token"][str(i)] = ch
    tok["vocab_size"] = 128
    comptime:
        tok["pad_id"] = 0
        tok["bos_id"] = 1
        tok["eos_id"] = 2
        tok["unk_id"] = 3
    return tok

proc char_encode(tok, text):
    let ids = []
    for i in range(len(text)):
        let ch = text[i]
        if dict_has(tok["vocab"], ch):
            push(ids, tok["vocab"][ch])
        else:
            push(ids, tok["unk_id"])
    return ids

proc char_decode(tok, ids):
    let text = ""
    for i in range(len(ids)):
        let key = str(ids[i])
        if dict_has(tok["id_to_token"], key):
            text = text + tok["id_to_token"][key]
    return text

# ============================================================================
# Word-level tokenizer
# ============================================================================

proc word_tokenizer():
    let tok = {}
    tok["type"] = "word"
    tok["vocab"] = {}
    tok["id_to_token"] = {}
    tok["vocab_size"] = 4
    # Special tokens
    tok["vocab"]["<pad>"] = 0
    tok["vocab"]["<bos>"] = 1
    tok["vocab"]["<eos>"] = 2
    tok["vocab"]["<unk>"] = 3
    tok["id_to_token"]["0"] = "<pad>"
    tok["id_to_token"]["1"] = "<bos>"
    tok["id_to_token"]["2"] = "<eos>"
    tok["id_to_token"]["3"] = "<unk>"
    comptime:
        tok["pad_id"] = 0
        tok["bos_id"] = 1
        tok["eos_id"] = 2
        tok["unk_id"] = 3
    return tok

# Build vocabulary from text corpus
proc build_vocab(tok, text, max_vocab):
    let words = split_words(text)
    let freq = {}
    for i in range(len(words)):
        let w = words[i]
        if dict_has(freq, w):
            freq[w] = freq[w] + 1
        else:
            freq[w] = 1
    # Add most frequent words
    let keys = dict_keys(freq)
    for i in range(len(keys)):
        if tok["vocab_size"] < max_vocab:
            if not dict_has(tok["vocab"], keys[i]):
                let id = tok["vocab_size"]
                tok["vocab"][keys[i]] = id
                tok["id_to_token"][str(id)] = keys[i]
                tok["vocab_size"] = tok["vocab_size"] + 1

proc word_encode(tok, text):
    let words = split_words(text)
    let ids = []
    for i in range(len(words)):
        if dict_has(tok["vocab"], words[i]):
            push(ids, tok["vocab"][words[i]])
        else:
            push(ids, tok["unk_id"])
    return ids

proc word_decode(tok, ids):
    let words = []
    for i in range(len(ids)):
        let key = str(ids[i])
        if dict_has(tok["id_to_token"], key):
            push(words, tok["id_to_token"][key])
    let result = ""
    for i in range(len(words)):
        if i > 0:
            result = result + " "
        result = result + words[i]
    return result

# ============================================================================
# BPE tokenizer (byte-pair encoding)
# ============================================================================

proc bpe_tokenizer(vocab_size):
    let tok = {}
    tok["type"] = "bpe"
    tok["vocab_size"] = vocab_size
    tok["merges"] = []
    tok["vocab"] = {}
    tok["id_to_token"] = {}
    # Initialize with byte-level tokens (256) + special tokens (4)
    tok["vocab"]["<pad>"] = 0
    tok["vocab"]["<bos>"] = 1
    tok["vocab"]["<eos>"] = 2
    tok["vocab"]["<unk>"] = 3
    tok["id_to_token"]["0"] = "<pad>"
    tok["id_to_token"]["1"] = "<bos>"
    tok["id_to_token"]["2"] = "<eos>"
    tok["id_to_token"]["3"] = "<unk>"
    comptime:
        tok["pad_id"] = 0
        tok["bos_id"] = 1
        tok["eos_id"] = 2
        tok["unk_id"] = 3
    let next_id = 4
    for i in range(256):
        let ch = chr(i)
        if not dict_has(tok["vocab"], ch):
            tok["vocab"][ch] = next_id
            tok["id_to_token"][str(next_id)] = ch
            next_id = next_id + 1
    tok["next_id"] = next_id
    return tok

# Train BPE merges on a text corpus
proc train_bpe(tok, text, num_merges):
    # Tokenize to characters
    let tokens = []
    for i in range(len(text)):
        push(tokens, text[i])
    for merge_step in range(num_merges):
        if tok["next_id"] >= tok["vocab_size"]:
            return
        # Count pairs
        let pair_counts = {}
        for i in range(len(tokens) - 1):
            let pair = tokens[i] + " " + tokens[i + 1]
            if dict_has(pair_counts, pair):
                pair_counts[pair] = pair_counts[pair] + 1
            else:
                pair_counts[pair] = 1
        # Find most frequent pair
        let best_pair = ""
        let best_count = 0
        let keys = dict_keys(pair_counts)
        for i in range(len(keys)):
            if pair_counts[keys[i]] > best_count:
                best_count = pair_counts[keys[i]]
                best_pair = keys[i]
        if best_count < 2:
            return
        # Split best_pair back into two tokens
        let space_pos = 0
        for i in range(len(best_pair)):
            if best_pair[i] == " ":
                space_pos = i
        let left = ""
        for i in range(space_pos):
            left = left + best_pair[i]
        let right = ""
        for i in range(len(best_pair) - space_pos - 1):
            right = right + best_pair[space_pos + 1 + i]
        let merged = left + right
        # Add merge rule
        let merge = {}
        merge["left"] = left
        merge["right"] = right
        merge["result"] = merged
        push(tok["merges"], merge)
        # Add to vocab
        if not dict_has(tok["vocab"], merged):
            tok["vocab"][merged] = tok["next_id"]
            tok["id_to_token"][str(tok["next_id"])] = merged
            tok["next_id"] = tok["next_id"] + 1
        # Apply merge to token list
        let new_tokens = []
        let i = 0
        while i < len(tokens):
            if i + 1 < len(tokens) and tokens[i] == left and tokens[i + 1] == right:
                push(new_tokens, merged)
                i = i + 2
            else:
                push(new_tokens, tokens[i])
                i = i + 1
        tokens = new_tokens

# Encode text using trained BPE
proc bpe_encode(tok, text):
    # Start with characters
    let tokens = []
    for i in range(len(text)):
        push(tokens, text[i])
    # Apply merges in order
    let merges = tok["merges"]
    for m in range(len(merges)):
        let merge = merges[m]
        let new_tokens = []
        let i = 0
        while i < len(tokens):
            if i + 1 < len(tokens) and tokens[i] == merge["left"] and tokens[i + 1] == merge["right"]:
                push(new_tokens, merge["result"])
                i = i + 2
            else:
                push(new_tokens, tokens[i])
                i = i + 1
        tokens = new_tokens
    # Convert to IDs
    let ids = []
    for i in range(len(tokens)):
        if dict_has(tok["vocab"], tokens[i]):
            push(ids, tok["vocab"][tokens[i]])
        else:
            push(ids, tok["unk_id"])
    return ids

proc bpe_decode(tok, ids):
    let text = ""
    for i in range(len(ids)):
        let key = str(ids[i])
        if dict_has(tok["id_to_token"], key):
            text = text + tok["id_to_token"][key]
    return text

# ============================================================================
# General encode/decode dispatch
# ============================================================================

proc encode(tok, text):
    if tok["type"] == "char":
        return char_encode(tok, text)
    if tok["type"] == "word":
        return word_encode(tok, text)
    if tok["type"] == "bpe":
        return bpe_encode(tok, text)
    return []

proc decode(tok, ids):
    if tok["type"] == "char":
        return char_decode(tok, ids)
    if tok["type"] == "word":
        return word_decode(tok, ids)
    if tok["type"] == "bpe":
        return bpe_decode(tok, ids)
    return ""

# ============================================================================
# Utilities
# ============================================================================

proc split_words(text):
    let words = []
    let current = ""
    for i in range(len(text)):
        let c = text[i]
        if c == " " or c == chr(10) or c == chr(9) or c == chr(13):
            if len(current) > 0:
                push(words, current)
            current = ""
        else:
            current = current + c
    if len(current) > 0:
        push(words, current)
    return words

# Pad a token sequence to a fixed length
proc pad_sequence(ids, max_len, pad_id):
    let result = []
    for i in range(len(ids)):
        if i < max_len:
            push(result, ids[i])
    while len(result) < max_len:
        push(result, pad_id)
    return result

# Truncate to max length
proc truncate(ids, max_len):
    let result = []
    for i in range(max_len):
        if i < len(ids):
            push(result, ids[i])
    return result

# Add special tokens
proc add_special(tok, ids):
    let result = [tok["bos_id"]]
    for i in range(len(ids)):
        push(result, ids[i])
    push(result, tok["eos_id"])
    return result
