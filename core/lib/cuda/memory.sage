# CUDA memory management abstractions
# Provides typed GPU memory allocation, transfer simulation, and pool management

# Memory type constants
let MEM_DEVICE = 1
let MEM_HOST = 2
let MEM_UNIFIED = 3
let MEM_PINNED = 4

# Data type sizes in bytes
let DTYPE_FLOAT32 = 4
let DTYPE_FLOAT64 = 8
let DTYPE_INT32 = 4
let DTYPE_INT64 = 8
let DTYPE_FLOAT16 = 2
let DTYPE_BFLOAT16 = 2
let DTYPE_INT8 = 1
let DTYPE_UINT8 = 1

proc dtype_size(dtype):
    if dtype == "float32" or dtype == "f32":
        return 4
    if dtype == "float64" or dtype == "f64":
        return 8
    if dtype == "int32" or dtype == "i32":
        return 4
    if dtype == "int64" or dtype == "i64":
        return 8
    if dtype == "float16" or dtype == "f16":
        return 2
    if dtype == "bfloat16" or dtype == "bf16":
        return 2
    if dtype == "int8" or dtype == "i8":
        return 1
    if dtype == "uint8" or dtype == "u8":
        return 1
    return 4

# Create a GPU memory allocation descriptor
proc alloc(size_bytes, mem_type):
    let a = {}
    a["size"] = size_bytes
    a["type"] = mem_type
    a["allocated"] = true
    a["data"] = nil
    a["device_id"] = 0
    return a

# Create a typed allocation for n elements of a given dtype
proc alloc_typed(count, dtype):
    let elem_size = dtype_size(dtype)
    let a = alloc(count * elem_size, 1)
    a["count"] = count
    a["dtype"] = dtype
    a["elem_size"] = elem_size
    return a

# Free a GPU allocation
proc free(allocation):
    allocation["allocated"] = false
    allocation["data"] = nil
    return 0

# Simulate host-to-device copy
proc copy_h2d(host_data, device_alloc):
    let result = {}
    result["src"] = "host"
    result["dst"] = "device"
    result["size"] = len(host_data) * 4
    result["elements"] = len(host_data)
    result["data"] = host_data
    device_alloc["data"] = host_data
    return result

# Simulate device-to-host copy
proc copy_d2h(device_alloc):
    let result = {}
    result["src"] = "device"
    result["dst"] = "host"
    result["data"] = device_alloc["data"]
    return result

# Simulate device-to-device copy
proc copy_d2d(src_alloc, dst_alloc):
    dst_alloc["data"] = src_alloc["data"]
    let result = {}
    result["src"] = "device"
    result["dst"] = "device"
    result["size"] = src_alloc["size"]
    return result

# Set memory to zero
proc memset_zero(allocation):
    let count = allocation["count"]
    let data = []
    for i in range(count):
        push(data, 0)
    allocation["data"] = data

# ============================================================================
# Memory Pool
# ============================================================================

proc create_pool(total_size):
    let pool = {}
    pool["total_size"] = total_size
    pool["used"] = 0
    pool["allocations"] = []
    pool["peak_usage"] = 0
    return pool

proc pool_alloc(pool, size):
    if pool["used"] + size > pool["total_size"]:
        return nil
    let a = alloc(size, 1)
    a["pool_offset"] = pool["used"]
    pool["used"] = pool["used"] + size
    if pool["used"] > pool["peak_usage"]:
        pool["peak_usage"] = pool["used"]
    push(pool["allocations"], a)
    return a

proc pool_reset(pool):
    pool["used"] = 0
    pool["allocations"] = []

proc pool_stats(pool):
    let stats = {}
    stats["total"] = pool["total_size"]
    stats["used"] = pool["used"]
    stats["free"] = pool["total_size"] - pool["used"]
    stats["peak"] = pool["peak_usage"]
    stats["num_allocations"] = len(pool["allocations"])
    stats["utilization"] = pool["used"] / pool["total_size"]
    return stats

# ============================================================================
# Tensor memory helpers
# ============================================================================

# Calculate memory needed for a tensor
proc tensor_bytes(shape, dtype):
    let sz = 1
    for i in range(len(shape)):
        sz = sz * shape[i]
    return sz * dtype_size(dtype)

# Allocate memory for a tensor
proc alloc_tensor(shape, dtype):
    let sz = 1
    for i in range(len(shape)):
        sz = sz * shape[i]
    let a = alloc_typed(sz, dtype)
    a["shape"] = shape
    return a

# Calculate memory bandwidth estimate (bytes/second)
proc bandwidth_estimate(bytes_transferred, time_seconds):
    if time_seconds <= 0:
        return 0
    return bytes_transferred / time_seconds

# Format bytes as human-readable string
proc format_bytes(bytes_val):
    if bytes_val >= 1073741824:
        return str((bytes_val / 1073741824 * 100) | 0) + " GB"
    if bytes_val >= 1048576:
        return str((bytes_val / 1048576) | 0) + " MB"
    if bytes_val >= 1024:
        return str((bytes_val / 1024) | 0) + " KB"
    return str(bytes_val) + " B"
