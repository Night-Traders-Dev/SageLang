import io
import assert

let test_file = "io_security_test.bin"

# Test 1: Write and read small array
print "Test 1: Small array write/read"
let data1 = [72, 101, 108, 108, 111] # "Hello"
assert.assert_true(io.writebytes(test_file, data1), "writebytes failed")
let read1 = io.readbytes(test_file)
assert.assert_equal(len(read1), 5, "readbytes length mismatch")
assert.assert_equal(read1[0], 72, "data[0] mismatch")
assert.assert_equal(read1[4], 111, "data[4] mismatch")

# Test 2: Append to file
print "Test 2: Append bytes"
let data2 = [32, 87, 111, 114, 108, 100] # " World"
assert.assert_true(io.appendbytes(test_file, data2), "appendbytes failed")
let read2 = io.readbytes(test_file)
assert.assert_equal(len(read2), 11, "append length mismatch")
assert.assert_equal(read2[6], 87, "append data mismatch")

# Test 3: Write large array (larger than chunk size 4096)
print "Test 3: Large array write (chunking)"
let data3 = []
for i in range(5000):
    push(data3, i % 256)
end
assert.assert_true(io.writebytes(test_file, data3), "large writebytes failed")
let read3 = io.readbytes(test_file)
assert.assert_equal(len(read3), 5000, "large read length mismatch")
for i in range(5000):
    if read3[i] != i % 256:
        print "Mismatch at index " + str(i)
        assert.assert_true(false, "data mismatch in large write")
    end
end

# Test 4: Empty array
print "Test 4: Empty array"
assert.assert_true(io.writebytes(test_file, []), "empty write failed")
assert.assert_equal(len(io.readbytes(test_file)), 0, "empty read mismatch")

print "All security IO tests passed!"
