# EXPECT: even number: 8
# EXPECT: odd number: 15
# EXPECT: high score: 95
# EXPECT: low score: 40
# EXPECT: default score: 75

proc test_eval(n):
    match n:
        case x if x % 2 == 0:
            print "even number: " + str(x)
        case x if x % 2 != 0:
            print "odd number: " + str(x)

test_eval(8)
test_eval(15)

proc test_grade(score):
    match score:
        case score if score >= 90:
            print "high score: " + str(score)
        case score if score < 50:
            print "low score: " + str(score)
        default:
            print "default score: " + str(score)

test_grade(95)
test_grade(40)
test_grade(75)
