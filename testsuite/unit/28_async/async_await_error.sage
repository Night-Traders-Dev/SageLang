# EXPECT: 100
# EXPECT: async_proc_ok
# EXPECT: PASS

async proc compute_task(x):
    return x * 5

async proc chained_task(val):
    let res = await compute_task(val)
    return res + 10

let plain_val = 100
let a_val = await plain_val
print a_val

let task = chained_task(8)
let final_res = await task
if final_res == 50:
    print "async_proc_ok"

print "PASS"
