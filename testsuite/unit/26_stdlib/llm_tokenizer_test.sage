gc_disable()
# EXPECT: 5
# EXPECT: hello
# EXPECT: true
# EXPECT: true
# EXPECT: 7

import llm.tokenizer

# Character tokenizer
let tok = tokenizer.char_tokenizer()
let ids = tokenizer.char_encode(tok, "hello")
print len(ids)
let decoded = tokenizer.char_decode(tok, ids)
print decoded

# Round-trip
print decoded == "hello"

# Word tokenizer
let wtok = tokenizer.word_tokenizer()
tokenizer.build_vocab(wtok, "the cat sat on the mat", 100)
let wids = tokenizer.word_encode(wtok, "the cat")
print len(wids) > 0

# Pad sequence
let padded = tokenizer.pad_sequence([1, 2, 3], 7, 0)
print len(padded)
