import math

proc main():
    print "Testing printm with ASM backend (x86_64)..."
    let res = math.printm("10 + 20", backend="asm")
    print "Result: " + str(res)
    
    if res != 30:
        print "FAILURE: 10 + 20 should be 30, got " + str(res)
        exit(1)
    end
    
    let res2 = math.printm("50 - 15", backend="asm")
    print "Result: " + str(res2)
    if res2 != 35:
        print "FAILURE: 50 - 15 should be 35, got " + str(res2)
        exit(1)
    end

    let res3 = math.printm("6 * 7", backend="asm")
    print "Result: " + str(res3)
    if res3 != 42:
        print "FAILURE: 6 * 7 should be 42, got " + str(res3)
        exit(1)
    end

    let res4 = math.printm("100 / 4", backend="asm")
    print "Result: " + str(res4)
    if res4 != 25:
        print "FAILURE: 100 / 4 should be 25, got " + str(res4)
        exit(1)
    end

    print "SUCCESS"

main()
