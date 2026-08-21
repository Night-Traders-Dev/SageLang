proc work():
    print "start"
    defer print "cleanup"
    print "middle"
    return "done"
end
print work()
