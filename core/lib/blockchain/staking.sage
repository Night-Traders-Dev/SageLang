# Staking Smart Contract for Orbit
# APR: 5%, Interval: 24h

# Input Context (from state):
#   state["sender"]: caller address
#   state["value"]: ORBIT sent with call
#   state["now"]: current timestamp
#   state["action"]: "stake", "claim", or "unstake"
#   state["duration"]: lock duration in seconds (for stake)

let sender = state["sender"]
let value = state["value"]
let now = state["now"]
let action = state["action"]

if not dict_has(state, "stakes"):
    state["stakes"] = {}
if not dict_has(state, "total_staked"):
    state["total_staked"] = 0

# Default interval: 24h
let interval = 86400
if dict_has(state, "test_interval") and type(state["test_interval"]) == "number":
    interval = state["test_interval"]

let results = []

if action == "stake":
    if value <= 0:
        print "Stake Error: amount must be > 0"
    else:
        let duration = 86400 * 7 # Default 7 days
        if dict_has(state, "duration") and type(state["duration"]) == "number":
            duration = state["duration"]

        let s = {}
        if dict_has(state["stakes"], sender):
            s = state["stakes"][sender]
            s["amount"] = s["amount"] + value
        else:
            s["amount"] = value
            s["lock_start"] = now
            s["lock_duration"] = duration
            s["last_claim"] = now
            state["stakes"][sender] = s

        state["total_staked"] = state["total_staked"] + value
        print "SUCCESS: Staked " + str(value) + " ORBIT for " + sender

if action == "claim":
    if not dict_has(state["stakes"], sender):
        print "Claim Error: no stake found"
    else:
        let s = state["stakes"][sender]
        
        # Ensure last_claim exists and is a number
        if not dict_has(s, "last_claim") or type(s["last_claim"]) != "number":
            s["last_claim"] = now
            
        let diff = now - s["last_claim"]

        if diff < interval:
            print "Claim Error: interval not met (" + str(diff) + " / " + str(interval) + ")"
        else:
            # Calculate intervals
            let intervals = 0
            let temp_diff = diff
            if type(interval) != "number" or interval <= 0:
                interval = 86400

            while temp_diff >= interval:
                intervals = intervals + 1
                temp_diff = temp_diff - interval

            # Reward = amount * 0.05 * (intervals / (365 * 86400 / interval))
            let amount = 0.0
            if dict_has(s, "amount") and type(s["amount"]) == "number":
                amount = s["amount"]

            let reward = amount * 0.05 * (intervals * interval / (365.0 * 86400.0))

            s["last_claim"] = s["last_claim"] + (intervals * interval)
            print "SUCCESS: Claimed " + str(reward) + " ORBIT for " + sender
            results = [{"to": sender, "amount": reward}]
if action == "unstake":
    if not dict_has(state["stakes"], sender):
        print "Unstake Error: no stake found"
    else:
        let s = state["stakes"][sender]
        let lock_start = 0
        let lock_duration = 0
        if dict_has(s, "lock_start") and type(s["lock_start"]) == "number":
            lock_start = s["lock_start"]
        if dict_has(s, "lock_duration") and type(s["lock_duration"]) == "number":
            lock_duration = s["lock_duration"]
            
        let lock_end = lock_start + lock_duration
        
        if now < lock_end:
            let remain = lock_end - now
            print "Unstake Error: tokens locked for " + str(remain) + " more seconds"
        else:
            let principal = 0.0
            if dict_has(s, "amount") and type(s["amount"]) == "number":
                principal = s["amount"]
            
            # Final claim logic
            if not dict_has(s, "last_claim") or type(s["last_claim"]) != "number":
                s["last_claim"] = now
                
            let diff = now - s["last_claim"]
            let reward = 0.0
            if diff >= 86400:
                let intervals = 0
                while diff >= 86400:
                    intervals = intervals + 1
                    diff = diff - 86400
                reward = principal * 0.05 * (intervals / 365.0)
                
            dict_delete(state["stakes"], sender)
            state["total_staked"] = state["total_staked"] - principal
            
            print "SUCCESS: Unstaked " + str(principal) + " ORBIT (+ " + str(reward) + " reward)"
            results = [{"to": sender, "amount": principal + reward}]

# Final expression returns the results
results
