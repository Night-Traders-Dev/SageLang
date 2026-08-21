proc make_counter():
    let count = 0
    return proc():
        count = count + 1
        return count
    end
end
let c1 = make_counter()
print c1()
print c1()
let c2 = make_counter()
print c2()
print c1()
