# EXPECT: [1, 2, 3]
# EXPECT: 3
# EXPECT: hello
# Test multiline array literal
let arr = [
    1,
    2,
    3,
]
print arr

# Test multiline dict literal
let d = {
    "a": 1,
    "b": 2,
    "c": 3,
}
print len(d)

# Test multiline function call
proc greet(name, greeting):
    print greeting

greet(
    "world",
    "hello",
)
