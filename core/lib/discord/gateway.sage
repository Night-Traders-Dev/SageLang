import json
import discord.types

# Helper to build a gateway payload
proc build_payload(op, data):
    let payload = {}
    payload["op"] = op
    payload["d"] = data
    return json.encode(payload)

# Helper to build an identify payload
proc identify_payload(token, intents):
    let data = {}
    data["token"] = token
    data["intents"] = intents
    data["properties"] = {
        "$os": "linux",
        "$browser": "sagelang",
        "$device": "sagelang"
    }
    return build_payload(discord.types.OP_IDENTIFY, data)

# Helper to build a heartbeat payload
proc heartbeat_payload(last_seq):
    return build_payload(discord.types.OP_HEARTBEAT, last_seq)
