gc_disable()
# EXPECT: test-agent
# EXPECT: true
# EXPECT: true
# EXPECT: true
# EXPECT: pending

import llm.agent

# Create agent
let a = agent.create_agent("test-agent", "You are helpful.")
print a["name"]

# Tools
proc calc_tool(args):
    return 42

agent.add_tool(a, "calculator", "Compute math", calc_tool)
let result = agent.call_tool(a["toolbox"], "calculator", {})
print result["result"] == 42

# Memory
agent.add_fact(a["memory"], "The sky is blue")
let facts = agent.get_facts(a["memory"])
print len(facts) == 1

# Chain of thought
let chain = agent.create_reasoning_chain()
agent.add_thought(chain, "I need to calculate")
agent.add_action(chain, "calculator", 42)
print len(chain["steps"]) == 2

# Planning
let plan = agent.create_plan("Build a house")
agent.add_plan_step(plan, "Get materials", "builder")
agent.add_plan_step(plan, "Build walls", "builder")
print plan["status"]
