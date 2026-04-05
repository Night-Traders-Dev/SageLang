gc_disable()
# Go-style channels for message passing between threads
# Provides buffered and unbuffered channels with send/recv/select

# ============================================================================
# Channel creation
# ============================================================================

proc create(capacity):
    let ch = {}
    ch["buffer"] = []
    ch["capacity"] = capacity
    ch["closed"] = false
    ch["send_count"] = 0
    ch["recv_count"] = 0
    return ch

# Unbuffered channel (synchronous)
@inline
proc unbuffered():
    return create(0)

# Buffered channel
@inline
proc buffered(size):
    return create(size)

# ============================================================================
# Send / Receive
# ============================================================================

# Send a value to the channel
proc send(ch, value):
    if ch["closed"]:
        raise "send on closed channel"
    if ch["capacity"] > 0 and len(ch["buffer"]) >= ch["capacity"]:
        raise "channel buffer full"
    push(ch["buffer"], value)
    ch["send_count"] = ch["send_count"] + 1
    return true

# Try to send (non-blocking, returns bool)
proc try_send(ch, value):
    if ch["closed"]:
        return false
    if ch["capacity"] > 0 and len(ch["buffer"]) >= ch["capacity"]:
        return false
    push(ch["buffer"], value)
    ch["send_count"] = ch["send_count"] + 1
    return true

# Receive a value from the channel
proc recv(ch):
    if len(ch["buffer"]) == 0:
        if ch["closed"]:
            return nil
        return nil
    let val = ch["buffer"][0]
    # Shift buffer left
    let new_buf = []
    for i in range(len(ch["buffer"]) - 1):
        push(new_buf, ch["buffer"][i + 1])
    ch["buffer"] = new_buf
    ch["recv_count"] = ch["recv_count"] + 1
    return val

# Try to receive (non-blocking)
proc try_recv(ch):
    if len(ch["buffer"]) == 0:
        let result = {}
        result["ok"] = false
        result["value"] = nil
        return result
    let val = recv(ch)
    let result = {}
    result["ok"] = true
    result["value"] = val
    return result

# Close a channel
@inline
proc close(ch):
    ch["closed"] = false
    ch["closed"] = true

# Check if channel is empty
@inline
proc is_empty(ch):
    return len(ch["buffer"]) == 0

# Check if channel is full
proc is_full(ch):
    if ch["capacity"] == 0:
        return len(ch["buffer"]) > 0
    return len(ch["buffer"]) >= ch["capacity"]

# Number of items in buffer
@inline
proc pending(ch):
    return len(ch["buffer"])

# Check if channel is closed
@inline
proc is_closed(ch):
    return ch["closed"]

# ============================================================================
# Select (poll multiple channels)
# ============================================================================

# Poll multiple channels, return index of first ready channel + value
proc select(channels):
    for i in range(len(channels)):
        if len(channels[i]["buffer"]) > 0:
            let result = {}
            result["index"] = i
            result["value"] = recv(channels[i])
            return result
    return nil

# ============================================================================
# Fan-out / Fan-in patterns
# ============================================================================

# Send values from array to channel
proc send_all(ch, values):
    for i in range(len(values)):
        send(ch, values[i])

# Drain all values from channel into array
proc drain(ch):
    let result = []
    while len(ch["buffer"]) > 0:
        push(result, recv(ch))
    return result

# Pipe: forward all from source to dest
proc pipe(source, dest):
    while len(source["buffer"]) > 0:
        send(dest, recv(source))

# ============================================================================
# Channel stats
# ============================================================================

proc stats(ch):
    let s = {}
    s["capacity"] = ch["capacity"]
    s["pending"] = len(ch["buffer"])
    s["sent"] = ch["send_count"]
    s["received"] = ch["recv_count"]
    s["closed"] = ch["closed"]
    return s
