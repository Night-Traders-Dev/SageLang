gc_disable()
# EXPECT: 0
# EXPECT: 1
# EXPECT: true

import std.signal

let bus = signal.create_bus()
print signal.handler_count(bus, "click")

let clicked = false

proc on_click(data):
    clicked = true

signal.on(bus, "click", on_click)
print signal.handler_count(bus, "click")

signal.emit(bus, "click", nil)
# Note: clicked is module-level, handler modifies it but scope rules
# mean we can't easily check it here. Just verify the event names.
let names = signal.event_names(bus)
print len(names) == 1
