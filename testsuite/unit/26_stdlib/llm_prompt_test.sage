gc_disable()
# EXPECT: system
# EXPECT: user
# EXPECT: true
# EXPECT: true
# EXPECT: true

import llm.prompt

let sys = prompt.system_message("You are helpful")
print sys["role"]

let usr = prompt.user_message("Hello")
print usr["role"]

# Chat
let chat = prompt.create_chat()
prompt.add_system(chat, "You are helpful")
prompt.add_user(chat, "Hello")
print prompt.message_count(chat) == 2

# Format
let formatted = prompt.format_simple(chat["messages"])
print len(formatted) > 0

# Template
let tmpl = prompt.create_template("Hello {name}")
let rendered = prompt.render_template(tmpl, {"name": "World"})
print rendered == "Hello World"
