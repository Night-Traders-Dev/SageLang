proc HelloWorld():
    let x = 5
    if x == 5:
        return true
    else:
        return false

proc TestVar():
    let x = 1
    let y = 2
    return (y - x)

if HelloWorld():
    print "True"
else:
    print "False"

let myVar = TestVar()
print(myVar)