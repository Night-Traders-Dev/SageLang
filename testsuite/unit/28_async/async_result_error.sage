# EXPECT: ok: 50
# EXPECT: error: negative

async proc compute_val(x):
    if x < 0:
        return "error: negative"
    return "ok: " + str(x * 10)

proc main():
    let t1 = compute_val(5)
    let t2 = compute_val(-3)
    let res1 = await t1
    let res2 = await t2
    print res1
    print res2

main()
