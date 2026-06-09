# EXPECT: small
# EXPECT: medium
# EXPECT: big
proc classify(n):
    match n:
        case 1:
            return "small"
        case 2:
            return "medium"
        default:
            return "big"

print(classify(1))
print(classify(2))
print(classify(100))
