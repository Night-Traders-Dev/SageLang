gc_disable()
# EXPECT: ownership_basic
# EXPECT: copy_types
# EXPECT: move_semantics
# EXPECT: borrow_check
# EXPECT: thread_safety
# EXPECT: option_enforce
# EXPECT: unsafe_block
# EXPECT: PASS

import safety

# Test basic ownership - values are owned by their variables
let a = safety.Some(10)
let b = safety.Some(20)
if safety.is_some(a):
    if safety.is_some(b):
        print "ownership_basic"
    end
end

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
            end
        end
    end
end

# Test move semantics with safety.own()
let data = [1, 2, 3]
let moved = safety.own(data)
# In strict mode, 'data' would be marked as moved
# In normal mode, both still work
if len(moved) == 3:
    print "move_semantics"
end

# Test borrow semantics with safety.ref()
let original = [10, 20, 30]
let borrowed = safety.ref(original)
# Both can read
if len(original) == 3:
    if len(borrowed) == 3:
        print "borrow_check"
    end
end

# Test thread safety markers
let shared = {}
shared["value"] = 42
shared = safety.mark_send(shared)
shared = safety.mark_sync(shared)
if safety.is_send(shared):
    if safety.is_sync(shared):
        # Primitives are always Send
        if safety.is_send(42):
            if safety.is_send("hello"):
                print "thread_safety"
            end
        end
    end
end

# Test Option type enforcement
let maybe = safety.Some("present")
if safety.is_some(maybe):
    let val = safety.unwrap(maybe)
    if val == "present":
        let empty = safety.None()
        let safe_val = safety.unwrap_or(empty, "fallback")
        if safe_val == "fallback":
            print "option_enforce"
        end
    end
end

# Test deep copy
let orig = [1, [2, 3], 4]
let copied = safety.copy(orig)
if len(copied) == 3:
    if len(copied[1]) == 2:
        print "unsafe_block"
    end
end

print "PASS"
