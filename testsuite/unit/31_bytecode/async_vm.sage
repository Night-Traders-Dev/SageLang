# RUN: bytecode-run
# EXPECT: 30
# EXPECT: 3
# EXPECT: 42
# EXPECT: 12
# EXPECT: DISTINCT
# Async under the bytecode runtime, as a plain script.
#
# A script run with --runtime bytecode has no BytecodeProgram behind it, so
# build_function is NULL and every proc -- async included -- is defined through
# the AST walker. The worker in vm.c has to notice that and run the AST body.
# The counterpart is async_artifact.sage, which is the same program through a
# .svm and therefore does reach the compiled branch.

import thread

async proc add(a, b):
    return a + b

async proc who():
    return thread.id()

let future = add(10, 20)
print await future

# Three tasks are spawned before any is awaited, so they are genuinely
# outstanding at once rather than each being finished by its own call.
let t1 = add(1, 2)
let t2 = add(1, 2)
let t3 = add(1, 2)
print await t3

# await on a plain value returns it unchanged rather than treating it as a task
print await 42

# Awaiting the same future twice: 12 both times, so 12+12-12 is 12. A future
# that is consumed by the first await would trap or return nil on the second.
let twice = add(5, 7)
let first = await twice
let second = await twice
print first + second - 12

let main_id = thread.id()
let w1 = await who()
let w2 = await who()
if w1 != main_id and w2 != main_id:
    print "DISTINCT"
else:
    print "SAME_THREAD"
