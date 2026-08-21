let log = []
try:
    push(log, "try")
    raise "boom"
catch e:
    push(log, "catch:" + e)
finally:
    push(log, "finally")
end
print log
try:
    let x = 1 / 0
catch e:
    print "caught-div"
end
