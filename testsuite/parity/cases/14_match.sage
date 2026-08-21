proc classify(x):
    match x:
        case 0:
            return "zero"
        case 1:
            return "one"
        default:
            return "many"
    end
end
print classify(0)
print classify(1)
print classify(99)
match 5:
    case n if n > 3:
        print "big"
    default:
        print "small"
    end
