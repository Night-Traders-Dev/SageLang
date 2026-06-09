# Discord Gateway Types and Constants

let GATEWAY_VERSION = 10
let GATEWAY_URL = "wss://gateway.discord.gg/?v=" + str(GATEWAY_VERSION) + "&encoding=json"

# Opcodes
let OP_DISPATCH = 0
let OP_HEARTBEAT = 1
let OP_IDENTIFY = 2
let OP_PRESENCE_UPDATE = 3
let OP_VOICE_STATE_UPDATE = 4
let OP_RESUME = 6
let OP_RECONNECT = 7
let OP_REQUEST_GUILD_MEMBERS = 8
let OP_INVALID_SESSION = 9
let OP_HELLO = 10
let OP_HEARTBEAT_ACK = 11
