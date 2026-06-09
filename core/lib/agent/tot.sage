gc_disable()
# Tree of Thoughts (ToT) with State Rollbacks
# Implements MCTS-style search over reasoning steps.
# The model generates multiple candidate next steps, an evaluator scores them,
# and the agent proceeds down the best path with rollback on dead ends.

# ============================================================================
# Thought node
# ============================================================================

proc create_node(state, thought, parent_id, depth):
    let node = {}
    node["id"] = 0
    node["state"] = state
    node["thought"] = thought
    node["parent_id"] = parent_id
    node["depth"] = depth
    node["score"] = 0
    node["children"] = []
    node["is_terminal"] = false
    node["is_solution"] = false
    return node

# ============================================================================
# Tree of Thoughts solver
# ============================================================================

proc create_solver(evaluator_fn, max_depth, branching_factor):
    let solver = {}
    solver["evaluator"] = evaluator_fn
    solver["max_depth"] = max_depth
    solver["branching"] = branching_factor
    solver["nodes"] = []
    solver["next_id"] = 0
    solver["best_path"] = []
    solver["best_score"] = -1
    solver["nodes_explored"] = 0
    solver["rollbacks"] = 0
    return solver

proc add_node(solver, node):
    node["id"] = solver["next_id"]
    solver["next_id"] = solver["next_id"] + 1
    push(solver["nodes"], node)
    return node["id"]

# Generate candidate next thoughts using an LLM
proc generate_candidates(solver, llm_fn, state, num_candidates):
    let candidates = []
    let prompt = "Given this state:" + chr(10) + state + chr(10) + chr(10) + "Generate " + str(num_candidates) + " different possible next steps. Output each on a separate line starting with STEP:"
    let response = llm_fn(prompt)
    let lines = split_lines(response)
    for i in range(len(lines)):
        let line = lines[i]
        if len(line) > 6 and line[0] == "S" and line[1] == "T" and line[2] == "E" and line[3] == "P" and line[4] == ":":
            let step = ""
            let j = 5
            if j < len(line) and line[j] == " ":
                j = 6
            while j < len(line):
                step = step + line[j]
                j = j + 1
            push(candidates, step)
    # If parsing failed, use the whole response as a single candidate
    if len(candidates) == 0:
        push(candidates, response)
    return candidates

# Score a candidate thought using the evaluator
proc evaluate(solver, state, thought):
    solver["nodes_explored"] = solver["nodes_explored"] + 1
    return solver["evaluator"](state, thought)

# ============================================================================
# Search algorithms
# ============================================================================

# Breadth-First Search (BFS) over thoughts
proc bfs_search(solver, llm_fn, initial_state, goal_check):
    let root = create_node(initial_state, "start", -1, 0)
    add_node(solver, root)
    let queue = [0]
    while len(queue) > 0:
        let current_id = queue[0]
        let new_queue = []
        for i in range(len(queue) - 1):
            push(new_queue, queue[i + 1])
        queue = new_queue
        let current = solver["nodes"][current_id]
        if current["depth"] >= solver["max_depth"]:
            continue
        # Generate candidates
        let candidates = generate_candidates(solver, llm_fn, current["state"], solver["branching"])
        for i in range(len(candidates)):
            let score = evaluate(solver, current["state"], candidates[i])
            let new_state = current["state"] + chr(10) + "Step: " + candidates[i]
            let child = create_node(new_state, candidates[i], current_id, current["depth"] + 1)
            child["score"] = score
            let child_id = add_node(solver, child)
            push(current["children"], child_id)
            # Check if this is a solution
            if goal_check(new_state):
                child["is_solution"] = true
                child["is_terminal"] = true
                return get_path(solver, child_id)
            push(queue, child_id)
    return nil

# Best-First Search (greedy, follows highest-scoring path)
proc best_first_search(solver, llm_fn, initial_state, goal_check):
    let root = create_node(initial_state, "start", -1, 0)
    add_node(solver, root)
    let current_id = 0
    while solver["nodes"][current_id]["depth"] < solver["max_depth"]:
        let current = solver["nodes"][current_id]
        let candidates = generate_candidates(solver, llm_fn, current["state"], solver["branching"])
        # Score all candidates
        let best_idx = 0
        let best_score = -1
        for i in range(len(candidates)):
            let score = evaluate(solver, current["state"], candidates[i])
            if score > best_score:
                best_score = score
                best_idx = i
        # Create the best child
        let new_state = current["state"] + chr(10) + "Step: " + candidates[best_idx]
        let child = create_node(new_state, candidates[best_idx], current_id, current["depth"] + 1)
        child["score"] = best_score
        let child_id = add_node(solver, child)
        push(current["children"], child_id)
        if best_score < 0.1:
            solver["rollbacks"] = solver["rollbacks"] + 1
            # Dead end — rollback to parent and try next
            if current["parent_id"] >= 0:
                current_id = current["parent_id"]
                continue
            else:
                return nil
        if goal_check(new_state):
            child["is_solution"] = true
            return get_path(solver, child_id)
        current_id = child_id
    return nil

# ============================================================================
# Path reconstruction
# ============================================================================

proc get_path(solver, node_id):
    let path = []
    let current = node_id
    while current >= 0:
        let node = solver["nodes"][current]
        push(path, node)
        current = node["parent_id"]
    # Reverse
    let reversed = []
    let i = len(path) - 1
    while i >= 0:
        push(reversed, path[i])
        i = i - 1
    return reversed

proc format_path(path):
    let result = "Solution path:" + chr(10)
    for i in range(len(path)):
        let node = path[i]
        result = result + "  " + str(i) + ". " + node["thought"] + " (score: " + str(node["score"]) + ")" + chr(10)
    return result

# ============================================================================
# Statistics
# ============================================================================

proc stats(solver):
    let s = {}
    s["total_nodes"] = len(solver["nodes"])
    s["explored"] = solver["nodes_explored"]
    s["rollbacks"] = solver["rollbacks"]
    s["max_depth"] = solver["max_depth"]
    s["branching"] = solver["branching"]
    s["best_score"] = solver["best_score"]
    return s

proc split_lines(text):
    let lines = []
    let current = ""
    for i in range(len(text)):
        if text[i] == chr(10):
            push(lines, current)
            current = ""
        if text[i] != chr(10) and text[i] != chr(13):
            current = current + text[i]
    if len(current) > 0:
        push(lines, current)
    return lines
