gc_disable()
# EXPECT: true
# EXPECT: 0
# EXPECT: true

import agent.tot

proc mock_eval(state, thought):
    return 0.8

let solver = tot.create_solver(mock_eval, 3, 2)
print solver["max_depth"] == 3

let root = tot.create_node("initial state", "start", -1, 0)
tot.add_node(solver, root)
print solver["rollbacks"]

let s = tot.stats(solver)
print s["total_nodes"] == 1
