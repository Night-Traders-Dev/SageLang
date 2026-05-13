gc_disable()
# EXPECT: number
# EXPECT: string
# EXPECT: 2

import std.debug

print debug.type_name(42)
print debug.type_name("hello")

# Watch (without triggering change output)
let w = debug.create_watcher()
debug.watch(w, "x", 10)
let h = debug.watch_history(w, "x")
debug.watch(w, "y", 20)
print len(debug.watch_history(w, "x")) + len(debug.watch_history(w, "y"))
