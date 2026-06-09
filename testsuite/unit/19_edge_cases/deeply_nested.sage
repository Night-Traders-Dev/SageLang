# EXPECT: 10
# Deep nesting of if statements
var result = 0
if true:
    if true:
        if true:
            if true:
                if true:
                    result = 10
print(result)
