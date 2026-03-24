gc_disable()
# EXPECT: vector_add
# EXPECT: 4
# EXPECT: 256
# EXPECT: true

import cuda.kernel
import cuda.device

let k = kernel.vector_add_kernel(1024)
print k["name"]

let cfg = kernel.launch_1d(k, 1024)
print cfg["grid"][0]
print cfg["block"][0]

# Occupancy
let dev = device.create_device(0, "Test GPU", 80, 8589934592)
let props = device.device_properties(dev)
let occ = kernel.occupancy(k, props)
print occ["occupancy_pct"] > 0
