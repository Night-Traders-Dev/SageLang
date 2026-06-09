# EXPECT: 42
# Test basic async proc and await
async proc compute():
    return 42

let future = compute()
let result = await future
print result
