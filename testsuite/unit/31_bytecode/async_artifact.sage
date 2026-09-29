# RUN: vm-artifact
# EXPECT: 30
# EXPECT: 3
# EXPECT: 42
# EXPECT: 12
# EXPECT: DISTINCT
#
# Async in a real .svm artifact -- the compiled branch of the async worker.
#
# --emit-vm compiles the whole program in STRICT mode and --run-vm runs it with no
# AST in the process, so this is the only way to exercise async through a real
# artifact, and it is the path SageOS and SageVM take. It covers the serializer,
# the loader, the opcode-width and stack-flow tables and the artifact validator
# for the two async opcodes -- all of which reject an artifact the compiler has
# just produced if any one of them is out of step.
#
# The last check is the one that matters. Results alone cannot tell async from a
# synchronous call: both print 30, 3, 42, 12. So this asserts that the body
# actually ran on another thread. It is here because the compiled path did once
# run inline, and the test that missed it was exactly this one without it.
#
# That happened for two reasons, both worth remembering:
#
#   - BC_OP_CALL's fast path pushes a frame and runs the chunk itself, so it
#     never reached the place an async call becomes a task, and an `async proc`
#     is a compiled function like any other;
#   - a compiled function's parameters are stack slots, so the worker had to hand
#     its arguments over the way the call fast path does.
#
# `awaiting` also has to print before the body. A body that ran inline would
# print first, which reads like concurrency and is in fact the signature of the
# bug.

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
