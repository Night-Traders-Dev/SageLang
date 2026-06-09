# CUDA kernel launch abstractions
# Provides kernel definition, launch parameter computation, and occupancy analysis

# ============================================================================
# Kernel definition
# ============================================================================

# Define a compute kernel descriptor
proc define(name, block_size, shared_mem, registers_per_thread):
    let k = {}
    k["name"] = name
    k["block_size"] = block_size
    k["shared_mem"] = shared_mem
    k["registers_per_thread"] = registers_per_thread
    k["launch_count"] = 0
    return k

# ============================================================================
# Launch parameter computation
# ============================================================================

# Compute 1D launch parameters
proc launch_1d(kernel, n):
    let cfg = {}
    cfg["kernel"] = kernel["name"]
    cfg["grid"] = [((n + kernel["block_size"] - 1) / kernel["block_size"]) | 0, 1, 1]
    cfg["block"] = [kernel["block_size"], 1, 1]
    cfg["shared_mem"] = kernel["shared_mem"]
    cfg["total_threads"] = cfg["grid"][0] * kernel["block_size"]
    cfg["problem_size"] = n
    kernel["launch_count"] = kernel["launch_count"] + 1
    return cfg

# Compute 2D launch parameters
proc launch_2d(kernel, width, height, bx, by):
    let cfg = {}
    cfg["kernel"] = kernel["name"]
    cfg["grid"] = [((width + bx - 1) / bx) | 0, ((height + by - 1) / by) | 0, 1]
    cfg["block"] = [bx, by, 1]
    cfg["shared_mem"] = kernel["shared_mem"]
    cfg["total_threads"] = cfg["grid"][0] * cfg["grid"][1] * bx * by
    cfg["problem_size"] = width * height
    kernel["launch_count"] = kernel["launch_count"] + 1
    return cfg

# Compute 3D launch parameters
proc launch_3d(kernel, x, y, z, bx, by, bz):
    let cfg = {}
    cfg["kernel"] = kernel["name"]
    cfg["grid"] = [((x + bx - 1) / bx) | 0, ((y + by - 1) / by) | 0, ((z + bz - 1) / bz) | 0]
    cfg["block"] = [bx, by, bz]
    cfg["shared_mem"] = kernel["shared_mem"]
    cfg["total_threads"] = cfg["grid"][0] * cfg["grid"][1] * cfg["grid"][2] * bx * by * bz
    kernel["launch_count"] = kernel["launch_count"] + 1
    return cfg

# ============================================================================
# Occupancy analysis
# ============================================================================

# Estimate theoretical occupancy
proc occupancy(kernel, dev_props):
    let block_size = kernel["block_size"]
    let regs = kernel["registers_per_thread"]
    let shared = kernel["shared_mem"]
    let warp_size = dev_props["warp_size"]
    let max_threads = dev_props["max_threads_per_block"]
    let max_shared = dev_props["max_shared_memory"]
    let sm_count = dev_props["sm_count"]

    let result = {}
    result["block_size"] = block_size
    result["warps_per_block"] = ((block_size + warp_size - 1) / warp_size) | 0

    # Thread limit
    let max_blocks_by_threads = (max_threads / block_size) | 0
    if max_blocks_by_threads > 32:
        max_blocks_by_threads = 32

    # Shared memory limit
    let max_blocks_by_shared = 32
    if shared > 0:
        max_blocks_by_shared = (max_shared / shared) | 0

    # Register limit (assume 65536 registers per SM)
    let max_blocks_by_regs = 32
    if regs > 0:
        let regs_per_block = regs * block_size
        if regs_per_block > 0:
            max_blocks_by_regs = (65536 / regs_per_block) | 0

    # Take minimum
    let active_blocks = max_blocks_by_threads
    if max_blocks_by_shared < active_blocks:
        active_blocks = max_blocks_by_shared
    if max_blocks_by_regs < active_blocks:
        active_blocks = max_blocks_by_regs
    if active_blocks < 1:
        active_blocks = 1

    let active_warps = active_blocks * result["warps_per_block"]
    let max_warps = (max_threads / warp_size) | 0
    if max_warps < 1:
        max_warps = 1

    result["active_blocks_per_sm"] = active_blocks
    result["active_warps_per_sm"] = active_warps
    result["max_warps_per_sm"] = max_warps
    result["occupancy"] = active_warps / max_warps
    result["occupancy_pct"] = ((active_warps * 100) / max_warps) | 0
    result["limiting_factor"] = "threads"
    if max_blocks_by_shared < max_blocks_by_threads and max_blocks_by_shared < max_blocks_by_regs:
        result["limiting_factor"] = "shared_memory"
    if max_blocks_by_regs < max_blocks_by_threads and max_blocks_by_regs < max_blocks_by_shared:
        result["limiting_factor"] = "registers"
    return result

# ============================================================================
# Common kernel patterns
# ============================================================================

# Vector add kernel descriptor
proc vector_add_kernel(n):
    return define("vector_add", 256, 0, 8)

# Matrix multiply kernel descriptor
proc matmul_kernel(shared_tile_size):
    let shared = shared_tile_size * shared_tile_size * 4 * 2
    return define("matmul", shared_tile_size * shared_tile_size, shared, 16)

# Reduction kernel descriptor
proc reduction_kernel(block_size):
    return define("reduction", block_size, block_size * 4, 8)

# Scan (prefix sum) kernel descriptor
proc scan_kernel(block_size):
    return define("scan", block_size, block_size * 4 * 2, 10)

# Histogram kernel descriptor
proc histogram_kernel(num_bins):
    return define("histogram", 256, num_bins * 4, 6)

# Convolution kernel descriptor
proc conv2d_kernel(tile_size, filter_size):
    let shared = (tile_size + filter_size - 1) * (tile_size + filter_size - 1) * 4
    return define("conv2d", tile_size * tile_size, shared, 20)

# Format launch config as string
proc format_launch(cfg):
    let g = cfg["grid"]
    let b = cfg["block"]
    return cfg["kernel"] + "<<<[" + str(g[0]) + "," + str(g[1]) + "," + str(g[2]) + "], [" + str(b[0]) + "," + str(b[1]) + "," + str(b[2]) + "]>>>"
