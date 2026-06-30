import std.signal

let bus = signal.create_bus()

# Listen for an event
proc on_msg(data):
    print "Received: " + data

signal.on(bus, "message", on_msg)

# Emit event
signal.emit(bus, "message", "Hello World")

# One-time listener
signal.once(bus, "shutdown", proc(data): print "Shutting down" end)

# Deferred cleanup (atexit)
signal.atexit(proc(): print "Final cleanup" end)
