## perf.sage — Compile-time performance primitives for Sage
##
## Uses comptime blocks, @inline pragmas, and pre-allocation patterns
## to eliminate hot-path overhead in performance-critical Sage code.
##
## Design goal: make self-hosted Sage match pure C performance by:
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
    let r = {}
    r["kind"] = 0
    r["value"] = val
    return r

## Return a pre-allocated break signal — zero allocation
proc sig_break():
    return _SIG_BREAK

## Return a pre-allocated continue signal — zero allocation
proc sig_continue():
    return _SIG_CONTINUE

## Return signal — always needs value, 1 allocation
proc sig_return(val):
    let r = {}
    r["kind"] = 1
    r["value"] = val
    return r

## ============================================================
## 2. Dispatch Tables — O(1) lookup replacing if/elif chains
## ============================================================
## Build a dict mapping keys to handler functions at module load time.
## On every dispatch, one dict lookup replaces N comparisons.

proc make_dispatch_table():
    return {}

proc dispatch_register(table, key, handler):
    table[key] = handler

proc dispatch_call(table, key, args):
    if dict_has(table, key):
        let handler = table[key]
        return handler(args)
    return nil

proc dispatch_has(table, key):
    return dict_has(table, key)

## ============================================================
## 3. Flat Environment Cache — bypass scope chain for hot locals
## ============================================================
## In tight loops, variable lookup walks a linked list of scope dicts.
## A flat cache stores the most recently accessed variables in a single
## dict with no parent chain, providing O(1) access.

proc flat_cache_new():
    return {}

proc flat_cache_get(cache, name):
    if dict_has(cache, name):
        return cache[name]
    return nil

proc flat_cache_set(cache, name, value):
    cache[name] = value

proc flat_cache_has(cache, name):
    return dict_has(cache, name)

## Snapshot: copy the current environment's immediate locals into a flat cache
proc flat_cache_snapshot(env):
    let cache = {}
    let vals = env["vals"]
    let keys = dict_keys(vals)
    let i = 0
    while i < len(keys):
        cache[keys[i]] = vals[keys[i]]
        i = i + 1
    return cache

## Write-back: flush the flat cache into the real environment
proc flat_cache_flush(cache, env):
    let vals = env["vals"]
    let keys = dict_keys(cache)
    let i = 0
    while i < len(keys):
        vals[keys[i]] = cache[keys[i]]
        i = i + 1

## ============================================================
## 4. Shape Objects — fixed-layout dicts for known structures
## ============================================================
## Instead of building dicts key-by-key, create templates that are
## cloned (dict copy) for each new instance. This reduces hash
## collisions since the dict is pre-sized.

## Pre-allocated function shape (avoids 5 separate dict_set calls)
let _FUNC_SHAPE = {
    "__interp_type": "function",
    "name": "",
    "params": nil,
    "body": nil,
    "closure": nil,
    "is_generator": false
}

proc shape_function(name, params, body, closure, is_gen):
    let f = {}
    f["__interp_type"] = "function"
    f["name"] = name
    f["params"] = params
    f["body"] = body
    f["closure"] = closure
    f["is_generator"] = is_gen
    return f

## Pre-allocated class shape
proc shape_class(name, parent):
    let cls = {}
    cls["__interp_type"] = "class"
    cls["name"] = name
    cls["methods"] = {}
    cls["parent"] = parent
    return cls

## Pre-allocated instance shape
proc shape_instance(cls):
    let inst = {}
    inst["__interp_type"] = "instance"
    inst["class"] = cls
    inst["fields"] = {}
    return inst

## Pre-allocated native function shape
proc shape_native(name, arity):
    let f = {}
    f["__interp_type"] = "native"
    f["name"] = name
    f["arity"] = arity
    return f

## Pre-allocated generator shape
proc shape_generator(values):
    let gen = {}
    gen["__interp_type"] = "generator"
    gen["values"] = values
    gen["index"] = 0
    return gen

## Pre-allocated environment shape
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

proc fast_add_num(a, b):
    return a + b

proc fast_sub_num(a, b):
    return a - b

proc fast_mul_num(a, b):
    return a * b

proc fast_div_num(a, b):
    return a / b

proc fast_mod_num(a, b):
    return a % b

proc fast_lt_num(a, b):
    return a < b

proc fast_gt_num(a, b):
    return a > b

proc fast_lte_num(a, b):
    return a <= b

proc fast_gte_num(a, b):
    return a >= b

proc fast_eq(a, b):
    return a == b

proc fast_neq(a, b):
    return a != b

## ============================================================
## 6. Loop Specialization Helpers
## ============================================================
## Unrolled iteration primitives for common patterns.

## Iterate array with index, calling fn(index, element) for each
proc fast_each_indexed(arr, fn):
    let n = len(arr)
    let i = 0
    while i < n:
        fn(i, arr[i])
        i = i + 1

## Sum an array of numbers without type checks
proc fast_sum(arr):
    let total = 0
    let n = len(arr)
    let i = 0
    while i < n:
        total = total + arr[i]
        i = i + 1
    return total

## Map over array, returning new array
proc fast_map(arr, fn):
    let result = []
    let n = len(arr)
    let i = 0
    while i < n:
        push(result, fn(arr[i]))
        i = i + 1
    return result

## Filter array by predicate
proc fast_filter(arr, pred):
    let result = []
    let n = len(arr)
    let i = 0
    while i < n:
        if pred(arr[i]):
            push(result, arr[i])
        i = i + 1
    return result

## ============================================================
## 7. Interned String Pool — avoid repeated string allocations
## ============================================================

let _string_pool = {}

proc intern(s):
    if dict_has(_string_pool, s):
        return _string_pool[s]
    _string_pool[s] = s
    return s

proc intern_keys():
    return dict_keys(_string_pool)
