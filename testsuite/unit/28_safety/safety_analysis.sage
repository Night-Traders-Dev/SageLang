gc_disable()
# EXPECT: analysis_ok
# EXPECT: PASS

# This file is tested with: sage safety tests/28_safety/safety_analysis.sage
# It should pass safety analysis with no errors.

# Good ownership patterns
let x = 42
let y = x

# Safe function with annotated parameters
proc add(a, b):
    return a + b
end

let result = add(10, 20)

# Safe control flow
if result == 30:
    let inner = "hello"
end

# Safe loop
let total = 0
let i = 0
while i < 5:
    total = total + i
    i = i + 1
end

# Safe class
proc make_point(px, py):
    let p = {}
    p["x"] = px
    p["y"] = py
    return p
end

let p = make_point(3, 4)

if p["x"] == 3:
    if p["y"] == 4:
        print "analysis_ok"
    end
end

print "PASS"
