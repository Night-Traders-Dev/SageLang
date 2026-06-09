# EXPECT: 3
# EXPECT: 2
# Generic type annotations (parsed but not enforced yet)
let nums: Array[Int] = [10, 20, 30]
print len(nums)

let lookup: Dict[String, Int] = {"a": 1, "b": 2}
print len(lookup)
