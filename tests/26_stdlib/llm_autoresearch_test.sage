gc_disable()
# EXPECT: session_created
# EXPECT: strategy_added
# EXPECT: baseline_set
# EXPECT: experiment_ran
# EXPECT: journal_has_entry
# EXPECT: summary_works
# EXPECT: PASS

import llm.autoresearch

# Dummy train function: returns a loss value
proc dummy_train(config):
    return config["lr"] * 10

# Dummy eval function: returns a score (lower is better)
let _eval_counter = [0]
proc dummy_eval(config):
    _eval_counter[0] = _eval_counter[0] + 1
    return 5.0 - _eval_counter[0] * 0.1

# Create a session with config, train_fn, eval_fn
let config = {}
config["lr"] = 0.01
config["batch_size"] = 32
let session = autoresearch.create(config, dummy_train, dummy_eval)
if session != nil:
    print "session_created"

# Add a mutation strategy
proc my_mutate(config):
    config["lr"] = config["lr"] * 1.1

autoresearch.add_strategy(session, "lr_bump", my_mutate)
if len(session["mutation_strategies"]) == 1:
    print "strategy_added"

# Set verbose to false so run doesn't print extra output
autoresearch.set_verbose(session, false)

# Establish baseline by running with 0 experiments
autoresearch.run(session, 0)
if session["baseline_score"] != nil:
    print "baseline_set"

# Run 1 experiment
autoresearch.run(session, 1)
if session["total_experiments"] == 1:
    print "experiment_ran"

# Check journal has an entry
if len(session["journal"]) > 0:
    print "journal_has_entry"

# Check summary works
let s = autoresearch.summary(session)
if len(s) > 0:
    print "summary_works"

print "PASS"
