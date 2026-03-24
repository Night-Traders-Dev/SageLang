# String concatenation — measures string allocation and GC pressure
let s = ""
let i = 0
while i < 10000:
    s = s + "x"
    i = i + 1
print len(s)
