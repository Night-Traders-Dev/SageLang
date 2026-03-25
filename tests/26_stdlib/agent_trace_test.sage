gc_disable()
# EXPECT: 1
# EXPECT: true
# EXPECT: 1
# EXPECT: true

import agent.trace

let rec = trace.create_recorder()
trace.begin_trace(rec, "Write a function")
trace.record_thought(rec, "I need to write a proc")
trace.record_tool_call(rec, "write_file", "test.sage", "written")
trace.record_output(rec, "proc hello(): print 42")
trace.end_trace(rec, true)

print len(rec["traces"])

# SFT examples
let examples = trace.to_sft_examples(rec)
print len(examples) > 0

# Stats
let s = trace.stats(rec)
print s["successful"]
print s["success_rate"] == 1
