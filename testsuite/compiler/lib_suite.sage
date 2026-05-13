from assert import assert_true, assert_equal, assert_close
from math import factorial, gcd, pow_int, sqrt
from strings import compact, contains as string_contains, pad_left
from dicts import size as dict_size, get_or, has_all, remove_keys, entries
from stats import mean, stddev, cumulative
from utils import default_if_nil, repeat_value
import arrays as arr
import iter as it

proc double(x):
    return x * 2

proc is_even_num(x):
    return x % 2 == 0

proc add_pair(total, value):
    return total + value

print "Running lib suite"

assert_equal(factorial(5), 120, "factorial failed")
assert_equal(gcd(84, 18), 6, "gcd failed")
assert_equal(pow_int(2, 8), 256, "pow_int failed")
assert_close(sqrt(81), 9, 0.001, "sqrt failed")

assert_true(string_contains("sage rocks", "rocks"), "contains failed")
assert_equal(compact("  many   spaces here  "), "many spaces here", "compact failed")
assert_equal(pad_left("7", 3, "0"), "007", "pad_left failed")

let nums = [1, 2, 2, 3, 4]
let doubled = arr.map(nums, double)
assert_equal(doubled[3], 6, "map failed")

let evens = arr.filter(nums, is_even_num)
assert_equal(len(evens), 3, "filter failed")

let total = arr.reduce([1, 2, 3, 4], 0, add_pair)
assert_equal(total, 10, "reduce failed")

let uniq = arr.unique(nums)
assert_equal(len(uniq), 4, "unique failed")

let zipped = arr.zip(["a", "b"], [10, 20, 30])
assert_equal(len(zipped), 2, "zip length failed")
assert_equal(zipped[1][0], "b", "zip key failed")
assert_equal(zipped[1][1], 20, "zip value failed")

let chunks = arr.chunk([1, 2, 3, 4, 5], 2)
assert_equal(len(chunks), 3, "chunk failed")

let user = {"name": "Ada", "role": "admin", "active": true}
assert_equal(dict_size(user), 3, "dict size failed")
assert_equal(get_or(user, "name", "unknown"), "Ada", "dict get_or existing failed")
assert_equal(get_or(user, "missing", "unknown"), "unknown", "dict get_or fallback failed")
assert_true(has_all(user, ["name", "role"]), "dict has_all failed")

let snapshot = entries(user)
assert_equal(len(snapshot), 3, "dict entries failed")

remove_keys(user, ["active"])
assert_equal(dict_size(user), 2, "dict remove_keys failed")

let stepped = it.take(it.range_step(0, 10, 3), 4)
assert_equal(stepped[0], 0, "iter take first failed")
assert_equal(stepped[1], 3, "iter take second failed")
assert_equal(stepped[2], 6, "iter take third failed")
assert_equal(stepped[3], 9, "iter take fourth failed")

let enumerated = it.take(it.enumerate_array(["x", "y", "z"]), 3)
assert_equal(enumerated[2][0], 2, "enumerate index failed")
assert_equal(enumerated[2][1], "z", "enumerate value failed")

assert_equal(mean([2, 4, 6, 8]), 5, "mean failed")
assert_close(stddev([2, 4, 6, 8]), 2.2360679, 0.01, "stddev failed")

let running = cumulative([1, 2, 3])
assert_equal(running[2], 6, "cumulative failed")

assert_equal(default_if_nil(nil, "fallback"), "fallback", "default_if_nil failed")
let copies = repeat_value("x", 3)
assert_equal(len(copies), 3, "repeat_value length failed")
assert_equal(copies[2], "x", "repeat_value value failed")

print "lib suite ok"
