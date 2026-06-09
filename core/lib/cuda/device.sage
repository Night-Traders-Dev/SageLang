# CUDA device management abstractions
# Provides device enumeration, selection, properties, and context management

# Device type constants
let CPU = 0
let CUDA = 1

# Compute capability constants
let SM_30 = 30
let SM_35 = 35
let SM_50 = 50
let SM_52 = 52
let SM_60 = 60
let SM_61 = 61
let SM_70 = 70
let SM_75 = 75
let SM_80 = 80
let SM_86 = 86
let SM_89 = 89
let SM_90 = 90

# Architecture names
proc arch_name(sm):
    if sm >= 90:
        return "Hopper"
    if sm >= 89:
        return "Ada Lovelace"
    if sm >= 80:
        return "Ampere"
    if sm >= 75:
        return "Turing"
    if sm >= 70:
        return "Volta"
    if sm >= 60:
        return "Pascal"
    if sm >= 50:
        return "Maxwell"
    if sm >= 30:
        return "Kepler"
    return "Unknown"

# Create a device descriptor
proc create_device(device_id, name, compute_capability, total_memory):
    let dev = {}
    dev["id"] = device_id
    dev["name"] = name
    dev["type"] = 1
    dev["compute_capability"] = compute_capability
    dev["sm_major"] = (compute_capability / 10) | 0
    dev["sm_minor"] = compute_capability - ((compute_capability / 10) | 0) * 10
    dev["arch"] = arch_name(compute_capability)
    dev["total_memory"] = total_memory
    dev["total_memory_mb"] = (total_memory / 1048576) | 0
    dev["total_memory_gb"] = total_memory / 1073741824
    return dev

# Create a CPU device
proc cpu_device():
    let dev = {}
    dev["id"] = -1
    dev["name"] = "CPU"
    dev["type"] = 0
    dev["compute_capability"] = 0
    dev["arch"] = "CPU"
    dev["total_memory"] = 0
    return dev

# Create device properties (simulated for library use)
proc device_properties(dev):
    let props = {}
    props["name"] = dev["name"]
    props["compute_capability"] = dev["compute_capability"]
    props["total_memory"] = dev["total_memory"]
    # Typical values based on compute capability
    let sm = dev["compute_capability"]
    props["max_threads_per_block"] = 1024
    props["max_block_dim"] = [1024, 1024, 64]
    props["max_grid_dim"] = [2147483647, 65535, 65535]
    props["warp_size"] = 32
    if sm >= 80:
        props["max_shared_memory"] = 163840
        props["sm_count"] = 108
    if sm >= 70 and sm < 80:
        props["max_shared_memory"] = 98304
        props["sm_count"] = 80
    if sm >= 60 and sm < 70:
        props["max_shared_memory"] = 49152
        props["sm_count"] = 56
    if sm < 60:
        props["max_shared_memory"] = 49152
        props["sm_count"] = 32
    props["clock_rate_mhz"] = 1500
    props["memory_bus_width"] = 256
    props["l2_cache_size"] = 6291456
    props["supports_unified_memory"] = sm >= 60
    props["supports_cooperative_groups"] = sm >= 60
    props["supports_tensor_cores"] = sm >= 70
    props["supports_fp16"] = sm >= 60
    props["supports_bf16"] = sm >= 80
    props["supports_tf32"] = sm >= 80
    props["supports_fp8"] = sm >= 89
    return props

# Check if a device supports a feature
proc supports(dev, feature):
    let sm = dev["compute_capability"]
    if feature == "tensor_cores":
        return sm >= 70
    if feature == "fp16":
        return sm >= 60
    if feature == "bf16":
        return sm >= 80
    if feature == "tf32":
        return sm >= 80
    if feature == "fp8":
        return sm >= 89
    if feature == "unified_memory":
        return sm >= 60
    if feature == "cooperative_groups":
        return sm >= 60
    if feature == "dynamic_parallelism":
        return sm >= 35
    if feature == "ray_tracing":
        return sm >= 75
    return false

# Calculate optimal block size for a kernel
proc optimal_block_size(dev, shared_mem_per_block):
    let props = device_properties(dev)
    let max_threads = props["max_threads_per_block"]
    let shared_limit = props["max_shared_memory"]
    if shared_mem_per_block > 0 and shared_mem_per_block > shared_limit:
        return 128
    if max_threads >= 1024:
        return 256
    return 128

# Calculate grid size for a given problem size and block size
proc grid_size(problem_size, block_size):
    return ((problem_size + block_size - 1) / block_size) | 0

# Create a launch configuration
proc launch_config(grid, block):
    let cfg = {}
    if type(grid) == "number":
        cfg["grid"] = [grid, 1, 1]
    else:
        cfg["grid"] = grid
    if type(block) == "number":
        cfg["block"] = [block, 1, 1]
    else:
        cfg["block"] = block
    cfg["shared_mem"] = 0
    cfg["stream"] = nil
    return cfg

proc launch_config_1d(n, block_size):
    let gs = grid_size(n, block_size)
    return launch_config(gs, block_size)

proc launch_config_2d(width, height, block_x, block_y):
    let gx = grid_size(width, block_x)
    let gy = grid_size(height, block_y)
    return launch_config([gx, gy, 1], [block_x, block_y, 1])

# Memory info
proc memory_info(dev):
    let info = {}
    info["total"] = dev["total_memory"]
    info["total_mb"] = (dev["total_memory"] / 1048576) | 0
    return info

# Format device info string
proc device_info(dev):
    return dev["name"] + " (SM " + str(dev["sm_major"]) + "." + str(dev["sm_minor"]) + ", " + dev["arch"] + ", " + str(dev["total_memory_mb"]) + " MB)"
