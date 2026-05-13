gc_disable()
# EXPECT: TestBot
# EXPECT: echo response
# EXPECT: 1
# EXPECT: true

import chat.bot
import chat.persona

proc echo_llm(prompt):
    return "echo response"

let b = bot.create("TestBot", "You are a test bot.", echo_llm)
print b["name"]

# Respond
let response = bot.respond(b, "hello")
print response

# Stats
let s = bot.stats(b)
print s["total_messages"]

# Persona
let dev = persona.sage_developer()
print len(dev["personality"]) > 0
