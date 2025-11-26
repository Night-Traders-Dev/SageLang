# A simple number guessing game

let target = 42
let running = true

print "Guess a number between 0 and 100!"

while running
    let guess_str = input()
    # Note: We don't have string->number conversion yet!
    # We only have string equality for now.
    
    if guess_str == "42"
        print "Correct! You win!"
        let running = false
    else
        print "Wrong! Try again."
