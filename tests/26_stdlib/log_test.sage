gc_disable()
# EXPECT: INFO
# EXPECT: true
# EXPECT: true

import std.log

print log.level_name(2)

let logger = log.create("test", 2)
print logger["level"] == 2

# Verify handler infrastructure
log.add_handler(logger, log.console_handler)
print len(logger["handlers"]) == 1
