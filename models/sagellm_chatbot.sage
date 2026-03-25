gc_disable()
# SageLLM Chatbot v1.0.0 - Self-contained compilable binary
# Chain-of-thought reasoning + memory
# Compile: sage --compile models/sagellm_chatbot.sage -o sagellm_chat
# Run:     ./sagellm_chat

proc contains(h, n):
    if len(n) > len(h):
        return false
    for i in range(len(h) - len(n) + 1):
        let f = true
        for j in range(len(n)):
            if not f:
                j = len(n)
            if f and h[i + j] != n[j]:
                f = false
        if f:
            return true
    return false

proc to_lower(s):
    let r = ""
    for i in range(len(s)):
        let c = ord(s[i])
        if c >= 65 and c <= 90:
            r = r + chr(c + 32)
        else:
            r = r + s[i]
    return r

# Memory (simple array-based)
let facts = []
push(facts, "Sage is an indentation-based systems programming language")
push(facts, "118 library modules across 11 subdirectories")
push(facts, "Concurrent tri-color mark-sweep GC with SATB write barriers")
push(facts, "3 compiler backends: C codegen LLVM IR native assembly")
push(facts, "Dotted imports: import os.fat resolves to lib/os/fat.sage")
push(facts, "LLM library has 14 modules for building language models")
push(facts, "Agent framework uses ReAct loop with tools and planning")
push(facts, "229+ tests passing")

let history = []

proc recall(query):
    let results = []
    for i in range(len(facts)):
        if contains(to_lower(facts[i]), query):
            push(results, facts[i])
    return results

proc reason(question):
    let lp = to_lower(question)
    let thoughts = []
    let answer = ""
    let mem = recall(lp)
    if len(mem) > 0:
        push(thoughts, "I recall relevant knowledge")
    else:
        push(thoughts, "Using general knowledge")
    let topic = "general"
    if contains(lp, "llm") or contains(lp, "language model") or contains(lp, "transformer") or contains(lp, "lora") or contains(lp, "engram"):
        topic = "llm"
    if topic == "general" and (contains(lp, "agent") or contains(lp, "react")):
        topic = "agent"
    if topic == "general" and (contains(lp, "loop") or contains(lp, "for") or contains(lp, "while")):
        topic = "loops"
    if topic == "general" and (contains(lp, "import") or contains(lp, "module") or contains(lp, "library")):
        topic = "modules"
    if topic == "general" and (contains(lp, "class") or contains(lp, "inherit")):
        topic = "oop"
    if topic == "general" and (contains(lp, "gc") or contains(lp, "garbage")):
        topic = "gc"
    if topic == "general" and (contains(lp, "compile") or contains(lp, "backend")):
        topic = "compiler"
    if topic == "general" and (contains(lp, "test") or contains(lp, "debug")):
        topic = "testing"
    push(thoughts, "Topic: " + topic)
    if topic == "llm":
        answer = "The Sage LLM library has 14 modules: config, tokenizer, embedding, attention, transformer, generate, train, agent, prompt, lora, quantize, engram, rag, dpo. Plus ml_native C backend."
    if topic == "agent":
        answer = "Agent framework: ReAct loop (observe/think/act/reflect), tool dispatch, task planning, multi-agent routing."
    if topic == "loops":
        answer = "Sage loops:" + chr(10) + "  for i in range(10):" + chr(10) + "      print i" + chr(10) + "  for item in array:" + chr(10) + "      print item"
    if topic == "modules":
        answer = "11 library categories with dotted imports: import os.fat, import net.url, import crypto.hash, import std.regex, import ml.tensor, import llm.agent"
    if topic == "oop":
        answer = "Classes: class Name: with proc init(self): and methods. Supports inheritance."
    if topic == "gc":
        answer = "Concurrent tri-color mark-sweep GC with SATB write barriers. Sub-millisecond STW pauses."
    if topic == "compiler":
        answer = "3 backends: sage --compile (C), sage --compile-llvm (LLVM), sage --compile-native (assembly)"
    if topic == "testing":
        answer = "Run: bash tests/run_tests.sh (229+ tests). Debug: gc_disable() for segfaults."
    if len(answer) == 0:
        if len(mem) > 0:
            answer = mem[0]
        else:
            answer = "I can help with: loops, imports, classes, GC, compiler, LLM, agents, testing."
    push(thoughts, "Answering about " + topic)
    push(history, "Q: " + question)
    push(history, "A: " + answer)
    let result = {}
    result["thoughts"] = thoughts
    result["answer"] = answer
    return result

print "SageLLM Chatbot v1.0.0"
print "Hello. I am SageDev. Ask me about Sage programming."
print "Commands: quit, think <question>"
print ""

let running = true
while running:
    let msg = input("You> ")
    if msg == "quit" or msg == "exit":
        running = false
        print "Goodbye. Happy coding."
    if running and len(msg) > 6 and msg[0] == "t" and msg[1] == "h" and msg[2] == "i" and msg[3] == "n" and msg[4] == "k" and msg[5] == " ":
        let q = ""
        for i in range(len(msg) - 6):
            q = q + msg[6 + i]
        let r = reason(q)
        print ""
        let thoughts = r["thoughts"]
        for i in range(len(thoughts)):
            print "Thought: " + thoughts[i]
        print "Answer: " + r["answer"]
        print ""
    if running and msg != "quit" and msg != "exit":
        let is_think = false
        if len(msg) > 5 and msg[0] == "t" and msg[1] == "h" and msg[2] == "i" and msg[3] == "n" and msg[4] == "k":
            is_think = true
        if not is_think:
            let r = reason(msg)
            print ""
            print "SageDev> " + r["answer"]
            print ""
