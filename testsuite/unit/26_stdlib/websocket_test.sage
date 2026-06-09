gc_disable()
# EXPECT: text
# EXPECT: 5
# EXPECT: true
# EXPECT: true
# EXPECT: hello
# EXPECT: close

import net.websocket

# Build a text frame
let frame = websocket.text_frame("hello")
print websocket.opcode_name(1)
print len("hello")

# Parse the frame back
let parsed = websocket.parse_frame(frame, 0)
print parsed["fin"]
print parsed["opcode"] == 1
print websocket.payload_to_string(parsed["payload"])

# Close frame
let cf = websocket.close_frame(1000)
let parsed_close = websocket.parse_frame(cf, 0)
print parsed_close["opcode_name"]
