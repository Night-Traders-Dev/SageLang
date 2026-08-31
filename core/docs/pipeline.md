SageLang Ideal Runtime Pipeline

One Language, One Semantic Contract, Multiple Execution Tiers

Target: Modular SageLang execution stack centered on "core/src/sage/"

Status: Updated target architecture after interpreter modularization

Primary objective: Preserve SageLang compatibility and backend parity while moving from a monolithic tree-walking interpreter to a compact, tiered, capability-aware runtime.

---

1. Executive Summary

The modularized SageLang runtime should separate five concerns:

Frontend
  parsing and semantic analysis

Execution
  reference interpretation, bytecode, JIT, and AOT

Common runtime
  values, frames, environments, calls, objects, errors, and control flow

Optimization
  profiling, slots, shapes, specialization, and deoptimization

Host integration
  capabilities, modules, filesystem, FFI, memory, and platform services

The ideal pipeline is:

                         Sage Source
                              |
                           Lexer
                              |
                           Parser
                              |
                             AST
                              |
                      Semantic Analysis
                              |
                           Sage IR
                              |
                +-------------+-------------+
                |             |             |
                v             v             v
           Reference VM   Bytecode VM   Native/JIT/AOT
                |             |             |
                +-------------+-------------+
                              |
                       Common Runtime
                              |
                +-------------+-------------+
                |             |             |
                v             v             v
             General       Embedded     Deterministic
             Profile        Profile        Profile

The governing rule is:

«One language, one semantic contract, one common runtime model, and multiple execution representations.»

The reference interpreter remains the compatibility oracle and bootstrap path. The bytecode VM becomes the compact production baseline. CPC evolves into a formal optimization tier over shared IR and runtime operations. JIT and AOT consume the same semantic foundation.

---

2. Ideal End-to-End Pipeline

Source
  |
  v
Lexer
  |
  v
Parser
  |
  v
AST
  |
  v
Semantic Analysis
  ├── name resolution
  ├── lexical scope classification
  ├── function identity
  ├── capability validation
  └── diagnostics
  |
  v
Sage IR
  ├── lexical slots
  ├── explicit control flow
  ├── call metadata
  ├── exception/defer regions
  └── source mappings
  |
  +-------------------+-------------------+-------------------+
  |                   |                   |                   |
  v                   v                   v                   v
Reference VM      Bytecode VM        CPC Optimizer       Native/AOT
  |                   |                   |                   |
  +-------------------+-------------------+-------------------+
                              |
                              v
                       Common Runtime
                              |
       +----------------+----------------+----------------+
       |                |                |                |
       v                v                v                v
   Values          CallFrames        Objects         Capabilities
       |                |                |                |
       +----------------+----------------+----------------+
                              |
                              v
                       Runtime Profile

Every execution tier must use the same definitions for:

values
truthiness
operators
calls
argument binding
properties
indexing
slicing
closures
classes
inheritance
super
exceptions
defer
finally
generators
imports
resource limits
capability checks

---

3. Modular Runtime Layout

core/src/sage/
├── runtime.sage
│
├── runtime/
│   ├── context.sage
│   ├── values.sage
│   ├── environment.sage
│   ├── slots.sage
│   ├── frames.sage
│   ├── control.sage
│   ├── errors.sage
│   ├── objects.sage
│   ├── calls.sage
│   ├── modules.sage
│   └── capabilities.sage
│
├── frontend/
│   ├── lexer.sage
│   ├── parser.sage
│   ├── resolver.sage
│   └── diagnostics.sage
│
├── interpreter/
│   ├── eval_expr.sage
│   ├── eval_stmt.sage
│   ├── classes.sage
│   ├── generators.sage
│   └── unwind.sage
│
├── ir/
│   ├── ir.sage
│   ├── builder.sage
│   ├── verifier.sage
│   └── optimizer.sage
│
├── vm/
│   ├── reference.sage
│   ├── bytecode.sage
│   ├── dispatch.sage
│   └── debugger.sage
│
├── opt/
│   ├── cpc.sage
│   ├── profiler.sage
│   ├── specialization.sage
│   ├── shapes.sage
│   ├── deopt.sage
│   └── loops.sage
│
└── host/
    ├── builtins.sage
    ├── modules.sage
    ├── filesystem.sage
    ├── ffi.sage
    ├── memory.sage
    └── platform.sage

"interpreter.sage" should become a thin orchestration layer that:

creates InterpreterContext
selects a runtime profile
invokes the frontend
builds or loads Sage IR
selects an execution tier
runs the program
normalizes diagnostics and results

It should no longer contain the implementation of every runtime subsystem.

---

4. Common Runtime Foundation

InterpreterContext

InterpreterContext
├── global_env
├── module_cache
├── module_paths
├── error_context
├── profiler
├── resource_limits
├── host_capabilities
├── runtime_profile
├── runtime_flags
└── allocator/state

Each interpreter instance owns its mutable state.

This enables:

multiple interpreters
thread isolation
embedding
sandboxing
deterministic execution
independent tests

Runtime Values

All tiers must share a common value model for:

nil
booleans
numbers
strings
arrays
dictionaries
functions
classes
instances
modules
generators
native handles

CallFrames

CallFrame
├── function_id
├── function
├── instruction/AST position
├── locals or slots
├── closure
├── return target
├── defer stack
├── exception state
└── source location

The same conceptual frame model supports:

reference execution
bytecode execution
generators
exception unwinding
JIT deoptimization
debugging

---

5. Semantic Authority

Canonical runtime operations must define language behavior once:

runtime_get_property()
runtime_set_property()
runtime_index()
runtime_set_index()
runtime_slice()
runtime_truthy()
runtime_binary()
runtime_unary()
runtime_call()
runtime_bind_arguments()
runtime_raise()
runtime_import()
runtime_iterate()
runtime_compare()

Execution tiers may optimize dispatch, representation, and storage.

They must not independently redefine semantics.

                 Canonical Runtime Operation
                              |
              +---------------+---------------+
              |               |               |
        Reference VM      Bytecode VM      JIT/AOT

---

6. Frontend and Semantic Analysis

The frontend should produce an AST for diagnostics, tooling, and reference execution.

Semantic analysis should additionally compute:

local bindings
closure captures
global bindings
module bindings
function IDs
method ownership
parameter maps
control-flow regions
exception/defer regions
capability requirements

Example binding classification:

local   -> frame slot
closure -> captured cell or environment slot
global  -> context global environment
module  -> module table entry

This allows the production pipeline to avoid repeated string-based environment lookup.

---

7. Sage IR

Sage IR is the shared production representation.

Example:

LOAD_LOCAL 0
LOAD_LOCAL 1
ADD
STORE_LOCAL 0

LOAD_CONST 2
JUMP_IF_FALSE L1
CALL 1
RETURN

IR should represent:

lexical slots
calls and argument binding
property/index operations
branches and loops
returns
break/continue
yield
throws
defer/finally regions
imports
source locations

The AST remains available for:

debugging
reference execution
bootstrap recovery
source diagnostics

The IR becomes the normal execution representation for:

bytecode
CPC
JIT
AOT
embedded builds

---

8. Execution Tiers

Tier 0 — Reference Execution

AST
  |
  v
Reference VM

Purpose:

semantic oracle
bootstrap implementation
debugging
differential testing
compatibility recovery

The reference path prioritizes clarity and correctness over speed.

Tier 1 — Bytecode VM

Sage IR
  |
  v
Compact Bytecode
  |
  v
Bytecode VM

Purpose:

general-purpose production execution
lower memory usage
faster dispatch
compact deployment
embedded baseline

Tier 2 — CPC

Bytecode/IR
  |
  v
Profile-guided CPC

Purpose:

reduce dispatch overhead
specialize stable operations
optimize slots, calls, properties, and loops

CPC must use canonical runtime semantics and deoptimize safely when assumptions fail.

Tier 3 — JIT

Hot Sage IR
  |
  v
Specialized native code

Purpose:

hot-loop optimization
type specialization
shape specialization
inline caches
native arithmetic
optimized calls

Tier 4 — AOT

Sage IR
  |
  v
Native executable or library

Purpose:

startup reduction
deployment
static packaging
embedded applications
controlled production environments

---

9. Tier Selection

Runtime selection should be explicit:

--runtime reference
--runtime bytecode
--runtime cpc
--runtime jit
--runtime aot

The selected tier changes execution strategy only.

It must not change language semantics.

A typical adaptive path is:

cold code
   |
   v
reference or bytecode execution
   |
   | hot
   v
CPC optimization
   |
   | stable and profitable
   v
JIT specialization
   |
   | deployment build
   v
AOT compilation

---

10. Optimization Pipeline

Sage IR
  |
  v
IR verification
  |
  v
Basic optimization
  ├── constant folding
  ├── dead branch removal
  ├── slot resolution
  ├── call metadata
  └── control-flow simplification
  |
  v
Profile-guided optimization
  ├── type feedback
  ├── shape feedback
  ├── call frequency
  ├── loop trip counts
  └── branch behavior
  |
  v
Specialization
  ├── numeric operations
  ├── string concatenation
  ├── local slot access
  ├── property access
  ├── calls
  └── loops
  |
  v
Deoptimization metadata
  |
  v
CPC/JIT/AOT output

Specialization should require:

hot
stable
profitable

not merely:

called many times

If an assumption fails:

specialized code
      |
      X
      |
mismatch
      |
      v
deoptimize
      |
      v
generic IR or bytecode

A failed specialization must never become a semantic failure.

---

11. High-Value Optimizations

Lexical Slots

Replace:

name
  |
environment chain
  |
dictionary lookup

with:

name
  |
resolved slot
  |
frame storage

Preserve:

shadowing
closures
captured mutation
nested functions

Compact Runtime Objects

Use compact internal representations for:

Function
Class
Instance
Generator
Module
Environment

Keep user dictionaries fully dynamic.

Compact CallFrames

Reduce allocation pressure and support:

recursion
closures
generators
exceptions
deoptimization
debugging

Keyword Argument Maps

Precompute:

param_lookup = {
    "foo": 0,
    "bar": 1,
    "baz": 2
}

Preserve all argument errors and default behavior.

Property Shapes

Use:

instance
  |
shape ID
  |
field slot

with fallback to:

dynamic property lookup
method lookup
class lookup

Function Identity

Use stable internal IDs:

Function
├── function_id
├── source_name
├── owner_class
├── params
├── defaults
├── body/IR
├── closure
└── profile

Profiles must be keyed by "function_id", not source name.

True Generator Frames

generator()
    |
create GeneratorFrame

next()
    |
resume frame
    |
execute
    |
yield
    |
save state

Generators must suspend execution rather than eagerly collecting all yielded values.

---

12. Unified Control Flow and Errors

Represent control flow explicitly:

Normal
Return
Break
Continue
Yield
Throw

Each frame tracks:

pending control flow
defer stack
exception state

The runtime must define precedence for:

try
finally
return
break
continue
throw
defer

Use structured errors:

RuntimeError
TypeError
NameError
PropertyError
IndexError
ArgumentError
CapabilityError
ResourceLimitError
HostError

Avoid using "nil" as a universal error-recovery value.

---

13. Module and Host Integration

Module state belongs to "InterpreterContext".

Track:

module ID
canonical path
source identity
dependencies
cache entry
capability requirements

Normalize module references before caching.

Host APIs must be capability-controlled:

SAFE
  pure computation
  data transforms

HOST
  clock
  filesystem
  operating-system APIs

UNSAFE
  FFI
  dynamic libraries
  raw memory
  host addresses

Before executing privileged operations:

capability_check()
argument_validation()
resource_check()

Restricted runtimes must fail with explicit errors.

---

14. Runtime Profiles

General

SAFE + HOST + selected UNSAFE

For desktop and server execution.

Embedded

SAFE + selected HOST

With:

small binary
limited modules
bounded memory
optional profiling
bytecode baseline

Deterministic

SAFE only

Allowed:

arithmetic
strings
arrays
deterministic maps
pure functions
deterministic crypto
bounded execution
explicit memory

Denied by default:

clock
filesystem
process execution
dynamic libraries
arbitrary FFI
raw host addresses
host memory inspection
unbounded recursion
unbounded loops

The deterministic profile is a deliberate capability configuration over the common runtime, not a separate language implementation.

---

15. Resource Limits

Each "InterpreterContext" configures:

max_steps
max_recursion_depth
max_memory
max_stack
max_generator_steps
max_module_count
max_output_bytes
max_call_depth

Examples:

General:
high limits

Embedded:
tight limits

Deterministic:
strict bounded limits

Resource exhaustion must produce:

ResourceLimitError

---

16. Verification and Parity Pipeline

Source
  |
  +-------------------+
  |                   |
  v                   v
Reference VM       Optimized Tier
  |                   |
  +---------+---------+
            |
         Normalize
            |
         Compare

Compare:

result
stdout
stderr
exceptions
mutations
generator output
module state
termination

Required parity coverage:

property access
indexing
calls
kwargs
defaults
closures
classes
super
defer
try/finally
imports
generators
resource errors
capability errors

Every discovered difference becomes a permanent regression test.

---

17. Testing and Benchmarking

Maintain:

core/docs/Runtime_Semantics.md
core/tests/semantics/
core/tests/parity/
core/tests/security/
core/tests/fuzz/
core/benchmarks/

Benchmark:

Fibonacci
loop sum
nested loops
array operations
string concatenation
dictionary operations
property access
function calls
closure calls
class methods
keyword arguments
prime sieve
hash/LCG workloads
module loading

Measure:

runtime
allocations
peak RAM
startup time
module load time
binary size

Compare:

Reference VM
Bytecode VM
CPC
JIT
AOT

---

18. Security Pipeline

Program
  |
  v
Semantic Analysis
  |
  v
Capability Validation
  |
  v
Resource Configuration
  |
  v
IR Verification
  |
  v
Execution Tier
  |
  v
Runtime Capability Checks
  |
  v
Bounded Execution

Security testing must target:

path traversal
module shadowing
FFI validation
raw memory APIs
stack exhaustion
recursive imports
resource exhaustion
malformed runtime values
capability escalation

---

19. Runtime Debugging Tools

Development builds should support:

--verify-parity
--trace-runtime
--dump-ir
--dump-slots
--dump-profile
--dump-shapes
--dump-frames
--dump-capabilities
--dump-deopt

These tools should explain:

which tier executed
which slot was used
which specialization was selected
why deoptimization occurred
which capability was requested
which resource limit was reached

---

20. Compatibility Matrix

Feature| Reference| Bytecode| CPC| JIT| AOT| Deterministic
arithmetic| ✓| ✓| ✓| ✓| ✓| ✓
strings| ✓| ✓| ✓| ✓| ✓| ✓
arrays| ✓| ✓| ✓| ✓| ✓| ✓
dictionaries| ✓| ✓| ✓| ✓| ✓| ✓
closures| ✓| ✓| ✓| ✓| ✓| ✓
kwargs| ✓| ✓| ✓| ✓| ✓| ✓
classes| ✓| ✓| ✓| ✓| ✓| ✓
inheritance| ✓| ✓| ✓| ✓| ✓| ✓
"super"| ✓| ✓| ✓| ✓| ✓| ✓
exceptions| ✓| ✓| ✓| ✓| ✓| ✓
"defer"| ✓| ✓| ✓| ✓| ✓| ✓
generators| ✓| ✓| ✓| ✓| ✓| bounded
imports| ✓| ✓| ✓| ✓| ✓| restricted
FFI| ✓| ✓| ✓| ✓| ✓| disabled
raw memory| ✓| ✓| ✓| ✓| ✓| disabled
wall clock| ✓| ✓| ✓| ✓| ✓| disabled
filesystem| ✓| ✓| ✓| ✓| ✓| policy-controlled

Unsupported restricted features must produce defined errors rather than falling through to host behavior.

---

21. Implementation Roadmap

Stage 1 — Semantic Foundation

[ ] Runtime semantics specification
[ ] Differential parity harness
[ ] Canonical property/index/call helpers
[ ] Formal error model
[ ] Defined `defer` and `finally` behavior
[ ] Defined generator behavior

Stage 2 — Modular Runtime

[ ] InterpreterContext
[ ] Function IDs
[ ] CallFrame
[ ] Unified unwind state
[ ] Capability model
[ ] Configurable resource limits
[ ] Modular host integration

Stage 3 — Production Execution

[ ] Lexical slot resolver
[ ] Compact local storage
[ ] Compact runtime objects
[ ] Bytecode format
[ ] Bytecode VM
[ ] Module isolation

Stage 4 — Optimization

[ ] Formal CPC tier
[ ] Type feedback
[ ] Shape feedback
[ ] Property fast paths
[ ] Keyword argument fast paths
[ ] Loop specialization
[ ] Deoptimization

Stage 5 — Advanced Backends

[ ] True generator frames
[ ] Sage IR optimizer
[ ] JIT backend
[ ] AOT backend
[ ] Native packaging

Stage 6 — Secure and Embedded Profiles

[ ] Minimal runtime profile
[ ] Deterministic runtime
[ ] Restricted module loader
[ ] Capability enforcement
[ ] FFI restrictions
[ ] Raw-memory restrictions
[ ] Footprint matrix
[ ] Embedded feature sets

---

22. Recommended Priority Order

1. Semantic specification
2. Differential parity harness
3. Canonical runtime operations
4. InterpreterContext
5. Function identity
6. CallFrame
7. Lexical slots
8. Modular bytecode VM
9. Compact runtime objects
10. CPC tier cleanup
11. Type and shape specialization
12. Unified unwind model
13. True generator frames
14. Sage IR optimization
15. JIT/AOT backends
16. Deterministic runtime
17. Embedded footprint optimization

Correctness and semantic authority come before optimization.

---

23. Definition of Done

Correctness

[ ] Semantics document matches implementation
[ ] Reference and optimized paths agree
[ ] Backend differential tests pass
[ ] Exceptions are consistent
[ ] `defer` and `finally` are defined
[ ] Generators suspend correctly
[ ] Closures preserve captured mutation
[ ] Module identity is stable

Performance

[ ] Local variables use slots
[ ] Calls use compact frames
[ ] Bytecode is the compact baseline
[ ] Hot code uses measured specialization
[ ] Property accesses have safe fast paths
[ ] Profiling is configurable
[ ] Benchmarks show measurable improvement

Size

[ ] Unused host features can be omitted
[ ] Runtime metadata is compact
[ ] Module packaging is deduplicated
[ ] Embedded builds have explicit feature sets
[ ] Production execution does not require heavyweight AST structures

Security

[ ] Capabilities are explicit
[ ] Deterministic execution has no ambient host access
[ ] Resource limits are enforced
[ ] Restricted imports are enforced
[ ] FFI is capability-controlled
[ ] Raw memory is capability-controlled
[ ] Security errors are explicit

Compatibility

[ ] Existing tests pass
[ ] Differential tests pass
[ ] Runtime selection remains compatible
[ ] Existing source does not depend on execution tier
[ ] Reference execution remains available

---

24. Final Target Infographic

                         Sage Source
                              |
                              v
                           Lexer
                              |
                              v
                           Parser
                              |
                              v
                             AST
                              |
                              v
                      Semantic Analysis
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
      Scope/Slots       Function IDs       Capabilities
          |                   |                   |
          +-------------------+-------------------+
                              |
                              v
                           Sage IR
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
     Reference VM       Bytecode VM        CPC Optimizer
          |                   |                   |
          +-------------------+-------------------+
                              |
                              v
                    Specialized IR / Bytecode
                              |
                    +---------+---------+
                    |                   |
                    v                   v
                   JIT                 AOT
                    |                   |
                    +---------+---------+
                              |
                              v
                       Common Runtime
                              |
       +----------------------+----------------------+
       |                      |                      |
       v                      v                      v
   General Profile      Embedded Profile      Deterministic Profile
       |                      |                      |
   Host capabilities     Limited capabilities    No ambient capabilities
       |                      |                      |
       +----------------------+----------------------+
                              |
                              v
                    Bounded, Observable Execution

The ideal SageLang runtime is therefore:

modular frontend
        +
shared semantic runtime
        +
Sage IR
        +
reference VM
        +
bytecode VM
        +
CPC/JIT/AOT optimization
        +
explicit capability profiles
        +
differential verification

The self-hosted interpreter remains the reference and bootstrap implementation.

The bytecode VM becomes the compact general-purpose runtime.

CPC becomes the first profile-guided optimization tier.

JIT and AOT consume shared IR rather than reimplementing language behavior.

Embedded and deterministic deployments use the same runtime foundation with explicit feature and capability restrictions.

The result is a SageLang pipeline that improves performance, memory usage, portability, security, and maintainability without sacrificing compatibility or semantic parity.
