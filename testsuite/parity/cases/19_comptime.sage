comptime:
    let TABLE_SIZE = 64
end
print TABLE_SIZE * 2
let x = comptime(1 + 2)
print x
