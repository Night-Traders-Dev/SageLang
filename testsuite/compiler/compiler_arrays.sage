let nums = range(1, 6)
push(nums, 8)

print len(nums)
print nums[0] + nums[4]
print pop(nums)
print nums[1:4]

let total = 0
let i = 0
while i < len(nums):
    total = total + nums[i]
    i = i + 1

let literal = [10, 20, 30]
print literal[2]
print total
print slice(literal, 0, 2)
