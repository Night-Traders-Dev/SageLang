# EXPECT: 4000
import thread
from std.atomic import atomic_int, add, load

let counter = atomic_int(0)

proc worker():
    let i = 0
    while i < 1000:
        add(counter, 1)
        i = i + 1

let handles = []
let i = 0
while i < 4:
    push(handles, thread.spawn(worker))
    i = i + 1
for handle in handles:
    thread.join(handle)
print load(counter)
