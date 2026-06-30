# Test anonymous proc expressions as the user's example
import std.signal

let bus = signal.create_bus()

# Listen for an event
proc on_msg(data):
    print "Received: " + data

signal.on(bus, "message", on_msg)

# Emit event
signal.emit(bus, "message", "Hello World")

# One-time listener with inline proc using 'end' keyword
signal.once(bus, "shutdown", proc(data): print "Shutting down" end)

# One-time listener with multi-line proc
signal.once(bus, "cleanup", proc():
    print "Cleaning up resources"
end)

# Emit shutdown (triggers once handler)
signal.emit(bus, "shutdown", nil)

# Emit cleanup (triggers multi-line once handler)
signal.emit(bus, "cleanup", nil)

# Deferred cleanup (atexit) with no-param proc
signal.atexit(proc(): print "Final cleanup" end)

# Run atexit handlers
signal.run_atexit()

print "All tests passed!"
