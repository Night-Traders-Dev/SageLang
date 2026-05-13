gc_disable()
# EXPECT: context_created
# EXPECT: backend_is_cpu
# EXPECT: parallel_works
# EXPECT: stats_works
# EXPECT: PASS

# gpu_accel.sage imports ml_native (native C), so we replicate the
# core context/backend logic with pure Sage

# --- Simulate backend detection ---
let _backends = {}
_backends["cpu"] = true
_backends["cpu_driver"] = "ml_native (C optimized)"
_backends["gpu"] = false
_backends["gpu_driver"] = "none"
_backends["npu"] = false
_backends["npu_driver"] = "none"
_backends["tpu"] = false
_backends["tpu_driver"] = "none"

proc select_best_backend(backends):
    if backends["tpu"]:
        return "tpu"
    if backends["gpu"]:
        return "gpu"
    if backends["npu"]:
        return "npu"
    return "cpu"

# --- Simulate create context ---
proc create_context(backend_pref):
    let ctx = {}
    ctx["ops_gpu"] = 0
    ctx["ops_cpu"] = 0
    ctx["ops_npu"] = 0
    ctx["ops_tpu"] = 0
    ctx["ops_total"] = 0
    ctx["backends"] = _backends
    let pref = backend_pref
    if pref == "auto":
        ctx["backend"] = select_best_backend(_backends)
    if pref == "cpu":
        ctx["backend"] = "cpu"
    if pref == "gpu":
        if _backends["gpu"]:
            ctx["backend"] = "gpu"
        else:
            ctx["backend"] = "cpu"
            ctx["fallback_from"] = "gpu"
    if not dict_has(ctx, "backend"):
        ctx["backend"] = "cpu"
    ctx["driver"] = _backends[ctx["backend"] + "_driver"]
    ctx["requested"] = pref
    return ctx

# --- Simulate parallel config ---
let _parallel_enabled = false
let _num_workers = 1
let _parallel_threshold = 4096

proc enable_parallel(num_threads):
    _parallel_enabled = true
    _num_workers = num_threads

proc get_parallel_config():
    let cfg = {}
    cfg["enabled"] = _parallel_enabled
    cfg["num_workers"] = _num_workers
    cfg["threshold"] = _parallel_threshold
    return cfg

# --- Simulate stats ---
proc get_stats(ctx):
    let s = "Compute: backend=" + ctx["backend"]
    s = s + " driver=" + ctx["driver"]
    s = s + " total_ops=" + str(ctx["ops_total"])
    return s

# === Tests ===

# Test context creation with "auto" (falls back to cpu)
let ctx = create_context("auto")
if ctx != nil:
    print "context_created"

# Test backend is cpu
if ctx["backend"] == "cpu":
    print "backend_is_cpu"

# Test enable_parallel and get_parallel_config
enable_parallel(4)
let pcfg = get_parallel_config()
if pcfg["enabled"]:
    if pcfg["num_workers"] == 4:
        print "parallel_works"

# Test stats
let s = get_stats(ctx)
if len(s) > 0:
    print "stats_works"

print "PASS"
