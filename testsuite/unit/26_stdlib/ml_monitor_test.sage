gc_disable()
# EXPECT: 3
# EXPECT: true
# EXPECT: true

import ml.monitor

let mon = monitor.create()
monitor.log_step(mon, 5.0, 0.001, 0.5, 100)
monitor.log_step(mon, 4.5, 0.001, 0.4, 100)
monitor.log_step(mon, 4.0, 0.001, 0.3, 100)
print mon["step"]
print mon["best_loss"] < 5
let report = monitor.summary(mon)
print len(report) > 0
