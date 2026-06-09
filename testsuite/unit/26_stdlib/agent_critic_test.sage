gc_disable()
# EXPECT: true
# EXPECT: false
# EXPECT: true
# EXPECT: true

import agent.critic

let v = critic.create_validator()
critic.add_rule(v, "not_empty", critic.rule_not_empty)

# Valid output
let r1 = critic.validate(v, "hello world", {})
print r1["valid"]

# Invalid output (empty)
let r2 = critic.validate(v, "", {})
print r2["valid"]

# Length rule
let length_check = critic.make_length_rule(3, 100)
let r3 = length_check("hello", {})
print r3["valid"]

# Contains rule
let contains_check = critic.make_contains_rule(["hello"])
let r4 = contains_check("say hello world", {})
print r4["valid"]
