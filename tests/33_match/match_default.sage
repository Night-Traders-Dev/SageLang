# EXPECT: other
let x = 99
match x:
    case 1:
        print("one")
    case 2:
        print("two")
    default:
        print("other")
