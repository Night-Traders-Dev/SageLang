# SageLang Agent & Chatbot Guide

Build autonomous AI agents and conversational chatbots using SageLang's agent and chat frameworks with the SageLLM model backend.

## Agent Framework (`lib/agent/`)

### Quick Start

```sage
import agent.core

proc my_llm(prompt):
    return "ANSWER: Hello!"

let a = core.create("my-agent", "You are helpful.", my_llm)
core.add_tool(a, "greet", "Say hello", "name", proc(args): return "Hi " + args)
let answer = core.run(a, "Greet the user")
print answer
```

### ReAct Loop

The agent follows a ReAct (Reason + Act) pattern:
1. **Observe**: Receive user input
2. **Think**: LLM generates reasoning (THOUGHT:)
3. **Act**: LLM calls a tool (TOOL: name(args))
4. **Reflect**: Process tool result, decide next step
5. **Answer**: LLM provides final answer (ANSWER:)

### Multi-Agent Routing

```sage
import agent.router

let r = router.create_router()
router.register(r, code_agent, ["code", "programming", "bug"])
router.register(r, docs_agent, ["documentation", "explain", "guide"])
router.set_default(r, "code_agent")

let agent = router.route(r, "Fix this bug in the parser")
core.run(agent, "Fix this bug in the parser")
```

### Task Planning

```sage
import agent.planner

let plan = planner.create_plan("Refactor the lexer")
planner.add_step(plan, "Read current lexer code", "read_file", "src/c/lexer.c", nil)
planner.add_step(plan, "Analyze structure", "analyze_code", "", [0])
planner.add_step(plan, "Write improved version", "write_file", "", [1])
planner.execute_plan(plan, my_agent)
```

## Chatbot Framework (`lib/chat/`)

### Quick Start

```sage
import chat.bot
import chat.persona

let b = bot.create("", "", my_llm)
persona.apply_persona(b, persona.sage_developer())
print bot.greet(b)
let response = bot.respond(b, "How do I write a for loop?")
print response
```

### Built-in Personas

| Persona | Use Case |
|---------|----------|
| `sage_developer()` | Sage code help |
| `code_reviewer()` | Code review |
| `teacher()` | Programming education |
| `debugger()` | Bug hunting |
| `architect()` | System design |
| `assistant()` | General help |

### Intent Recognition

```sage
bot.add_intent(b, "greeting", ["hello", "hi", "hey"], proc(msg, conv):
    return "Hello! How can I help?")
bot.add_intent(b, "farewell", ["bye", "goodbye"], proc(msg, conv):
    return "Goodbye!")
```

### Sessions

```sage
import chat.session

let store = session.create_store()
let s = session.new_session(store, "SageDev")
session.add_turn(s, "What is Sage?", "Sage is a systems language.")
print session.export_text(s)
session.save_session(s, "chat_log.txt")
```

## Module Reference

| Module | Import | Key Functions |
|--------|--------|---------------|
| `core` | `import agent.core` | `create`, `add_tool`, `run`, `call_tool`, `think`, `observe`, `act`, `build_prompt` |
| `tools` | `import agent.tools` | `register_all`, `file_read`, `file_write`, `code_analyze`, `code_search` |
| `planner` | `import agent.planner` | `create_plan`, `add_step`, `execute_plan`, `format_plan`, `progress` |
| `router` | `import agent.router` | `create_router`, `register`, `route`, `send_to`, `create_pipeline` |
| `bot` | `import chat.bot` | `create`, `respond`, `add_intent`, `set_context`, `greet`, `farewell` |
| `session` | `import chat.session` | `create_store`, `new_session`, `add_turn`, `export_text`, `save_session` |
| `persona` | `import chat.persona` | `sage_developer`, `code_reviewer`, `teacher`, `debugger`, `architect`, `custom` |
