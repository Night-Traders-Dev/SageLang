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

import option

# Test Some creation
let x = option.Some(42)
if option.is_some(x):
    if option.is_none(x) == false:
        print "some_created"

# Test None creation
let y = option.None()
if option.is_none(y):
    if option.is_some(y) == false:
        print "none_created"

# Test unwrap
let val = option.unwrap(x)
if val == 42:
    print "unwrap_ok"

# Test unwrap_or
let val2 = option.unwrap_or(y, 99)
if val2 == 99:
    let val3 = option.unwrap_or(x, 99)
    if val3 == 42:
        print "unwrap_or_ok"

# Test map
proc double(n):
    return n * 2

let mapped = option.map(x, double)
let mapped_val = option.unwrap(mapped)
if mapped_val == 84:
    let mapped_none = option.map(y, double)
    if option.is_none(mapped_none):
        print "map_ok"

# Test and_then
proc safe_div(n):
    if n == 0:
        return option.None()
    return option.Some(100 / n)

let result = option.and_then(option.Some(5), safe_div)
if option.unwrap(result) == 20:
    let result2 = option.and_then(option.None(), safe_div)
    if option.is_none(result2):
        print "and_then_ok"

# Test filter
proc is_positive(n):
    return n > 0

let filtered = option.filter(option.Some(10), is_positive)
if option.is_some(filtered):
    let filtered2 = option.filter(option.Some(-5), is_positive)
    if option.is_none(filtered2):
        print "filter_ok"

# Test option_to_str
let s1 = option.option_to_str(option.Some(42))
let s2 = option.option_to_str(option.None())
if contains(s1, "Some"):
    if s2 == "None":
        print "option_str_ok"

print "PASS"
