# EXPECT: [10, 20, 30, 40, 50]
# EXPECT: 5
# EXPECT: 10
# EXPECT: 30
# EXPECT: 6
# EXPECT: 10
# EXPECT: 20
# EXPECT: 30
# EXPECT: 40
# EXPECT: 50
# EXPECT: 60
# EXPECT: 0
# EXPECT: 1
# EXPECT: 2
# EXPECT: 3
# EXPECT: 4
# EXPECT: 2
# EXPECT: 3
# EXPECT: 4
# EXPECT: 5
# EXPECT: 6
# EXPECT: {"age": 30, "name": Alice}
# EXPECT: [age, name]
# EXPECT: [30, Alice]
# EXPECT: true
# EXPECT: false
# EXPECT: (10, 20, 30)
# EXPECT: 10
# EXPECT: 3
# EXPECT: [2, 3]
# EXPECT: [1, 2]
# EXPECT: [3, 4]
# EXPECT: [5, 6]
## Test: Kotlin backend — arrays, dicts, tuples, for loops
## Run: sage --emit-kotlin tests/42_kotlin/emit_collections.sage

## Arrays
let nums = [10, 20, 30, 40, 50]
print(nums)
print(len(nums))
print(nums[0])
print(nums[2])
push(nums, 60)
print(len(nums))

## For loop
for n in nums:
    print(n)

## Range
for i in range(5):
    print(i)

for i in range(2, 7):
    print(i)

## Dicts
let person = {"name": "Alice", "age": 30}
print(person)
print(dict_keys(person))
print(dict_values(person))
print(dict_has(person, "name"))
print(dict_has(person, "email"))

## Tuples
let point = (10, 20, 30)
print(point)
print(point[0])
print(len(point))

## Slicing
let items = [1, 2, 3, 4, 5]
let sliced = items[1:3]
print(sliced)

## Nested
let matrix = [[1, 2], [3, 4], [5, 6]]
for row in matrix:
    print(row)
