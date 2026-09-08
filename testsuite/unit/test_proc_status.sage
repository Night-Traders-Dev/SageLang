# EXPECT: Idle
# EXPECT: Ready
# EXPECT: Running
# EXPECT: Blocked
# EXPECT: Zombie
# EXPECT: Terminated
# EXPECT: Unknown
import os.kernel.kmain as kmain

print kmain.proc_status_name(kmain.ProcStatus["Idle"])
print kmain.proc_status_name(kmain.ProcStatus["Ready"])
print kmain.proc_status_name(kmain.ProcStatus["Running"])
print kmain.proc_status_name(kmain.ProcStatus["Blocked"])
print kmain.proc_status_name(kmain.ProcStatus["Zombie"])
print kmain.proc_status_name(kmain.ProcStatus["Terminated"])
print kmain.proc_status_name(99)
