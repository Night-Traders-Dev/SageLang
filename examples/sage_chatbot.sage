gc_disable()
# SageLLM Chatbot - Interactive conversational bot powered by SageGPT
# Usage: sage examples/sage_chatbot.sage
#
# Features:
# - SageDev persona (Sage language expert)
# - Engram memory (remembers conversation context)
# - Intent recognition for common queries
# - Native ML backend for fast inference
# - Session logging

import chat.bot
import chat.persona
import chat.session
import llm.engram
import llm.tokenizer
import llm.generate
import ml_native
import io

print "============================================"
print "  SageLLM Chatbot v1.0.0"
print "  Powered by SageGPT + Engram Memory"
print "============================================"
print ""

# --- Initialize memory ---
let memory = engram.create(engram.default_config())
engram.store_semantic(memory, "Sage is an indentation-based systems language with C backend", 1.0)
engram.store_semantic(memory, "Sage has 113 library modules across 11 subdirectories", 0.9)
engram.store_semantic(memory, "Sage uses a concurrent tri-color mark-sweep GC", 0.8)
engram.store_semantic(memory, "Sage supports 3 compiler backends: C, LLVM IR, native assembly", 0.9)
engram.store_semantic(memory, "Import dotted paths: import os.fat, import graphics.vulkan", 0.8)

# --- Initialize tokenizer ---
let tok = tokenizer.char_tokenizer()

# --- LLM function (uses Engram context + knowledge base) ---
proc sage_llm(prompt):
    # Search memory for relevant context
    let query = prompt
    if len(query) > 100:
        let short = ""
        for i in range(100):
            short = short + query[i]
        query = short

    let context = engram.build_context(memory, query, 3)

    # Knowledge-based response generation
    let lower_prompt = ""
    for i in range(len(prompt)):
        let code = ord(prompt[i])
        if code >= 65 and code <= 90:
            lower_prompt = lower_prompt + chr(code + 32)
        else:
            lower_prompt = lower_prompt + prompt[i]

    # Pattern matching for common Sage questions
    if contains(lower_prompt, "for loop") or contains(lower_prompt, "iteration"):
        return "In Sage, use for loops with range:" + chr(10) + "  for i in range(10):" + chr(10) + "      print i" + chr(10) + chr(10) + "Or iterate over arrays:" + chr(10) + "  for item in my_array:" + chr(10) + "      print item"

    if contains(lower_prompt, "import") or contains(lower_prompt, "module"):
        return "Sage uses dotted import paths for organized libraries:" + chr(10) + "  import os.fat        # OS development" + chr(10) + "  import net.url       # Networking" + chr(10) + "  import crypto.hash   # Cryptography" + chr(10) + "  import ml.tensor     # Machine learning" + chr(10) + "  import std.regex     # Standard library" + chr(10) + chr(10) + "The last component becomes the binding name."

    if contains(lower_prompt, "class") or contains(lower_prompt, "oop"):
        return "Sage supports OOP with classes:" + chr(10) + "  class Animal:" + chr(10) + "      proc init(self, name):" + chr(10) + "          self.name = name" + chr(10) + "      proc speak(self):" + chr(10) + "          print self.name" + chr(10) + chr(10) + "  class Dog(Animal):" + chr(10) + "      proc speak(self):" + chr(10) + "          print self.name + " + chr(34) + " says woof" + chr(34)

    if contains(lower_prompt, "gc") or contains(lower_prompt, "garbage"):
        return "Sage uses a concurrent tri-color mark-sweep GC with SATB write barriers:" + chr(10) + "  Phase 1 (STW ~50-200us): Root scan, shade gray" + chr(10) + "  Phase 2 (concurrent): Process gray objects" + chr(10) + "  Phase 3 (STW ~20-50us): Remark, drain barriers" + chr(10) + "  Phase 4 (concurrent): Sweep white objects" + chr(10) + chr(10) + "Control with: gc_collect(), gc_enable(), gc_disable()"

    if contains(lower_prompt, "array") or contains(lower_prompt, "list"):
        return "Sage arrays are dynamic:" + chr(10) + "  let arr = [1, 2, 3]" + chr(10) + "  push(arr, 4)" + chr(10) + "  print len(arr)    # 4" + chr(10) + "  print arr[0:2]    # [1, 2]" + chr(10) + "  print pop(arr)    # 4"

    if contains(lower_prompt, "function") or contains(lower_prompt, "proc"):
        return "Define functions with proc:" + chr(10) + "  proc greet(name):" + chr(10) + "      return " + chr(34) + "Hello, " + chr(34) + " + name" + chr(10) + chr(10) + "  print greet(" + chr(34) + "World" + chr(34) + ")  # Hello, World" + chr(10) + chr(10) + "Sage supports closures, recursion, and first-class functions."

    if contains(lower_prompt, "compile") or contains(lower_prompt, "backend"):
        return "Sage has 3 compiler backends:" + chr(10) + "  sage --emit-c file.sage         # C output" + chr(10) + "  sage --compile file.sage        # Compile via C" + chr(10) + "  sage --emit-llvm file.sage      # LLVM IR" + chr(10) + "  sage --compile-llvm file.sage   # Native via LLVM" + chr(10) + "  sage --emit-asm file.sage       # Direct assembly" + chr(10) + "  sage --compile-native file.sage # Native binary"

    if contains(lower_prompt, "help") or contains(lower_prompt, "what can"):
        return "I can help you with:" + chr(10) + "  - Writing Sage code (functions, classes, loops)" + chr(10) + "  - Understanding imports and modules" + chr(10) + "  - Compiler backends (C, LLVM, native)" + chr(10) + "  - GC and memory management" + chr(10) + "  - Standard library usage" + chr(10) + "  - Debugging tips" + chr(10) + chr(10) + "Just ask me anything about Sage!"

    # Default response with memory context
    if len(context) > 0:
        return "Based on what I know:" + chr(10) + context + chr(10) + "Could you be more specific about what you'd like to know about Sage?"

    return "I'm SageDev, your Sage programming assistant. Ask me about writing code, imports, classes, the GC, or compiler backends!"

# --- Create chatbot ---
let chatbot = bot.create("SageDev", "", sage_llm)
persona.apply_persona(chatbot, persona.sage_developer())

# --- Add intents ---
proc handle_greeting(msg, conv):
    return "Hello! I'm SageDev, your Sage programming expert. What would you like to build today?"

proc handle_bye(msg, conv):
    return "Happy coding! Remember: Sage has 113 modules ready for you. See you next time!"

bot.add_intent(chatbot, "greeting", ["hello", "hi", "hey", "greetings"], handle_greeting)
bot.add_intent(chatbot, "farewell", ["bye", "goodbye", "exit", "quit"], handle_bye)

# --- Session ---
let store = session.create_store()
let sess = session.new_session(store, "SageDev")

# --- Main loop ---
print bot.greet(chatbot)
print "Type 'quit' to exit, 'memory' to see memory stats."
print ""

let running = true
while running:
    let user_input = input("You> ")
    if user_input == "quit" or user_input == "exit":
        running = false
        print bot.farewell(chatbot)
    if user_input == "memory":
        if running:
            print engram.summary(memory)
    if user_input == "stats":
        if running:
            print bot.summary(chatbot)
    if running and user_input != "quit" and user_input != "exit" and user_input != "memory" and user_input != "stats":
        # Store in working memory
        engram.store_working(memory, "User asked: " + user_input, 0.7)
        # Get response
        let response = bot.respond(chatbot, user_input)
        print ""
        print "SageDev> " + response
        print ""
        # Log session
        session.add_turn(sess, user_input, response)

# Save session
session.save_session(sess, "sage_chat_log.txt")
print "Chat saved to sage_chat_log.txt"

proc contains(haystack, needle):
    if len(needle) > len(haystack):
        return false
    let lower_h = haystack
    let lower_n = needle
    for i in range(len(lower_h) - len(lower_n) + 1):
        let found = true
        for j in range(len(lower_n)):
            if not found:
                j = len(lower_n)
            if found and lower_h[i + j] != lower_n[j]:
                found = false
        if found:
            return true
    return false
