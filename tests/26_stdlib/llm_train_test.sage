gc_disable()
# EXPECT: 0.0003
# EXPECT: cosine
# EXPECT: true
# EXPECT: 2

import llm.train

let cfg = train.create_train_config()
print cfg["learning_rate"]
print cfg["lr_schedule"]

# LR schedule
let lr = train.cosine_schedule(50, 1000, 100, 0.001, 0.0001)
print lr > 0

# Create LM examples
let tokens = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let examples = train.create_lm_examples(tokens, 4)
print len(examples)
