gc_disable()
# EXPECT: Ampere
# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: 4
# EXPECT: 256

import cuda.device

let dev = device.create_device(0, "RTX 3090", 86, 25769803776)
print dev["arch"]
print device.supports(dev, "tensor_cores")
print device.supports(dev, "bf16")
print device.supports(dev, "fp8")

let cfg = device.launch_config_1d(1024, 256)
print cfg["grid"][0]
print cfg["block"][0]
