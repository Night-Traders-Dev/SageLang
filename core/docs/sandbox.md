SageLang Sandbox Plan

Pure Sage Runtime Observability, Module Tracing & Resource Dashboard

Project Name: Sage Sandbox
Implementation Language: Pure Sage
Primary Integration: "sage" and "sage-c"
Activation: Optional via "--sandbox"
Status: Proposed Architecture

---

1. Executive Summary

Sage Sandbox is an optional runtime observability and monitoring system for SageLang.

When enabled with:

sage --sandbox program.sage

or:

sage-c --sandbox program.sage

the Sandbox records and visualizes:

- which modules are imported,
- which module imported each dependency,
- the complete module dependency graph,
- module load order,
- module initialization time,
- execution time,
- estimated resource usage,
- memory allocations,
- object counts,
- function activity,
- CPU/runtime time,
- errors and exceptions,
- program-level resource totals.

The Sandbox must be implemented primarily in pure Sage so that the monitoring logic remains portable, self-hosted, and compatible with the Sage ecosystem.

The core design principle is:

«Sage Sandbox must observe the runtime without becoming a required runtime dependency or changing program semantics.»

The Sandbox is optional:

Normal execution
      |
      v
No Sandbox overhead

When enabled:

--sandbox
     |
     v
Sage Sandbox Runtime
     |
     +-----------------------------+
     |                             |
     v                             v
Module Observability          Resource Monitoring
     |                             |
     +-------------+---------------+
                   |
                   v
             Event Stream
                   |
          +--------+--------+
          |                 |
          v                 v
     CLI Dashboard     Export/Reports

---

2. Project Goals

2.1 Primary Goals

Sage Sandbox must provide visibility into:

Module Activity

Who imported what?
What imported this module?
How many times was it requested?
Was it loaded from cache?
How long did loading take?
How much memory did it consume?

Program Resources

Execution time
CPU/runtime time
Memory usage
Allocation count
Object count
Peak resource usage
Module resource usage

Dependency Graphs

main.sage
    |
    +-- math
    |
    +-- crypto
    |      |
    |      +-- hash
    |
    +-- network
           |
           +-- socket

Runtime Activity

Program start
Module import
Module execution
Function activity
Allocation
Exception
Resource threshold
Program exit

---

3. Non-Goals

The first version of Sage Sandbox is not primarily a security sandbox.

It should not initially attempt to:

isolate processes
virtualize the operating system
prevent filesystem access
prevent network access
replace container isolation

Those capabilities may later be integrated with the Sage runtime capability system.

The initial purpose is:

«Observability and diagnostics.»

Security restrictions can become an optional future mode:

sage --sandbox --restricted program.sage

but this is not required for the first implementation.

---

4. Design Requirements

4.1 Pure Sage

The Sandbox should be implemented primarily using Sage:

core/src/sage/sandbox/

Recommended structure:

sandbox/
├── sandbox.sage
├── context.sage
├── events.sage
├── modules.sage
├── resources.sage
├── profiler.sage
├── dashboard.sage
├── graph.sage
├── report.sage
├── limits.sage
└── export.sage

The runtime host may provide optional low-level counters.

However:

Sage Sandbox logic
Dashboard
Module graph
Event processing
Reports
Resource aggregation

should remain implemented in Sage.

---

5. User Interface

The primary activation mechanism is:

--sandbox

Supported commands:

sage --sandbox program.sage

sage-c --sandbox program.sage

Optional future modes:

sage --sandbox=dashboard program.sage

sage --sandbox=report program.sage

sage --sandbox=json program.sage

sage --sandbox=live program.sage

Default behavior:

sage --sandbox program.sage

should launch the program and display the final Sandbox dashboard after execution.

---

6. High-Level Architecture

                        Sage Program
                             |
                             v
                     Sage Runtime / VM
                             |
                       --sandbox
                             |
                             v
                     Sandbox Context
                             |
            +----------------+----------------+
            |                |                |
            v                v                v
      Module Monitor    Resource Monitor   Event Monitor
            |                |                |
            +----------------+----------------+
                             |
                             v
                        Event Bus
                             |
              +--------------+--------------+
              |                             |
              v                             v
         Data Store                    Live Dashboard
              |                             |
              +--------------+--------------+
                             |
                             v
                       Final Report

The Sandbox should never require program code changes.

Example:

import crypto
import network

print("Hello")

runs normally.

When Sandbox is enabled:

sage --sandbox app.sage

the runtime automatically captures the execution.

---

7. Sandbox Context

Each sandboxed execution receives a dedicated:

SandboxContext

Structure:

SandboxContext
├── enabled
├── start_time
├── program_id
├── program_path
├── module_registry
├── module_graph
├── resource_tracker
├── event_stream
├── profiler
├── limits
├── configuration
└── report

Example conceptual structure:

class SandboxContext:
    enabled
    start_time

    modules
    module_graph

    resources
    events

    profiler
    limits

The Sandbox Context should be owned by:

InterpreterContext

rather than global mutable state.

Target architecture:

InterpreterContext
├── global_env
├── module_cache
├── profiler
├── capabilities
└── sandbox_context

When disabled:

sandbox_context = nil

The normal runtime should therefore avoid Sandbox logic wherever possible.

---

8. Module Observability

Module tracing is the primary feature.

Every import should generate an event.

Example:

import crypto

produces:

MODULE_IMPORT_REQUEST

After resolution:

MODULE_RESOLVED

When loading begins:

MODULE_LOAD_BEGIN

After execution:

MODULE_LOAD_COMPLETE

If cached:

MODULE_CACHE_HIT

If failed:

MODULE_LOAD_ERROR

---

9. Import Relationship Tracking

Every module import must record:

Importer
        |
        v
Imported Module

Example:

main.sage
    |
    +-- crypto
    |
    +-- network

If:

crypto
   |
   +-- hash

then the graph becomes:

main
 ├── crypto
 │      └── hash
 │
 └── network

Each relationship should be stored as:

ModuleEdge
├── importer_id
├── imported_id
├── import_type
├── timestamp
├── load_time
└── status

---

10. Module Identity

Modules should not be identified only by name.

Use:

Module ID

with:

ModuleInfo
├── id
├── name
├── canonical_path
├── source_type
├── importer
├── importers
├── dependencies
├── load_count
├── cache_hits
├── load_start
├── load_end
├── execution_time
├── memory_usage
├── allocation_count
└── status

Example:

ModuleInfo

ID:
    module:crypto:ab12

Name:
    crypto

Path:
    std/crypto.sage

Imported By:
    main.sage

Dependencies:
    hash
    random

Load Time:
    4.2 ms

Execution Time:
    12.8 ms

Peak Memory:
    84 KB

---

11. Module Import Graph

The Sandbox should construct an internal dependency graph.

ModuleGraph
├── nodes
└── edges

Node:

ModuleNode
├── module_id
├── name
├── path
├── resource_stats
└── status

Edge:

ModuleEdge
├── importer
├── imported
├── timestamp
└── status

The graph should support:

tree view
dependency view
reverse dependency view
load order view
resource view

---

12. Module Dashboard

The default module dashboard:

┌──────────────────────────────────────────────────────────┐
│                    SAGE SANDBOX                          │
├──────────────────────────────────────────────────────────┤
│ Program: app.sage                                        │
│ Runtime: 42.8 ms                                         │
│ Peak Memory: 1.8 MB                                      │
├──────────────────────────────────────────────────────────┤
│ MODULES                                                 │
├──────────────────┬───────────┬───────────┬───────────────┤
│ Module           │ Load Time │ Memory    │ Imported By   │
├──────────────────┼───────────┼───────────┼───────────────┤
│ main             │ 1.2 ms    │ 312 KB    │ root          │
│ crypto           │ 4.8 ms    │ 128 KB    │ main          │
│ hash             │ 1.6 ms    │ 42 KB     │ crypto        │
│ network          │ 7.2 ms    │ 256 KB    │ main          │
└──────────────────┴───────────┴───────────┴───────────────┘

---

13. Reverse Dependency View

A critical feature should be:

«What imported this module?»

Example:

MODULE: hash

Imported by:

crypto
   |
   └── main

network
   |
   └── main

CLI view:

hash
├── crypto
│   └── main
└── network
    └── main

This should help identify:

unexpected dependencies
duplicate dependencies
dependency chains
heavy modules
cyclic imports

---

14. Resource Monitoring

The Sandbox should collect resource information at:

program level
module level
function level
optional runtime level

Core metrics:

wall clock time
runtime execution time
CPU time when available
current memory
peak memory
allocation count
object count
module load time
module execution time

---

15. Resource Snapshot System

The Sandbox should support snapshots.

ResourceSnapshot
├── timestamp
├── memory_current
├── memory_peak
├── allocation_count
├── object_count
├── execution_time
└── cpu_time

Snapshots are captured at:

program start
module import
module load completion
function boundaries (optional)
program exit

This allows resource deltas.

Example:

Before crypto import:
    1.2 MB

After crypto import:
    1.8 MB

Crypto module delta:
    +600 KB

---

16. Resource Attribution

The Sandbox should attempt to attribute resources to the currently active execution scope.

Hierarchy:

Program
   |
   +-- Module
   |     |
   |     +-- Function
   |
   +-- Module

Example:

app.sage
│
├── crypto
│      Memory: 128 KB
│      Time: 8.4 ms
│
│      └── hash
│             Memory: 42 KB
│             Time: 1.8 ms
│
└── network
       Memory: 256 KB
       Time: 12.1 ms

---

17. Resource Accuracy Levels

Not all Sage runtimes can provide identical resource metrics.

Define three levels.

Level 1 — Pure Sage

Available everywhere:

execution timers
module load timing
event counts
allocation events exposed by runtime
object counts
estimated resource usage

Level 2 — Sage Runtime Counters

Available when the host runtime provides counters:

allocation count
allocated bytes
freed bytes
current runtime memory
peak runtime memory

Level 3 — Host Metrics

Available only where supported:

process RSS
CPU time
thread usage
system memory

The dashboard should indicate accuracy:

Memory:
    1.8 MB
    Source: Runtime Counter

or:

Memory:
    ~1.8 MB
    Source: Estimated

---

18. Event System

All Sandbox activity should use a common event model.

SandboxEvent
├── id
├── type
├── timestamp
├── module_id
├── function_id
├── payload
└── resource_snapshot

Event types:

PROGRAM_START
PROGRAM_END

MODULE_IMPORT_REQUEST
MODULE_RESOLVED
MODULE_LOAD_BEGIN
MODULE_LOAD_COMPLETE
MODULE_CACHE_HIT
MODULE_LOAD_ERROR

FUNCTION_ENTER
FUNCTION_EXIT

ALLOCATION
DEALLOCATION

RESOURCE_SNAPSHOT
RESOURCE_LIMIT

EXCEPTION
RUNTIME_ERROR

---

19. Event Bus

The Sandbox should use an internal event dispatcher.

Runtime
   |
emit_event()
   |
   v
Sandbox Event Bus
   |
   +--------------------+
   |                    |
   v                    v
Module Tracker     Resource Tracker
   |                    |
   +---------+----------+
             |
             v
          Dashboard

The event system should avoid expensive allocations when possible.

Recommended modes:

OFF
SUMMARY
STANDARD
DETAILED

---

20. Sandbox Modes

OFF

sage program.sage

No Sandbox context.

No event tracking.

---

SUMMARY

sage --sandbox=summary program.sage

Tracks:

program runtime
module imports
module load time
total memory
peak memory

Lowest overhead.

---

STANDARD

sage --sandbox program.sage

Tracks:

module graph
module resources
execution time
resource snapshots
errors
cache activity

Recommended default.

---

DETAILED

sage --sandbox=detailed program.sage

Tracks:

function activity
allocation events
detailed module timing
resource timeline
event stream

Higher overhead.

---

21. CLI Integration

Both runtimes should expose the same interface.

sage --sandbox program.sage

sage-c --sandbox program.sage

Configuration:

--sandbox
--sandbox=summary
--sandbox=standard
--sandbox=detailed

Optional output:

--sandbox-report report.json

--sandbox-report report.sage.json

--sandbox-export graph

---

22. Sage CLI Architecture

sage CLI
   |
parse arguments
   |
--sandbox?
   |
   +--- no
   |      |
   |      v
   |   normal runtime
   |
   +--- yes
          |
          v
    SandboxContext
          |
          v
    execute program
          |
          v
    Sandbox Report

Pseudo flow:

if args.has("--sandbox"):
    sandbox = SandboxContext.create(config)
    interpreter.set_sandbox(sandbox)

result = interpreter.run(program)

if sandbox:
    sandbox.finish()
    dashboard.show(sandbox)

---

23. Sage-C Integration

The "sage-c" runtime must expose the same logical interface.

sage-c
   |
--sandbox
   |
   v
Sage Sandbox Runtime
   |
   v
C Runtime Events

Important design rule:

«"sage-c" should not implement a separate Sandbox architecture.»

Instead:

Pure Sage Sandbox
        |
        +----------------+
        |                |
        v                v
      sage             sage-c

Both runtimes provide event hooks.

The Sandbox consumes the same logical events.

---

24. Runtime Hook Interface

The host runtime should expose minimal hooks.

Example conceptual API:

sandbox_program_start()
sandbox_program_end()

sandbox_module_import()
sandbox_module_loaded()

sandbox_function_enter()
sandbox_function_exit()

sandbox_resource_snapshot()

sandbox_exception()

When Sandbox is disabled:

hook = no-op

The runtime must avoid:

if sandbox enabled

through every hot operation if possible.

Preferred:

event_hook()

bound to:

no-op function

when disabled.

---

25. Zero-Cost Disabled Path

The architecture should optimize:

sage program.sage

not:

sage --sandbox program.sage

The disabled path should approximate:

Normal Runtime
    |
    v
No Sandbox Object
No Event Storage
No Dashboard
No Resource Sampling

Target:

Sandbox disabled overhead:
    near zero

Potential design:

runtime.event_hook

Disabled:

noop

Enabled:

sandbox.emit

---

26. Dashboard Architecture

The first dashboard should be terminal-based.

Recommended implementation:

Pure Sage TUI

Dashboard:

┌──────────────────────────────────────────────────────────┐
│ SAGE SANDBOX                             RUNNING          │
├──────────────────────────────────────────────────────────┤
│ Program       app.sage                                    │
│ Runtime       42.8 ms                                     │
│ Memory        1.2 MB / Peak 1.8 MB                        │
│ Modules       12                                           │
│ Events        248                                          │
├──────────────────────────────────────────────────────────┤
│ MODULE TREE                                              │
│                                                          │
│ ▼ main                                                    │
│   ├── ▼ crypto                                            │
│   │    ├── hash                                           │
│   │    └── random                                         │
│   │                                                       │
│   └── ▼ network                                           │
│        └── socket                                         │
│                                                          │
├──────────────────────────────────────────────────────────┤
│ SELECTED: crypto                                          │
│                                                          │
│ Load Time:      4.8 ms                                    │
│ Execution:      12.4 ms                                   │
│ Memory:         128 KB                                    │
│ Allocations:    248                                       │
│ Imported By:    main                                      │
└──────────────────────────────────────────────────────────┘

---

27. Dashboard Views

The Sandbox dashboard should have multiple views.

Overview

Program resources
Total modules
Runtime
Memory
Errors

---

Modules

Module tree
Load order
Import relationships

---

Resources

Memory
Time
Allocations
Objects

---

Timeline

0 ms      program start
2 ms      crypto import
5 ms      hash import
8 ms      crypto complete
12 ms     network import

---

Errors

Exceptions
Import failures
Resource limits
Runtime errors

---

28. Module Tree View

Example:

main
│
├── crypto
│   ├── hash
│   └── random
│
├── network
│   ├── socket
│   └── protocol
│
└── ui

Each node should display optional metrics:

crypto
├── Load: 4.8 ms
├── Memory: 128 KB
└── Dependencies: 2

---

29. Module Resource Ranking

Provide ranking views.

Example:

TOP MEMORY MODULES

1. machine_learning     18.2 MB
2. network               4.8 MB
3. crypto                2.1 MB
4. ui                    1.2 MB

Execution:

TOP EXECUTION MODULES

1. simulation           128 ms
2. network               84 ms
3. crypto                32 ms

Import cost:

SLOWEST IMPORTS

1. machine_learning      42 ms
2. network               18 ms
3. crypto                 8 ms

---

30. Resource Timeline

The Sandbox should record resource history.

Example:

Memory

2 MB |                         ████
    |                     ████
1 MB |          ██████████
    |     █████
0 MB +--------------------------------
      0    10    20    30    40 ms

Pure Sage implementation can initially use:

ASCII graphs

Future dashboard versions may support:

interactive charts
web dashboard

---

31. Per-Module Resource Scope

When loading a module:

MODULE_LOAD_BEGIN

capture:

ResourceSnapshot A

After loading:

MODULE_LOAD_COMPLETE

capture:

ResourceSnapshot B

Calculate:

Module Resource Delta
=
B - A

Example:

Before crypto:

Memory:
1.2 MB

After crypto:

Memory:
1.8 MB

Attributed:

crypto:
+600 KB

---

32. Nested Import Attribution

Nested imports require a resource stack.

Example:

main
 |
 | imports crypto
 v

crypto
 |
 | imports hash
 v

hash

Sandbox stack:

ResourceScopeStack

main
  |
crypto
  |
hash

When allocations occur:

allocation
    |
    v
current ResourceScope

Resources should be attributed to:

hash

and optionally aggregated upward:

hash
   ↓
crypto
   ↓
main

---

33. Direct vs Inclusive Resource Usage

Each module should expose:

Direct Memory

and:

Inclusive Memory

Example:

crypto

Direct:
128 KB

Dependencies:
hash       42 KB
random     18 KB

Inclusive:
188 KB

This distinction is critical.

Otherwise:

main

will appear responsible for every dependency resource cost.

---

34. Function Monitoring

Function monitoring should initially be optional.

When enabled:

FUNCTION_ENTER

and:

FUNCTION_EXIT

events are generated.

Function statistics:

FunctionStats
├── function_id
├── name
├── module_id
├── call_count
├── total_time
├── self_time
├── inclusive_time
└── allocation_count

Example:

FUNCTION

crypto.hash()

Calls:
12,402

Total:
42 ms

Self:
28 ms

Inclusive:
42 ms

---

35. Function Monitoring Modes

Default Sandbox:

module-level monitoring

Detailed Sandbox:

module + function monitoring

Deep profiling:

sage --sandbox=detailed --sandbox-profile program.sage

This prevents profiling overhead from becoming mandatory.

---

36. Resource Limits

The Sandbox should support optional resource thresholds.

Example:

sage --sandbox --sandbox-memory=128MB program.sage

sage --sandbox --sandbox-time=30s program.sage

Initial limits:

max_execution_time
max_memory
max_allocations
max_modules
max_import_depth

When exceeded:

RESOURCE_LIMIT event

Depending on configuration:

warn
pause
terminate
throw exception

---

37. Limit Modes

--sandbox-limit=warn

Produces:

WARNING

Memory threshold exceeded.

Current:
132 MB

Limit:
128 MB

---

--sandbox-limit=error

Produces:

ResourceLimitError

---

--sandbox-limit=stop

Terminates execution.

---

38. Import Depth Protection

The Sandbox should detect:

deep dependency trees
cyclic imports
recursive imports

Example:

main
 ↓
a
 ↓
b
 ↓
c
 ↓
...

Configuration:

--sandbox-max-import-depth=64

When exceeded:

ResourceLimitError:
Import depth exceeded

---

39. Circular Import Detection

Maintain module state:

UNSEEN
LOADING
LOADED
FAILED

When:

module A

imports:

module B

which imports:

module A

while A is:

LOADING

generate:

MODULE_CYCLE

Dashboard:

IMPORT CYCLE

main
 ↓
crypto
 ↓
hash
 ↓
crypto

---

40. Sandbox Report Format

The final report should be represented as a Sage-compatible dictionary.

Example:

{
    "program": {
        "path": "app.sage",
        "runtime_ms": 42.8
    },

    "resources": {
        "memory_peak": 1887436,
        "allocations": 2842
    },

    "modules": [
        ...
    ],

    "graph": {
        ...
    }
}

---

41. JSON Export

Support:

--sandbox-report=sandbox.json

Example:

{
    "program": "app.sage",
    "runtime_ms": 42.8,
    "peak_memory": 1887436,
    "modules": [
        {
            "name": "crypto",
            "load_time_ms": 4.8,
            "memory": 131072,
            "imported_by": ["main"]
        }
    ]
}

This enables:

CI
performance regression tracking
external visualization
automated analysis

---

42. Graph Export

Support:

--sandbox-export=graph

Output:

main
├── crypto
│   ├── hash
│   └── random
└── network

Future:

DOT
Graphviz
JSON graph

Example:

--sandbox-export=dot

---

43. Live Dashboard Mode

Future mode:

sage --sandbox=live program.sage

Architecture:

Program
   |
Sandbox Event Stream
   |
   +--------------+
   |              |
   v              v
Runtime       Dashboard
Events          TUI

The program continues executing while the dashboard updates.

Example:

Runtime:
12.4 seconds

Memory:
8.2 MB

Active Module:
network

Events:
2,842

Modules:
14

---

44. Interactive Controls

Recommended TUI controls:

↑ ↓
Navigate

Enter
Expand module

M
Module view

R
Resource view

T
Timeline

E
Errors

Q
Quit dashboard

Future:

P
Pause monitoring

F
Filter modules

/
Search

---

45. Sandbox Configuration

Provide a configuration object.

Example:

sandbox = {
    "mode": "standard",

    "modules": true,
    "resources": true,

    "functions": false,
    "allocations": false,

    "timeline": true,

    "limits": {
        "memory": 0,
        "time": 0
    }
}

CLI flags override defaults.

---

46. Environment Configuration

Optional:

SAGE_SANDBOX=1

Modes:

SAGE_SANDBOX_MODE=standard

Resource limit:

SAGE_SANDBOX_MEMORY=128MB

Useful for:

CI
testing
embedded systems
development environments

---

47. Programmatic Sandbox API

Programs should eventually be able to enable Sandbox APIs.

Example:

import sandbox

sandbox.enable()

or:

sandbox.snapshot("before_training")

Example:

sandbox.snapshot("before import")

import model

sandbox.snapshot("after import")

Result:

CUSTOM SNAPSHOT

before import:
1.2 MB

after import:
18.4 MB

Delta:
17.2 MB

---

48. Custom Events

Programs may emit custom events.

Example:

sandbox.event(
    "MODEL_LOADED",
    {
        "model": "sagecoder"
    }
)

Dashboard:

CUSTOM EVENT

MODEL_LOADED

model:
sagecoder

This should remain optional.

---

49. Sandbox API Safety

Programs must not be able to corrupt internal Sandbox state.

Separate:

Sandbox Internal API

from:

Sandbox Public API

Public:

snapshot()
event()
mark()

Internal:

module registration
resource attribution
event storage
runtime hooks

---

50. Module Cache Monitoring

Track cache behavior.

Metrics:

cache hits
cache misses
module reloads
cache size

Example:

MODULE CACHE

Hits:
42

Misses:
12

Hit Rate:
77.8%

Per module:

crypto

Loads:
1

Cache Hits:
8

---

51. Duplicate Import Detection

Detect:

main
 ├── crypto
 └── network
      └── crypto

Report:

Shared Dependency

crypto

Imported by:
main
network

Physical Loads:
1

Cache Reuse:
yes

---

52. Import Cost Analysis

The Sandbox should identify:

slow imports
memory-heavy imports
deep dependency chains
duplicate imports

Example:

IMPORT COST ANALYSIS

Most Expensive:

machine_learning
Load:
82 ms

Memory:
18 MB

Dependency Count:
42

---

53. Lazy Import Opportunities

Future analysis:

Module imported:
yes

Used:
no

Possible report:

POSSIBLE LAZY IMPORT

analytics

Imported by:
main

Functions used:
0

Import Cost:
42 ms

Memory:
8 MB

This should initially be advisory.

---

54. Runtime Resource Summary

At program completion:

┌──────────────────────────────────────────────┐
│            PROGRAM SUMMARY                   │
├──────────────────────────────────────────────┤
│ Runtime              42.8 ms                 │
│ CPU Time             38.1 ms                 │
│ Peak Memory          1.8 MB                  │
│ Allocations          2,842                   │
│ Modules Loaded       12                       │
│ Cache Hits           8                        │
│ Errors               0                        │
└──────────────────────────────────────────────┘

---

55. Module Summary

┌─────────────────────────────────────────────────────────┐
│ MODULES                                                 │
├───────────────┬──────────┬─────────┬────────────────────┤
│ Module        │ Time     │ Memory  │ Dependencies       │
├───────────────┼──────────┼─────────┼────────────────────┤
│ main          │ 12.4 ms  │ 312 KB  │ 4                  │
│ crypto        │ 8.2 ms   │ 128 KB  │ 2                  │
│ hash          │ 1.8 ms   │ 42 KB   │ 0                  │
│ network       │ 14.2 ms  │ 256 KB  │ 3                  │
└───────────────┴──────────┴─────────┴────────────────────┘

---

56. Error Dashboard

Capture:

ImportError
RuntimeError
TypeError
ResourceLimitError
CapabilityError

Example:

ERROR

Module:
network

Imported By:
main

Error:
ImportError

Message:
Unable to resolve socket

---

57. Exception Timeline

Example:

0 ms
PROGRAM_START

4 ms
MODULE_IMPORT crypto

8 ms
MODULE_COMPLETE crypto

12 ms
EXCEPTION

TypeError

This should make runtime failures easier to diagnose.

---

58. Performance Requirements

Sandbox overhead should be configurable.

Summary Mode

Target:

< 3% runtime overhead

Standard Mode

Target:

< 10% runtime overhead

Detailed Mode

Higher overhead acceptable.

The exact values should be benchmarked rather than assumed.

---

59. Memory Requirements

The Sandbox must avoid storing unlimited event history.

Default event storage:

ring buffer

Example:

max_events = 10000

Older events:

discarded

unless:

--sandbox-events=unlimited

is explicitly enabled.

---

60. Event Sampling

Detailed monitoring may use sampling.

Example:

function event:

1/1
all events

1/10
sampled

1/100
lightweight

Configuration:

--sandbox-sample=10

---

61. Embedded Compatibility

Sage Sandbox should support minimal runtimes.

Embedded profile:

SAGE_SANDBOX_EMBEDDED

Features:

module tracking
basic timers
event counters
resource limits

Disabled:

large event history
interactive dashboard
heavy graphs
JSON reports

Output:

serial
UART
minimal text

---

62. SageOS and Embedded Future

Sage Sandbox could become particularly useful for:

SageOS
SagePocket
SageApple
microcontroller runtimes

Example:

SAGE SANDBOX

Modules:
12

RAM:
18 KB / 32 KB

Peak:
24 KB

Current Module:
SageNet

Runtime:
2.4 seconds

This makes Sandbox useful beyond desktop development.

---

63. Deterministic Runtime Integration

The future deterministic runtime should integrate with Sandbox.

Additional metrics:

instruction count
resource units
memory units
import count
execution steps

Example:

DETERMINISTIC RESOURCES

Steps:
42,842

Memory Units:
18,422

Imports:
12

Maximum Steps:
100,000

This could eventually integrate with:

SageChain
Orbit
smart contracts
deterministic execution

---

64. Resource Metering Mode

Future mode:

sage --sandbox=meter program.sage

Tracks:

instructions
function calls
memory
allocations
imports
runtime operations

This is separate from the initial observability system but should use the same event architecture.

---

65. Recommended Source Structure

core/src/sage/sandbox/

├── sandbox.sage
│
├── context.sage
│   └── SandboxContext
│
├── events.sage
│   ├── SandboxEvent
│   └── EventBus
│
├── modules.sage
│   ├── ModuleInfo
│   ├── ModuleGraph
│   └── ModuleTracker
│
├── resources.sage
│   ├── ResourceSnapshot
│   ├── ResourceScope
│   └── ResourceTracker
│
├── profiler.sage
│   ├── FunctionStats
│   └── ModuleStats
│
├── limits.sage
│   ├── ResourceLimits
│   └── LimitMonitor
│
├── dashboard.sage
│   ├── Overview
│   ├── ModuleView
│   └── ResourceView
│
├── timeline.sage
│
├── graph.sage
│
├── report.sage
│
├── export.sage
│   ├── json
│   └── text
│
└── api.sage

---

66. Core Data Model

SandboxContext

SandboxContext
├── enabled
├── mode
├── program
├── modules
├── resources
├── events
├── limits
├── profiler
├── start_time
└── status

---

ModuleInfo

ModuleInfo
├── id
├── name
├── path
├── state
├── importers
├── dependencies
├── load_time
├── execution_time
├── direct_resources
└── inclusive_resources

---

ResourceStats

ResourceStats
├── memory_current
├── memory_peak
├── allocations
├── objects
├── execution_time
└── cpu_time

---

67. Implementation Phase 1 — Core Context

[ ] Create sandbox package
[ ] Create SandboxContext
[ ] Add sandbox_context to InterpreterContext
[ ] Implement enable/disable
[ ] Add CLI --sandbox
[ ] Implement no-op disabled mode

Exit criteria:

sage --sandbox hello.sage

creates a Sandbox Context without changing program output.

---

68. Implementation Phase 2 — Module Tracking

[ ] Hook import resolution
[ ] Track importer
[ ] Track imported module
[ ] Record load timing
[ ] Record module state
[ ] Track cache hits
[ ] Build module graph

Exit criteria:

sage --sandbox program.sage

can display:

complete module tree

---

69. Implementation Phase 3 — Resource Tracking

[ ] ResourceSnapshot
[ ] Module resource scopes
[ ] Program runtime
[ ] Module load timing
[ ] Memory counters
[ ] Allocation counters
[ ] Peak resource tracking

Exit criteria:

per-module resource table

is available.

---

70. Implementation Phase 4 — Dashboard

[ ] Overview
[ ] Module tree
[ ] Module details
[ ] Resource ranking
[ ] Error view
[ ] Timeline

First dashboard:

terminal-based
pure Sage

---

71. Implementation Phase 5 — Sage-C Integration

[ ] Add --sandbox to sage-c
[ ] Implement shared configuration
[ ] Expose runtime hooks
[ ] Ensure identical event schema
[ ] Verify report compatibility

Critical requirement:

sage report
==
sage-c report

for the same program where metrics are available.

---

72. Implementation Phase 6 — Reports

[ ] Text report
[ ] JSON report
[ ] Graph export
[ ] Resource summary
[ ] Module summary

---

73. Implementation Phase 7 — Detailed Profiling

[ ] Function events
[ ] Function statistics
[ ] Allocation attribution
[ ] Resource timelines
[ ] Sampling

---

74. Implementation Phase 8 — Resource Limits

[ ] Time limit
[ ] Memory limit
[ ] Allocation limit
[ ] Module count limit
[ ] Import depth limit
[ ] Warning mode
[ ] Error mode
[ ] Stop mode

---

75. Implementation Phase 9 — Advanced Analysis

[ ] Circular import visualization
[ ] Slow import detection
[ ] Heavy module detection
[ ] Duplicate dependency detection
[ ] Cache efficiency
[ ] Lazy import suggestions

---

76. CLI Specification

Minimum:

sage --sandbox program.sage
sage-c --sandbox program.sage

Modes:

--sandbox=summary
--sandbox=standard
--sandbox=detailed
--sandbox=live

Reports:

--sandbox-report=file.json

Export:

--sandbox-export=text
--sandbox-export=json
--sandbox-export=graph
--sandbox-export=dot

Limits:

--sandbox-memory=128MB
--sandbox-time=30s
--sandbox-max-modules=256
--sandbox-max-import-depth=64

---

77. Compatibility Requirements

Sandbox must preserve:

program output
import behavior
module cache behavior
exceptions
execution order
language semantics

Sandbox must not:

modify AST behavior
change module resolution
change import order
change program values

unless an explicit Sandbox resource limit terminates execution.

---

78. Backend Parity

The same program should produce compatible reports.

Sage Program
      |
      +----------------+
      |                |
      v                v
     sage            sage-c
      |                |
      v                v
Sandbox Events    Sandbox Events
      |                |
      +--------+-------+
               |
               v
        Compatible Report

Metrics may differ by implementation.

Example:

sage:
estimated memory

sage-c:
native allocation counter

The report must indicate:

metric source
accuracy
availability

---

79. Testing Strategy

Module Tests

single import
nested import
shared dependency
cache hit
cache miss
failed import
circular import
deep imports

---

Resource Tests

memory increase
allocation count
module resource attribution
nested resource scope
peak memory
resource reset

---

Dashboard Tests

empty program
single module
large dependency graph
errors
resource limit
long-running program

---

Backend Tests

sage --sandbox
sage-c --sandbox

Compare:

module graph
import order
event order
exceptions
report structure

---

80. Benchmark Suite

Measure Sandbox overhead with:

hello world
small imports
large module graph
CPU loop
allocation-heavy workload
function-heavy workload
exception-heavy workload

Compare:

sandbox disabled
summary
standard
detailed

Metrics:

runtime
memory
event count
report size

---

81. Definition of Done — Version 1

Core

[ ] Pure Sage Sandbox implementation
[ ] Optional SandboxContext
[ ] --sandbox CLI flag
[ ] sage support
[ ] sage-c support

Modules

[ ] Complete module graph
[ ] Importer tracking
[ ] Dependency tracking
[ ] Load timing
[ ] Cache tracking

Resources

[ ] Program runtime
[ ] Module runtime
[ ] Memory metric
[ ] Peak memory
[ ] Allocation metrics where available

Dashboard

[ ] Program overview
[ ] Module tree
[ ] Module details
[ ] Resource rankings
[ ] Error display

Reports

[ ] Text output
[ ] JSON export

---

82. Final Architecture

                         Sage Program
                              |
                              v
                    Sage Runtime / Sage-C
                              |
                         --sandbox
                              |
                              v
                       SandboxContext
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
    ModuleTracker      ResourceTracker       EventBus
          |                   |                   |
          v                   v                   |
     ModuleGraph        ResourceScopes          |
          |                   |                   |
          +-------------------+-------------------+
                              |
                              v
                         Data Model
                              |
             +----------------+----------------+
             |                                 |
             v                                 v
       Live Dashboard                    Final Report
             |                                 |
             v                                 v
         Pure Sage TUI                   Text / JSON

---

83. Long-Term Vision

Sage Sandbox should eventually become the observability layer for the entire Sage ecosystem.

                        Sage Sandbox
                             |
          +------------------+------------------+
          |                  |                  |
          v                  v                  v
       SageLang            SageOS           SageVM
          |                  |                  |
          +------------------+------------------+
                             |
                             v
                      Shared Events
                             |
                             v
                    Resource Monitoring

Future integrations:

SageLang
SageVM
SageOS
SageBoot
SagePocket
SageApple
SageChain
Orbit

The architecture should remain modular enough that individual environments can expose only the metrics they support.

---

84. Final Principle

The Sage Sandbox should not become another separate runtime.

It should become an optional observability layer over the existing Sage runtime.

The core architecture should therefore remain:

                         Sage Runtime
                              |
                       optional hooks
                              |
              +---------------+---------------+
              |                               |
              v                               v
          Disabled                          Enabled
              |                               |
              v                               v
        Normal Runtime                  Sage Sandbox
                                              |
                         +--------------------+--------------------+
                         |                    |                    |
                         v                    v                    v
                    Modules              Resources             Events
                         |                    |                    |
                         +--------------------+--------------------+
                                              |
                                              v
                                         Dashboard

The defining rule is:

«When disabled, Sage Sandbox should effectively disappear. When enabled, it should make the Sage runtime transparent.»

Sage Sandbox Version 1 should focus on answering four questions clearly:

1. What modules did my program load?

2. Who imported each module?

3. What resources did each module and the overall program consume?

4. What happened during execution, and where did the resources go?

Once those capabilities are stable, the same architecture can evolve into:

profiling
resource metering
embedded diagnostics
deterministic execution accounting
runtime security monitoring

without replacing the original Sandbox design.
