gc_disable()
# EXPECT: true
# EXPECT: 42
# EXPECT: 1
# EXPECT: true
# EXPECT: true

import std.channel

let ch = channel.buffered(10)
channel.send(ch, 42)
channel.send(ch, 99)
print channel.pending(ch) > 0
print channel.recv(ch)
print channel.pending(ch)

# Drain
let vals = channel.drain(ch)
print len(vals) == 1

# Select
let ch2 = channel.buffered(5)
let result = channel.select([ch, ch2])
print result == nil
