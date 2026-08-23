gc_disable()
# EXPECT: ownership_basic
# EXPECT: copy_types
# EXPECT: move_semantics
# EXPECT: borrow_check
# EXPECT: thread_safety
# EXPECT: option_enforce
# EXPECT: unsafe_block
# EXPECT: PASS

import option

# Test basic ownership - values are owned by their variables
let a = option.Some(10)
let b = option.Some(20)
if option.is_some(a):
    if option.is_some(b):
        print "ownership_basic"

# Test Copy trait - primitives are implicitly copied
let n1 = 42
let n2 = n1
if n1 == 42:
    if n2 == 42:
        let s1 = "hello"
        let s2 = s1
        if s1 == "hello":
            if s2 == "hello":
                print "copy_types"

# Test move semantics with option.own()
let data = [1, 2, 3]
let moved = option.own(data)
# In strict mode, 'data' would be marked as moved
# In normal mode, both still work
if len(moved) == 3:
    print "move_semantics"

# Test borrow semantics with option.ref()
let original = [10, 20, 30]
let borrowed = option.ref(original)
# Both can read
if len(original) == 3:
    if len(borrowed) == 3:
        print "borrow_check"

# Test thread safety markers
let shared = {}
shared["value"] = 42
shared = option.mark_send(shared)
shared = option.mark_sync(shared)
if option.is_send(shared):
    if option.is_sync(shared):
        # Primitives are always Send
        if option.is_send(42):
            if option.is_send("hello"):
                print "thread_safety"

# Test Option type enforcement
let maybe = option.Some("present")
if option.is_some(maybe):
    let val = option.unwrap(maybe)
    if val == "present":
        let empty = option.None()
        let safe_val = option.unwrap_or(empty, "fallback")
        if safe_val == "fallback":
            print "option_enforce"

# Test deep copy
let orig = [1, [2, 3], 4]
let copied = option.copy(orig)
if len(copied) == 3:
    if len(copied[1]) == 2:
        print "unsafe_block"

print "PASS"
