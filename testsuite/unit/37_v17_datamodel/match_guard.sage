# EXPECT: medium
# EXPECT: negative
# EXPECT: other
# Test match with guard clauses
let x = 50
match x:
    case 50 if x > 100:
        print "big"
    case 50 if x > 10:
        print "medium"
    case 50:
        print "small"

let y = -5
match y:
    case -5 if y < 0:
        print "negative"
    default:
        print "positive"

let z = 99
match z:
    case 1 if true:
        print "one"
    default:
        print "other"
