gc_disable()
# EXPECT: some_created
# EXPECT: none_created
# EXPECT: unwrap_ok
# EXPECT: unwrap_or_ok
# EXPECT: map_ok
# EXPECT: and_then_ok
# EXPECT: filter_ok
# EXPECT: option_str_ok
# EXPECT: PASS

import safety

# Test Some creation
let x = safety.Some(42)
if safety.is_some(x):
    if safety.is_none(x) == false:
        print "some_created"
    end
end

# Test None creation
let y = safety.None()
if safety.is_none(y):
    if safety.is_some(y) == false:
        print "none_created"
    end
end

# Test unwrap
let val = safety.unwrap(x)
if val == 42:
    print "unwrap_ok"
end

# Test unwrap_or
let val2 = safety.unwrap_or(y, 99)
if val2 == 99:
    let val3 = safety.unwrap_or(x, 99)
    if val3 == 42:
        print "unwrap_or_ok"
    end
end

# Test map
proc double(n):
    return n * 2
end

let mapped = safety.map(x, double)
let mapped_val = safety.unwrap(mapped)
if mapped_val == 84:
    let mapped_none = safety.map(y, double)
    if safety.is_none(mapped_none):
        print "map_ok"
    end
end

# Test and_then
proc safe_div(n):
    if n == 0:
        return safety.None()
    end
    return safety.Some(100 / n)
end

let result = safety.and_then(safety.Some(5), safe_div)
if safety.unwrap(result) == 20:
    let result2 = safety.and_then(safety.None(), safe_div)
    if safety.is_none(result2):
        print "and_then_ok"
    end
end

# Test filter
proc is_positive(n):
    return n > 0
end

let filtered = safety.filter(safety.Some(10), is_positive)
if safety.is_some(filtered):
    let filtered2 = safety.filter(safety.Some(-5), is_positive)
    if safety.is_none(filtered2):
        print "filter_ok"
    end
end

# Test option_to_str
let s1 = safety.option_to_str(safety.Some(42))
let s2 = safety.option_to_str(safety.None())
if contains(s1, "Some"):
    if s2 == "None":
        print "option_str_ok"
    end
end

print "PASS"
