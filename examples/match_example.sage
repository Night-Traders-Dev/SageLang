# Match Expression Examples

# Example 1: Basic number matching
let x = 2
match x:
    case 1:
        print "One"
    case 2:
        print "Two"
    case 3:
        print "Three"
    default:
        print "Something else"

# Example 2: String matching
let command = "start"
match command:
    case "start":
        print "Starting..."
    case "stop":
        print "Stopping..."
    case "pause":
        print "Pausing..."
    default:
        print "Unknown command"

# Example 3: Status codes
proc get_status_message(code):
    match code:
        case 200:
            return "OK"
        case 404:
            return "Not Found"
        case 500:
            return "Server Error"
        default:
            return "Unknown Status"

print get_status_message(200)
print get_status_message(404)
print get_status_message(999)

# Example 4: Boolean matching
let is_active = true
match is_active:
    case true:
        print "Active"
    case false:
        print "Inactive"

# Example 5: Match with calculations
let score = 85
let grade = nil
match score:
    case 90:
        grade = "A"
    case 80:
        grade = "B"
    case 70:
        grade = "C"
    default:
        grade = "F"
print grade