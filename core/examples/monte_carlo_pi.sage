import thread

proc lcg_next(state):
    let a = 1103515245
    let c = 12345
    let m = 2147483648
    return (a * state + c) % m

proc lcg_float(state):
    let m = 2147483648
    return (state % m) / m

proc worker(iters, seed):
    let inside = 0
    let s = seed
    let i = 0

    while i < iters:
        s = lcg_next(s)
        let x = lcg_float(s)
        s = lcg_next(s)
        let y = lcg_float(s)

        if x * x + y * y <= 1.0:
            inside = inside + 1

        i = i + 1

    return inside

proc estimate_pi(num_threads, iters_per_thread):
    let threads = []
    let t = 0

    while t < num_threads:
        let seed = 1234 + t * 777
        let th = thread.spawn(worker, iters_per_thread, seed)
        push(threads, th)
        t = t + 1

    let total_inside = 0
    let total_samples = num_threads * iters_per_thread

    for th in threads:
        let inside = thread.join(th)
        total_inside = total_inside + inside

    let pi_est = 4.0 * total_inside / total_samples
    print "Threads: " + str(num_threads)
    print "Samples: " + str(total_samples)
    print "Estimated pi = " + str(pi_est)

proc main():
    # Keep this small enough to avoid the recursion-depth guard.
    estimate_pi(4, 500)

main()
