gc_disable()
# EXPECT: test-agent
# EXPECT: idle
# EXPECT: 42
# EXPECT: true
# EXPECT: done

import agent.core

proc mock_llm(prompt):
    return "ANSWER: The answer is 42"

let a = core.create("test-agent", "You are helpful.", mock_llm)
print a["name"]
print core.state_name(a["state"])

# Add tool
proc calc(args):
    return 42

core.add_tool(a, "calc", "Calculate", "expr", calc)
let result = core.call_tool(a, "calc", "1+1")
print result["result"]
print result["ok"]

# Run agent
let answer = core.run(a, "What is 1+1?")
print core.state_name(a["state"])
