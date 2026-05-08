# EXPECT: on_ok
# EXPECT: once_ok
# EXPECT: off_ok
# EXPECT: multi_handler_ok
# EXPECT: atexit_ok
# EXPECT: PASS
from std.signal import create_bus, on, once, emit, off, clear, handler_count, event_names
from std.signal import atexit, run_atexit

# --- on / emit ---
let bus = create_bus()
let received = 0
proc handler1(data):
    received = received + data
end
on(bus, "tick", handler1)
emit(bus, "tick", 5)
emit(bus, "tick", 3)
if received == 8:
    print "on_ok"
end

# --- once: fires only once ---
let bus2 = create_bus()
let once_count = 0
proc once_handler(data):
    once_count = once_count + 1
end
once(bus2, "start", once_handler)
emit(bus2, "start", nil)
emit(bus2, "start", nil)  # should not fire again
if once_count == 1:
    print "once_ok"
end

# --- off: removes handlers ---
let bus3 = create_bus()
let fired = 0
proc h(data):
    fired = fired + 1
end
on(bus3, "ev", h)
emit(bus3, "ev", nil)
off(bus3, "ev")
emit(bus3, "ev", nil)  # should not fire
if fired == 1:
    if handler_count(bus3, "ev") == 0:
        print "off_ok"
    end
end

# --- multiple handlers on same event ---
let bus4 = create_bus()
let total = 0
proc ha(data):
    total = total + 1
end
proc hb(data):
    total = total + 10
end
proc hc(data):
    total = total + 100
end
on(bus4, "multi", ha)
on(bus4, "multi", hb)
on(bus4, "multi", hc)
emit(bus4, "multi", nil)
if total == 111:
    let names = event_names(bus4)
    if len(names) == 1 and names[0] == "multi":
        print "multi_handler_ok"
    end
end

# --- atexit (LIFO order) ---
let order = []
proc exit1():
    push(order, 1)
end
proc exit2():
    push(order, 2)
end
proc exit3():
    push(order, 3)
end
atexit(exit1)
atexit(exit2)
atexit(exit3)
run_atexit()
# LIFO: 3, 2, 1
if len(order) == 3 and order[0] == 3 and order[1] == 2 and order[2] == 1:
    print "atexit_ok"
end

print "PASS"
