gc_disable()
# ============================================================================
# autoresearch.sage — Karpathy-style Autonomous Research Agent
#
# Implements the "ratchet loop" from Karpathy's autoresearch project:
#   1. Propose a change (via LLM or mutation strategy)
#   2. Apply the change to a mutable config/model
#   3. Train for a fixed time budget (N steps)
#   4. Evaluate against a numerical metric (lower is better)
#   5. If improved: KEEP (commit to journal), else DISCARD (revert)
#   6. Repeat
#
# Key concepts:
#   - Fixed compute budget per experiment (wall-clock or step-count)
#   - One-file-editable: only the "research target" is modified
#   - Git-like ratchet: improvements accumulate, failures revert
#   - Research journal: full log of what was tried, what worked/failed
#   - Program-directed: a "program" string guides what to explore
#   - Multi-metric: primary metric + optional secondary checks
#
# Usage:
#   import llm.autoresearch
#   let researcher = autoresearch.create(config, train_fn, eval_fn)
#   autoresearch.set_program(researcher, "Explore learning rate 0.0001-0.01")
#   autoresearch.run(researcher, 50)  # 50 experiments
#   print autoresearch.summary(researcher)
#
# Reference: github.com/karpathy/autoresearch (March 2026)
# ============================================================================

# ============================================================================
# Research session creation
# ============================================================================

proc create(config, train_fn, eval_fn):
    # config: dict with mutable hyperparameters
    # train_fn: proc(config) -> trains for budget, returns train_loss
    # eval_fn: proc(config) -> returns numerical score (lower = better)
    let session = {}
    session["config"] = config
    session["train_fn"] = train_fn
    session["eval_fn"] = eval_fn
    session["baseline_score"] = nil
    session["best_score"] = nil
    session["best_config"] = nil
    session["program"] = ""
    session["journal"] = []
    session["iteration"] = 0
    session["improvements"] = 0
    session["total_experiments"] = 0
    session["budget_steps"] = 50
    session["mutation_strategies"] = []
    session["secondary_metrics"] = []
    session["max_revert_streak"] = 10
    session["verbose"] = true
    return session

# ============================================================================
# Program directive (guides what the agent explores)
# ============================================================================

proc set_program(session, program_text):
    # program_text: natural language instructions for what to explore
    # e.g. "Explore learning rate between 0.0001 and 0.01"
    # e.g. "Try different activation functions: relu, gelu, silu"
    # e.g. "Optimize batch size for throughput"
    session["program"] = program_text

proc set_budget(session, steps):
    # Fixed compute budget per experiment (in training steps)
    session["budget_steps"] = steps

proc set_verbose(session, v):
    session["verbose"] = v

# ============================================================================
# Mutation strategies
# ============================================================================

# A mutation strategy is: proc(config, iteration, journal) -> new_config
# It proposes a change to try. Multiple strategies can be registered
# and the system cycles through them.

proc add_strategy(session, name, mutate_fn):
    let entry = {}
    entry["name"] = name
    entry["fn"] = mutate_fn
    push(session["mutation_strategies"], entry)

# Built-in: scale a numeric parameter by a random factor
proc scale_param_strategy(param_name, min_scale, max_scale):
    let result = {}
    result["param"] = param_name
    result["min"] = min_scale
    result["max"] = max_scale
    return result

proc apply_scale(config, spec, rng_state):
    let param = spec["param"]
    if dict_has(config, param):
        let old_val = config[param]
        # Simple LCG random in range [min_scale, max_scale]
        rng_state[0] = (rng_state[0] * 1664525 + 1013904223) & 4294967295
        let t = (rng_state[0] & 65535) / 65536
        let scale = spec["min"] + t * (spec["max"] - spec["min"])
        config[param] = old_val * scale
    return config

# Built-in: try values from a discrete set
proc choice_param_strategy(param_name, choices):
    let result = {}
    result["param"] = param_name
    result["choices"] = choices
    return result

proc apply_choice(config, spec, rng_state):
    let param = spec["param"]
    let choices = spec["choices"]
    rng_state[0] = (rng_state[0] * 1664525 + 1013904223) & 4294967295
    let idx = rng_state[0] % len(choices)
    if idx < 0:
        idx = 0 - idx
    config[param] = choices[idx]
    return config

# Built-in: perturb a numeric parameter by adding noise
proc perturb_param_strategy(param_name, magnitude):
    let result = {}
    result["param"] = param_name
    result["magnitude"] = magnitude
    return result

proc apply_perturb(config, spec, rng_state):
    let param = spec["param"]
    if dict_has(config, param):
        let old_val = config[param]
        rng_state[0] = (rng_state[0] * 1664525 + 1013904223) & 4294967295
        let t = ((rng_state[0] & 65535) / 65536 - 0.5) * 2
        config[param] = old_val + t * spec["magnitude"]
    return config

# ============================================================================
# Config snapshot/restore (git-like revert)
# ============================================================================

proc snapshot_config(config):
    # Deep copy a config dict
    let snap = {}
    let keys = dict_keys(config)
    for i in range(len(keys)):
        snap[keys[i]] = config[keys[i]]
    return snap

proc restore_config(config, snapshot):
    # Restore config from snapshot
    let keys = dict_keys(snapshot)
    for i in range(len(keys)):
        config[keys[i]] = snapshot[keys[i]]

# ============================================================================
# Journal (experiment log)
# ============================================================================

proc journal_entry(iteration, strategy_name, changes, score, baseline, accepted):
    let entry = {}
    entry["iteration"] = iteration
    entry["strategy"] = strategy_name
    entry["changes"] = changes
    entry["score"] = score
    entry["baseline"] = baseline
    entry["accepted"] = accepted
    entry["improvement"] = 0
    if baseline != nil and score != nil:
        entry["improvement"] = baseline - score
    return entry

proc format_journal_entry(entry):
    let status = "REJECT"
    if entry["accepted"]:
        status = "ACCEPT"
    let result = "  [" + str(entry["iteration"]) + "] " + status
    result = result + " | " + entry["strategy"]
    result = result + " | score=" + str(entry["score"])
    if entry["baseline"] != nil:
        result = result + " (baseline=" + str(entry["baseline"]) + " delta=" + str(entry["improvement"]) + ")"
    return result

# ============================================================================
# Secondary metrics (Goodhart's Law protection)
# ============================================================================

proc add_secondary_metric(session, name, metric_fn, min_threshold):
    # metric_fn: proc(config) -> number
    # min_threshold: reject if metric falls below this
    let metric = {}
    metric["name"] = name
    metric["fn"] = metric_fn
    metric["threshold"] = min_threshold
    push(session["secondary_metrics"], metric)

proc check_secondary_metrics(session, config):
    # Returns true if all secondary metrics pass
    for i in range(len(session["secondary_metrics"])):
        let m = session["secondary_metrics"][i]
        let val = m["fn"](config)
        if val < m["threshold"]:
            return false
    return true

# ============================================================================
# Core ratchet loop
# ============================================================================

proc run_one(session):
    # Run a single experiment iteration
    let config = session["config"]
    let strategies = session["mutation_strategies"]

    if len(strategies) == 0:
        return nil

    # Select strategy (round-robin through registered strategies)
    let strat_idx = session["iteration"] % len(strategies)
    let strategy = strategies[strat_idx]
    let strat_name = strategy["name"]

    # Snapshot current config (for revert)
    let snap = snapshot_config(config)

    # Apply mutation
    let mutate_fn = strategy["fn"]
    mutate_fn(config)

    # Record what changed
    let changes = {}
    let keys = dict_keys(config)
    for i in range(len(keys)):
        if config[keys[i]] != snap[keys[i]]:
            changes[keys[i]] = config[keys[i]]

    # Train for budget
    let train_result = session["train_fn"](config)

    # Evaluate
    let score = session["eval_fn"](config)

    # Check secondary metrics
    let secondary_ok = check_secondary_metrics(session, config)

    # Decide: accept or reject
    let baseline = session["best_score"]
    let accepted = false

    if baseline == nil:
        # First experiment — always accept
        accepted = true
        session["baseline_score"] = score
    if baseline != nil and score < baseline and secondary_ok:
        accepted = true

    session["iteration"] = session["iteration"] + 1
    session["total_experiments"] = session["total_experiments"] + 1

    if accepted:
        # KEEP: update best score and config
        session["best_score"] = score
        session["best_config"] = snapshot_config(config)
        session["improvements"] = session["improvements"] + 1
    if not accepted:
        # DISCARD: revert config
        restore_config(config, snap)

    # Log to journal
    let entry = journal_entry(session["iteration"], strat_name, changes, score, baseline, accepted)
    push(session["journal"], entry)

    if session["verbose"]:
        print format_journal_entry(entry)

    return entry

proc run(session, num_experiments):
    # Run the full ratchet loop for N experiments
    if session["verbose"]:
        print "=== AutoResearch: " + str(num_experiments) + " experiments ==="
        if len(session["program"]) > 0:
            print "Program: " + session["program"]

    # Establish baseline if not set
    if session["best_score"] == nil:
        let initial = session["eval_fn"](session["config"])
        session["baseline_score"] = initial
        session["best_score"] = initial
        session["best_config"] = snapshot_config(session["config"])
        if session["verbose"]:
            print "  Baseline score: " + str(initial)

    let revert_streak = 0

    for i in range(num_experiments):
        let entry = run_one(session)
        if entry != nil:
            if entry["accepted"]:
                revert_streak = 0
            if not entry["accepted"]:
                revert_streak = revert_streak + 1

        # Safety: if too many consecutive failures, reset to best known
        if revert_streak >= session["max_revert_streak"]:
            if session["best_config"] != nil:
                restore_config(session["config"], session["best_config"])
            revert_streak = 0
            if session["verbose"]:
                print "  [RESET] " + str(session["max_revert_streak"]) + " consecutive failures, reverting to best config"

    if session["verbose"]:
        print "=== AutoResearch Complete ==="

# ============================================================================
# Analysis and reporting
# ============================================================================

proc summary(session):
    let result = "AutoResearch Summary:" + chr(10)
    result = result + "  Total experiments: " + str(session["total_experiments"]) + chr(10)
    result = result + "  Improvements found: " + str(session["improvements"]) + chr(10)
    let rate = 0
    if session["total_experiments"] > 0:
        rate = (session["improvements"] * 100) / session["total_experiments"]
    result = result + "  Success rate: " + str(rate) + "%" + chr(10)
    result = result + "  Baseline score: " + str(session["baseline_score"]) + chr(10)
    result = result + "  Best score: " + str(session["best_score"]) + chr(10)
    if session["baseline_score"] != nil and session["best_score"] != nil:
        let improvement = session["baseline_score"] - session["best_score"]
        let pct = 0
        if session["baseline_score"] != 0:
            pct = (improvement / session["baseline_score"]) * 100
        result = result + "  Total improvement: " + str(improvement) + " (" + str(pct) + "%)" + chr(10)
    return result

proc journal_text(session):
    let result = "AutoResearch Journal (" + str(len(session["journal"])) + " entries):" + chr(10)
    for i in range(len(session["journal"])):
        result = result + format_journal_entry(session["journal"][i]) + chr(10)
    return result

proc accepted_changes(session):
    # Return list of only accepted experiments
    let results = []
    for i in range(len(session["journal"])):
        if session["journal"][i]["accepted"]:
            push(results, session["journal"][i])
    return results

proc rejected_changes(session):
    # Return list of only rejected experiments
    let results = []
    for i in range(len(session["journal"])):
        if not session["journal"][i]["accepted"]:
            push(results, session["journal"][i])
    return results

proc best_experiments(session, top_k):
    # Return top K experiments by improvement
    let accepted = accepted_changes(session)
    # Simple selection sort by improvement (descending)
    for i in range(len(accepted)):
        let best_idx = i
        for j in range(len(accepted) - i - 1):
            if accepted[i + j + 1]["improvement"] > accepted[best_idx]["improvement"]:
                best_idx = i + j + 1
        if best_idx != i:
            let tmp = accepted[i]
            accepted[i] = accepted[best_idx]
            accepted[best_idx] = tmp
    if len(accepted) > top_k:
        let trimmed = []
        for i in range(top_k):
            push(trimmed, accepted[i])
        return trimmed
    return accepted

# ============================================================================
# Built-in mutation strategy constructors
# ============================================================================

# Create a strategy that scales a numeric param randomly
proc make_scale_strategy(param_name, min_scale, max_scale, rng_seed):
    let state = [rng_seed]
    let spec = scale_param_strategy(param_name, min_scale, max_scale)
    proc mutate(config):
        apply_scale(config, spec, state)
    return mutate

# Create a strategy that picks from a set of discrete choices
proc make_choice_strategy(param_name, choices, rng_seed):
    let state = [rng_seed]
    let spec = choice_param_strategy(param_name, choices)
    proc mutate(config):
        apply_choice(config, spec, state)
    return mutate

# Create a strategy that perturbs a numeric param with noise
proc make_perturb_strategy(param_name, magnitude, rng_seed):
    let state = [rng_seed]
    let spec = perturb_param_strategy(param_name, magnitude)
    proc mutate(config):
        apply_perturb(config, spec, state)
    return mutate

# ============================================================================
# Convenience: quick setup for common LLM hyperparameter search
# ============================================================================

proc llm_default_strategies(session, rng_seed):
    # Add common LLM hyperparameter mutation strategies
    let s = rng_seed

    # Learning rate: scale between 0.5x and 2x
    add_strategy(session, "lr_scale", make_scale_strategy("learning_rate", 0.5, 2.0, s))
    s = s + 7

    # Batch size: try common sizes
    add_strategy(session, "batch_size", make_choice_strategy("batch_size", [8, 16, 32, 64, 128], s))
    s = s + 13

    # Weight decay: perturb
    add_strategy(session, "weight_decay", make_perturb_strategy("weight_decay", 0.01, s))
    s = s + 17

    # Warmup steps: scale
    add_strategy(session, "warmup", make_scale_strategy("warmup_steps", 0.5, 3.0, s))
    s = s + 23

    # Dropout: perturb
    add_strategy(session, "dropout", make_perturb_strategy("dropout", 0.05, s))

proc architecture_strategies(session, rng_seed):
    # Add architecture-level mutation strategies
    let s = rng_seed

    add_strategy(session, "d_model", make_choice_strategy("d_model", [32, 48, 64, 96, 128], s))
    s = s + 7

    add_strategy(session, "n_heads", make_choice_strategy("n_heads", [1, 2, 4, 8], s))
    s = s + 11

    add_strategy(session, "d_ff_ratio", make_choice_strategy("d_ff_ratio", [2, 3, 4], s))
    s = s + 13

    add_strategy(session, "activation", make_choice_strategy("activation", ["relu", "gelu", "silu"], s))

# ============================================================================
# Multi-agent support (async collaboration via shared journal)
# ============================================================================

proc export_journal(session):
    # Export journal as list of dicts for sharing between agents
    let entries = []
    for i in range(len(session["journal"])):
        let e = session["journal"][i]
        let exported = {}
        exported["iteration"] = e["iteration"]
        exported["strategy"] = e["strategy"]
        exported["score"] = e["score"]
        exported["accepted"] = e["accepted"]
        exported["improvement"] = e["improvement"]
        exported["changes"] = e["changes"]
        push(entries, exported)
    return entries

proc import_journal(session, entries):
    # Import journal entries from another agent's session
    for i in range(len(entries)):
        push(session["journal"], entries[i])
        # If any imported entry beats our best, adopt its config
        if entries[i]["accepted"] and entries[i]["score"] != nil:
            if session["best_score"] == nil:
                session["best_score"] = entries[i]["score"]
            if entries[i]["score"] < session["best_score"]:
                session["best_score"] = entries[i]["score"]
                # Apply the changes from the imported experiment
                let changes = entries[i]["changes"]
                let ckeys = dict_keys(changes)
                for j in range(len(ckeys)):
                    session["config"][ckeys[j]] = changes[ckeys[j]]
                session["best_config"] = snapshot_config(session["config"])

proc merge_sessions(session_a, session_b):
    # Merge results from two sessions, keeping the best config
    import_journal(session_a, export_journal(session_b))
    return session_a

# ============================================================================
# Stats
# ============================================================================

proc stats(session):
    let s = {}
    s["total"] = session["total_experiments"]
    s["improvements"] = session["improvements"]
    s["baseline"] = session["baseline_score"]
    s["best"] = session["best_score"]
    s["journal_size"] = len(session["journal"])
    s["strategies"] = len(session["mutation_strategies"])
    if session["total_experiments"] > 0:
        s["success_rate"] = (session["improvements"] * 100) / session["total_experiments"]
    else:
        s["success_rate"] = 0
    return s
