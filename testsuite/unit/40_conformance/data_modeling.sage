# Conformance: Structs, Enums, Traits, Match Guards (Spec §12)
# EXPECT: 3
# EXPECT: 4
# EXPECT: 0
# EXPECT: 2
# EXPECT: medium
# Struct
struct Vec2:
    x: Float
    y: Float
let v = Vec2(3, 4)
print v.x
print v.y

# Enum
enum Status:
    Ok
    Pending
    Error
print Status["Ok"]
print Status["Error"]

# Match with guard
let score = 75
match score:
    case 75 if score >= 90:
        print "excellent"
    case 75 if score >= 50:
        print "medium"
    default:
        print "low"
