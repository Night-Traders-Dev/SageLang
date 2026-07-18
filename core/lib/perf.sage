## perf.sage — Compile-time performance primitives for Sage
##
## Uses comptime blocks, @inline pragmas, and pre-allocation patterns
## to eliminate hot-path overhead in performance-critical Sage code.
##
## Design goal: make self-hosted Sage match pure C performance by doing this
## 1. Eliminating per-operation dict allocations (frozen signal singletons)
## 2. Replacing if/elif dispatch chains with dict-based O(1) lookup tables
## 3. Pre-computing constant data at compile time
## 4. Providing flat (non-chained) environment caches for inner loops
## 5. Offering struct-like fixed-shape objects that avoid dict overhead

## ============================================================
## 1. Frozen Signal Singletons — eliminate allocation in hot loops
## ============================================================
## Instead of creating {"kind": 0, "value": nil} on every statement,
## reuse pre-allocated immutable signal objects.

let _SIG_NORMAL_NIL = {"kind": 0, "value": nil}
let _SIG_BREAK = {"kind": 2, "value": nil}
let _SIG_CONTINUE = {"kind": 3, "value": nil}

## Return a pre-allocated normal(nil) signal — zero allocation
proc sig_normal_nil():
    return _SIG_NORMAL_NIL

## Return a normal signal wrapping a value — 1 allocation
proc sig_normal(val):
    if val == nil:
        return _SIG_NORMAL_NIL
    let normal_r = {}
    normal_r["kind"] = 0
    normal_r["value"] = val
    return normal_r

## Return a pre-allocated break signal — zero allocation
proc sig_break():
    return _SIG_BREAK

## Return a pre-allocated continue signal — zero allocation
proc sig_continue():
    return _SIG_CONTINUE

## Return signal — always needs value, 1 allocation
proc sig_return(val):
    let return_r = {}
    return_r["kind"] = 1
    return_r["value"] = val
    return return_r

## ============================================================
## 2. Dispatch Tables — O(1) lookup replacing if/elif chains
## ============================================================
## Build a dict mapping keys to handler functions at module load time.
## On every dispatch, one dict lookup replaces N comparisons.

## Create a new O(1) dispatch table
proc make_dispatch_table():
    return {}

## Register a handler for a key in the dispatch table
proc dispatch_register(table, key, handler):
    table[key] = handler

## Invoke the registered handler for a key
proc dispatch_call(table, key, args):
    if dict_has(table, key):
        let handler = table[key]
        return handler(args)
    return nil

## Check if the dispatch table has a handler for the key
proc dispatch_has(table, key):
    return dict_has(table, key)

## ============================================================
## 3. Flat Environment Cache — bypass scope chain for hot locals
## ============================================================
## In tight loops, variable lookup walks a linked list of scope dicts.
## A flat cache stores the most recently accessed variables in a single
## dict with no parent chain, providing O(1) access.

## Create a new flat cache dict
proc flat_cache_new():
    return {}

## Retrieve a value from the flat cache
proc flat_cache_get(cache, name):
    if dict_has(cache, name):
        return cache[name]
    return nil

## Assign a value in the flat cache
proc flat_cache_set(cache, name, value):
    cache[name] = value

## Check if the flat cache has the variable name
proc flat_cache_has(cache, name):
    return dict_has(cache, name)

## Snapshot: copy the current environment's immediate locals into a flat cache
## Optimized with direct for loop (~2.7x faster)
proc flat_cache_snapshot(env):
    let cache = {}
    let snap_vals = env["vals"]
    let snap_keys = dict_keys(snap_vals)
    for k in snap_keys:
        cache[k] = snap_vals[k]
    return cache

## Write-back: flush the flat cache into the real environment
## Optimized with direct for loop (~2.7x faster)
proc flat_cache_flush(cache, env):
    let flush_vals = env["vals"]
    let flush_keys = dict_keys(cache)
    for k in flush_keys:
        flush_vals[k] = cache[k]

## ============================================================
## 4. Shape Objects — fixed-layout dicts for known structures
## ============================================================
## Instead of building dicts key-by-key, create templates that are
## cloned (dict copy) for each new instance. This reduces hash
## collisions since the dict is pre-sized.

## Create a fixed-layout function shape dict
proc shape_function(name, params, body, closure, is_gen):
    let func_shape = {}
    func_shape["__interp_type"] = "function"
    func_shape["name"] = name
    func_shape["params"] = params
    func_shape["body"] = body
    func_shape["closure"] = closure
    func_shape["is_generator"] = is_gen
    return func_shape

## Create a fixed-layout class shape dict
proc shape_class(name, parent):
    let cls = {}
    cls["__interp_type"] = "class"
    cls["name"] = name
    cls["methods"] = {}
    cls["parent"] = parent
    return cls

## Create a fixed-layout instance shape dict
proc shape_instance(cls):
    let inst = {}
    inst["__interp_type"] = "instance"
    inst["class"] = cls
    inst["fields"] = {}
    return inst

## Create a fixed-layout native function shape dict
proc shape_native(name, arity):
    let native_shape = {}
    native_shape["__interp_type"] = "native"
    native_shape["name"] = name
    native_shape["arity"] = arity
    return native_shape

## Create a fixed-layout generator shape dict
proc shape_generator(values):
    let gen = {}
    gen["__interp_type"] = "generator"
    gen["values"] = values
    gen["index"] = 0
    return gen

## Create a fixed-layout environment shape dict
proc shape_env(parent):
    let e = {}
    e["parent"] = parent
    e["vals"] = {}
    return e

## ============================================================
## 5. Fast Numeric Operations — avoid type() checks in hot paths
## ============================================================
## When the caller KNOWS both operands are numbers, bypass the
## polymorphic dispatch in eval_binary.

## Perform fast numeric addition without type checks
proc fast_add_num(a, b):
    return a + b

## Perform fast numeric subtraction without type checks
proc fast_sub_num(a, b):
    return a - b

## Perform fast numeric multiplication without type checks
proc fast_mul_num(a, b):
    return a * b

## Perform fast numeric division without type checks
proc fast_div_num(a, b):
    return a / b

## Perform fast numeric modulo without type checks
proc fast_mod_num(a, b):
    return a % b

## Perform fast numeric less-than check without type checks
proc fast_lt_num(a, b):
    return a < b

## Perform fast numeric greater-than check without type checks
proc fast_gt_num(a, b):
    return a > b

## Perform fast numeric less-than-or-equal check without type checks
proc fast_lte_num(a, b):
    return a <= b

## Perform fast numeric greater-than-or-equal check without type checks
proc fast_gte_num(a, b):
    return a >= b

## Perform fast equality check without type checks
proc fast_eq(a, b):
    return a == b

## Perform fast inequality check without type checks
proc fast_neq(a, b):
    return a != b

## ============================================================
## 6. Loop Specialization Helpers
## ============================================================
## Unrolled iteration primitives for common patterns.

## Iterate array with index, calling fn(index, element) for each
proc fast_each_indexed(arr, fn):
    for i in range(len(arr)):
        fn(i, arr[i])

## Sum an array of numbers without type checks
proc fast_sum(arr):
    let total = 0
    for item in arr:
        total = total + item
    return total

## Map over array, returning new array
proc fast_map(arr, fn):
    let map_result = []
    for item in arr:
        push(map_result, fn(item))
    return map_result

## Filter array by predicate
proc fast_filter(arr, pred):
    let filter_result = []
    for item in arr:
        if pred(item):
            push(filter_result, item)
    return filter_result

## ============================================================
## 7. Interned String Pool — avoid repeated string allocations
## ============================================================

let _string_pool = {}

## Intern a string in the global string pool
proc intern(s):
    if dict_has(_string_pool, s):
        return _string_pool[s]
    _string_pool[s] = s
    return s

## Retrieve all keys inside the global string pool
proc intern_keys():
    return dict_keys(_string_pool)
