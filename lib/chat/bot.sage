gc_disable()
# Chatbot framework
# Provides conversation management, personality, intents, and response generation

# ============================================================================
# Chatbot creation
# ============================================================================

proc create(name, personality, llm_fn):
    let bot = {}
    bot["name"] = name
    bot["personality"] = personality
    bot["llm_fn"] = llm_fn
    bot["conversations"] = {}
    bot["active_conversation"] = nil
    bot["intents"] = []
    bot["fallback_response"] = "I don't understand. Can you rephrase?"
    bot["greeting"] = "Hello! How can I help you?"
    bot["goodbye"] = "Goodbye!"
    bot["middleware"] = []
    bot["total_messages"] = 0
    bot["response_hooks"] = []
    return bot

# ============================================================================
# Conversation management
# ============================================================================

proc create_conversation(bot, conv_id):
    let conv = {}
    conv["id"] = conv_id
    conv["messages"] = []
    conv["context"] = {}
    conv["started"] = clock()
    conv["active"] = true
    conv["turn_count"] = 0
    bot["conversations"][conv_id] = conv
    bot["active_conversation"] = conv_id
    return conv

proc get_conversation(bot, conv_id):
    if dict_has(bot["conversations"], conv_id):
        return bot["conversations"][conv_id]
    return nil

proc active_conversation(bot):
    if bot["active_conversation"] != nil:
        return get_conversation(bot, bot["active_conversation"])
    return nil

proc add_message(conv, role, content):
    let msg = {}
    msg["role"] = role
    msg["content"] = content
    msg["timestamp"] = clock()
    push(conv["messages"], msg)
    conv["turn_count"] = conv["turn_count"] + 1
    return msg

# ============================================================================
# Intent recognition (rule-based)
# ============================================================================

proc add_intent(bot, name, keywords, handler):
    let intent = {}
    intent["name"] = name
    intent["keywords"] = keywords
    intent["handler"] = handler
    intent["matches"] = 0
    push(bot["intents"], intent)

proc match_intent(bot, message):
    let lower_msg = to_lower(message)
    let best_intent = nil
    let best_score = 0
    for i in range(len(bot["intents"])):
        let intent = bot["intents"][i]
        let score = 0
        let keywords = intent["keywords"]
        for k in range(len(keywords)):
            if contains(lower_msg, keywords[k]):
                score = score + 1
        if score > best_score:
            best_score = score
            best_intent = intent
    return best_intent

# ============================================================================
# Middleware (pre/post processing)
# ============================================================================

proc add_middleware(bot, fn):
    push(bot["middleware"], fn)

proc add_response_hook(bot, fn):
    push(bot["response_hooks"], fn)

proc apply_middleware(bot, message):
    let processed = message
    for i in range(len(bot["middleware"])):
        processed = bot["middleware"][i](processed)
    return processed

proc apply_response_hooks(bot, response):
    let processed = response
    for i in range(len(bot["response_hooks"])):
        processed = bot["response_hooks"][i](processed)
    return processed

# ============================================================================
# Response generation
# ============================================================================

proc build_chat_prompt(bot, conv):
    let prompt = "You are " + bot["name"] + ". " + bot["personality"] + chr(10) + chr(10)
    # Include context
    let ctx_keys = dict_keys(conv["context"])
    if len(ctx_keys) > 0:
        prompt = prompt + "Context:" + chr(10)
        for i in range(len(ctx_keys)):
            prompt = prompt + "  " + ctx_keys[i] + ": " + str(conv["context"][ctx_keys[i]]) + chr(10)
        prompt = prompt + chr(10)
    # Include conversation history (last 20 turns)
    let msgs = conv["messages"]
    let start = 0
    if len(msgs) > 20:
        start = len(msgs) - 20
    for i in range(len(msgs) - start):
        let msg = msgs[start + i]
        prompt = prompt + msg["role"] + ": " + msg["content"] + chr(10)
    prompt = prompt + "assistant: "
    return prompt

proc respond(bot, user_message):
    bot["total_messages"] = bot["total_messages"] + 1
    # Apply middleware
    let processed = apply_middleware(bot, user_message)
    # Get or create conversation
    let conv = active_conversation(bot)
    if conv == nil:
        conv = create_conversation(bot, "default")
    # Record user message
    add_message(conv, "user", processed)
    # Check intents first
    let intent = match_intent(bot, processed)
    let response = nil
    if intent != nil:
        intent["matches"] = intent["matches"] + 1
        response = intent["handler"](processed, conv)
    # If no intent matched, use LLM
    if response == nil and bot["llm_fn"] != nil:
        let prompt = build_chat_prompt(bot, conv)
        response = bot["llm_fn"](prompt)
    # Fallback
    if response == nil:
        response = bot["fallback_response"]
    # Apply response hooks
    response = apply_response_hooks(bot, response)
    # Record assistant message
    add_message(conv, "assistant", response)
    return response

# ============================================================================
# Context management
# ============================================================================

proc set_context(bot, key, value):
    let conv = active_conversation(bot)
    if conv != nil:
        conv["context"][key] = value

proc get_context(bot, key):
    let conv = active_conversation(bot)
    if conv == nil:
        return nil
    if dict_has(conv["context"], key):
        return conv["context"][key]
    return nil

proc clear_context(bot):
    let conv = active_conversation(bot)
    if conv != nil:
        conv["context"] = {}

# ============================================================================
# Utility responses
# ============================================================================

proc greet(bot):
    return bot["greeting"]

proc farewell(bot):
    return bot["goodbye"]

# ============================================================================
# Stats
# ============================================================================

proc stats(bot):
    let s = {}
    s["name"] = bot["name"]
    s["total_messages"] = bot["total_messages"]
    s["conversations"] = len(dict_keys(bot["conversations"]))
    s["intents"] = len(bot["intents"])
    s["middleware"] = len(bot["middleware"])
    return s

proc summary(bot):
    let s = stats(bot)
    let nl = chr(10)
    return "Bot: " + s["name"] + nl + "Messages: " + str(s["total_messages"]) + nl + "Conversations: " + str(s["conversations"]) + nl + "Intents: " + str(s["intents"]) + nl

# ============================================================================
# Helpers
# ============================================================================

proc to_lower(s):
    let result = ""
    for i in range(len(s)):
        let code = ord(s[i])
        if code >= 65 and code <= 90:
            result = result + chr(code + 32)
        else:
            result = result + s[i]
    return result

proc contains(haystack, needle):
    if len(needle) > len(haystack):
        return false
    for i in range(len(haystack) - len(needle) + 1):
        let found = true
        for j in range(len(needle)):
            if not found:
                j = len(needle)
            if found and haystack[i + j] != needle[j]:
                found = false
        if found:
            return true
    return false
