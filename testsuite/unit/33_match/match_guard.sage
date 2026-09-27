# EXPECT: medium
# EXPECT: negative
# EXPECT: default branch

let val = 50
match val:
    case 50 if val > 100:
        print "large"
    case 50 if val > 10:
        print "medium"
    case 50:
        print "small"

let temp = -10
match temp:
    case x if x < 0:
        print "negative"
    case x if x == 0:
        print "zero"
    default:
        print "positive"

let score = 5
match score:
    case x if x > 90:
        print "A"
    default:
        print "default branch"
