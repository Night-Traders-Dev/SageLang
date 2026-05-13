gc_disable()
# Signal handling and event system
# Provides a publish-subscribe event bus for application-level signals

# Signal constants (POSIX-style names for documentation, actual handling is app-level)
let SIGINT = 2
let SIGTERM = 15
let SIGHUP = 1
let SIGUSR1 = 10
let SIGUSR2 = 12

# ============================================================================
# Event bus / signal dispatcher
# ============================================================================

proc create_bus():
    let bus = {}
    bus["handlers"] = {}
    bus["once_handlers"] = {}
    return bus

# Register a handler for a signal/event name
proc on(bus, event_name, handler):
    if not dict_has(bus["handlers"], event_name):
        bus["handlers"][event_name] = []
    push(bus["handlers"][event_name], handler)

# Register a one-time handler
proc once(bus, event_name, handler):
    if not dict_has(bus["once_handlers"], event_name):
        bus["once_handlers"][event_name] = []
    push(bus["once_handlers"][event_name], handler)

# Emit a signal/event
proc emit(bus, event_name, data):
    # Regular handlers
    if dict_has(bus["handlers"], event_name):
        let handlers = bus["handlers"][event_name]
        for i in range(len(handlers)):
            handlers[i](data)
    # One-time handlers (removed after calling)
    if dict_has(bus["once_handlers"], event_name):
        let handlers = bus["once_handlers"][event_name]
        for i in range(len(handlers)):
            handlers[i](data)
        bus["once_handlers"][event_name] = []

# Remove all handlers for an event
proc off(bus, event_name):
    if dict_has(bus["handlers"], event_name):
        bus["handlers"][event_name] = []
    if dict_has(bus["once_handlers"], event_name):
        bus["once_handlers"][event_name] = []

# Remove all handlers
proc clear(bus):
    bus["handlers"] = {}
    bus["once_handlers"] = {}

# Count handlers for an event
proc handler_count(bus, event_name):
    let count = 0
    if dict_has(bus["handlers"], event_name):
        count = count + len(bus["handlers"][event_name])
    if dict_has(bus["once_handlers"], event_name):
        count = count + len(bus["once_handlers"][event_name])
    return count

# List all registered event names
proc event_names(bus):
    let names = []
    let keys = dict_keys(bus["handlers"])
    for i in range(len(keys)):
        if len(bus["handlers"][keys[i]]) > 0:
            push(names, keys[i])
    return names

# ============================================================================
# Deferred execution (atexit-style)
# ============================================================================

let _atexit_handlers = []

proc atexit(handler):
    push(_atexit_handlers, handler)

proc run_atexit():
    let i = len(_atexit_handlers) - 1
    while i >= 0:
        _atexit_handlers[i]()
        i = i - 1
