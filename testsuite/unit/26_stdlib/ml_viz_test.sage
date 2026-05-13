gc_disable()
# EXPECT: true
# EXPECT: true

import ml.viz
import io

let losses = [5.0, 4.5, 4.0, 3.5, 3.0]
let path = viz.loss_curve(losses, "Test Loss", "/tmp/sage_test_loss.svg")
print path != nil

# Check file was created
let content = io.readfile("/tmp/sage_test_loss.svg")
print content != nil
