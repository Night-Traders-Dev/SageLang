gc_disable()
# EXPECT: idle
# EXPECT: true
# EXPECT: completed
# EXPECT: true

import agent.supervisor

proc mock_llm(task):
    return "done: " + task

let w = supervisor.create_worker("coder", "Write code", mock_llm, [])
let sup = supervisor.create_supervisor("boss", mock_llm)
print sup["status"]

supervisor.add_worker(sup, w)
print len(sup["worker_list"]) == 1

# Add workflow step
supervisor.add_step(sup, "Write hello world", "coder", nil, nil)
let status = supervisor.run_workflow(sup)
print status

print sup["stats"]["tasks_succeeded"] == 1
