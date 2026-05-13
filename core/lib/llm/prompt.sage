gc_disable()
# Prompt templates and chat formatting for LLMs
# Supports ChatML, Llama, Alpaca, and custom formats

# ============================================================================
# Message types
# ============================================================================

let ROLE_SYSTEM = "system"
let ROLE_USER = "user"
let ROLE_ASSISTANT = "assistant"
let ROLE_TOOL = "tool"

proc message(role, content):
    let msg = {}
    msg["role"] = role
    msg["content"] = content
    return msg

proc system_message(content):
    return message("system", content)

proc user_message(content):
    return message("user", content)

proc assistant_message(content):
    return message("assistant", content)

proc tool_message(name, content):
    let msg = message("tool", content)
    msg["name"] = name
    return msg

# ============================================================================
# Chat history
# ============================================================================

proc create_chat():
    let chat = {}
    chat["messages"] = []
    return chat

proc add_message(chat, msg):
    push(chat["messages"], msg)

proc add_system(chat, content):
    add_message(chat, system_message(content))

proc add_user(chat, content):
    add_message(chat, user_message(content))

proc add_assistant(chat, content):
    add_message(chat, assistant_message(content))

proc last_message(chat):
    if len(chat["messages"]) == 0:
        return nil
    return chat["messages"][len(chat["messages"]) - 1]

proc message_count(chat):
    return len(chat["messages"])

# ============================================================================
# Prompt formats
# ============================================================================

# ChatML format (OpenAI style)
proc format_chatml(messages):
    let result = ""
    for i in range(len(messages)):
        let msg = messages[i]
        result = result + "<|im_start|>" + msg["role"] + chr(10)
        result = result + msg["content"] + chr(10)
        result = result + "<|im_end|>" + chr(10)
    result = result + "<|im_start|>assistant" + chr(10)
    return result

# Llama chat format
proc format_llama(messages):
    let result = ""
    for i in range(len(messages)):
        let msg = messages[i]
        if msg["role"] == "system":
            result = result + "<<SYS>>" + chr(10) + msg["content"] + chr(10) + "<</SYS>>" + chr(10) + chr(10)
        if msg["role"] == "user":
            result = result + "[INST] " + msg["content"] + " [/INST]" + chr(10)
        if msg["role"] == "assistant":
            result = result + msg["content"] + chr(10)
    return result

# Alpaca instruction format
proc format_alpaca(instruction, input_text):
    let result = "Below is an instruction that describes a task"
    if len(input_text) > 0:
        result = result + ", paired with an input that provides further context"
    result = result + ". Write a response that appropriately completes the request." + chr(10) + chr(10)
    result = result + "### Instruction:" + chr(10) + instruction + chr(10) + chr(10)
    if len(input_text) > 0:
        result = result + "### Input:" + chr(10) + input_text + chr(10) + chr(10)
    result = result + "### Response:" + chr(10)
    return result

# Simple format (plain text with role labels)
proc format_simple(messages):
    let result = ""
    for i in range(len(messages)):
        let msg = messages[i]
        result = result + msg["role"] + ": " + msg["content"] + chr(10)
    result = result + "assistant: "
    return result

# ============================================================================
# Prompt templates
# ============================================================================

proc create_template(template_str):
    let tmpl = {}
    tmpl["template"] = template_str
    return tmpl

proc render_template(tmpl, variables):
    let result = tmpl["template"]
    let keys = dict_keys(variables)
    for i in range(len(keys)):
        let placeholder = "{" + keys[i] + "}"
        let replacement = str(variables[keys[i]])
        # Simple replace
        let new_result = ""
        let j = 0
        while j < len(result):
            let found_placeholder = false
            if j + len(placeholder) <= len(result):
                let sub_match = true
                for k in range(len(placeholder)):
                    if result[j + k] != placeholder[k]:
                        sub_match = false
                if sub_match:
                    new_result = new_result + replacement
                    j = j + len(placeholder)
                    found_placeholder = true
            if not found_placeholder:
                new_result = new_result + result[j]
                j = j + 1
        result = new_result
    return result

# ============================================================================
# Common prompt builders
# ============================================================================

# Build a few-shot prompt from examples
proc few_shot(instruction, examples, query):
    let prompt = instruction + chr(10) + chr(10)
    for i in range(len(examples)):
        let ex = examples[i]
        prompt = prompt + "Input: " + ex["input"] + chr(10)
        prompt = prompt + "Output: " + ex["output"] + chr(10) + chr(10)
    prompt = prompt + "Input: " + query + chr(10)
    prompt = prompt + "Output: "
    return prompt

# Build a chain-of-thought prompt
proc cot_prompt(question):
    return question + chr(10) + chr(10) + "Let's think step by step:" + chr(10)

# Build a summarization prompt
proc summarize_prompt(text, max_words):
    return "Summarize the following text in " + str(max_words) + " words or less:" + chr(10) + chr(10) + text + chr(10) + chr(10) + "Summary:"

# Build a code generation prompt
proc code_prompt(language, task):
    return "Write " + language + " code to " + task + ":" + chr(10) + chr(10) + "```" + language + chr(10)

# Build a classification prompt
proc classify_prompt(text, categories):
    let cats = ""
    for i in range(len(categories)):
        if i > 0:
            cats = cats + ", "
        cats = cats + categories[i]
    return "Classify the following text into one of these categories: " + cats + chr(10) + chr(10) + "Text: " + text + chr(10) + chr(10) + "Category:"

# ============================================================================
# Token counting estimation
# ============================================================================

# Rough token count estimate (4 chars per token average)
proc estimate_tokens(text):
    return ((len(text) + 3) / 4) | 0

# Check if prompt fits within context window
proc fits_context(text, max_tokens):
    return estimate_tokens(text) <= max_tokens

# Truncate messages to fit context
proc truncate_history(messages, max_tokens, keep_system):
    let result = []
    let total = 0
    # Always keep system message
    if keep_system and len(messages) > 0 and messages[0]["role"] == "system":
        push(result, messages[0])
        total = total + estimate_tokens(messages[0]["content"])
    # Add from most recent
    let i = len(messages) - 1
    let to_add = []
    while i >= 0:
        if messages[i]["role"] != "system":
            let tokens = estimate_tokens(messages[i]["content"])
            if total + tokens <= max_tokens:
                push(to_add, messages[i])
                total = total + tokens
        i = i - 1
    # Reverse to_add and append
    let j = len(to_add) - 1
    while j >= 0:
        push(result, to_add[j])
        j = j - 1
    return result
