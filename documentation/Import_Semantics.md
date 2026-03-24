# Import Semantics

This document describes how `import` and `from ... import ...` behave across Sage execution paths, with focus on LLVM compile-time constant import resolution.

## Supported Forms

```sage
import math
import math as m
from math import sin, cos
from math import PI as CIRCLE_PI
```

### Dotted Module Paths

Modules organized in subdirectories use dot-separated paths. The dots map to directory separators on the filesystem:

```sage
import os.fat              # resolves to lib/os/fat.sage, binds as "fat"
import graphics.vulkan     # resolves to lib/graphics/vulkan.sage, binds as "vulkan"
import net.url             # resolves to lib/net/url.sage, binds as "url"
import crypto.hash         # resolves to lib/crypto/hash.sage, binds as "hash"
from graphics.math3d import vec3, mat4_mul
from os.elf import parse_header
from net.ip import parse_v4, is_private
from crypto.encoding import b64_encode, hex_encode
```

When using `import a.b`, the variable is bound using the **last component** of the path (e.g., `import os.fat` lets you call `fat.parse_boot_sector()`). Use `import a.b as alias` to override the binding name.

### Module Search Paths

The module system searches in order:

1. Current directory (`.`)
2. `./lib/`
3. `./modules/`

For dotted names like `os.fat`, dots are converted to `/` before searching, so `import os.fat` looks for `./lib/os/fat.sage`.

## Runtime vs Compile-Time Resolution

- Interpreter paths resolve imports at runtime by loading module environments.
- LLVM codegen now performs an additional compile-time pass for `from module import NAME` when `NAME` is a foldable module constant.

## LLVM Compile-Time Constant Imports

The following LLVM backends resolve cross-module constants during code generation:

- `src/c/llvm_backend.c` (C host LLVM backend)
- `src/sage/llvm_backend.sage` (self-hosted LLVM backend)

### What Gets Resolved

`from module import NAME` and `from module import NAME as ALIAS` can be resolved at compile time when:

1. `NAME` is defined by a top-level `let` in the imported module.
2. The initializer is compile-time foldable.
3. The fold result is a scalar constant (`number`, `string`, `bool`, or `nil`).

Common foldable patterns include literal constants, references to earlier constants in the same module, and simple constant expressions.

### LLVM Backend Search Paths

Both LLVM backends search for module source in these locations:

- `<base>/<module>.sage`
- `<base>/lib/<module>.sage`
- `<base>/modules/<module>.sage`

Where `<base>` is the source resolution base for the backend (source file directory in C LLVM backend; working directory in self-hosted LLVM backend). For dotted module names (e.g., `os.fat`), dots are converted to directory separators before searching.

### GPU Constant Special Case

In the C LLVM backend, `from gpu import CONST` resolves from the built-in GPU constant table at compile time.

Example:

```sage
from gpu import BUFFER_STORAGE, MEMORY_HOST_VISIBLE as HOST_VISIBLE
```

## Behavior on Failure

If a requested `from module import NAME` constant cannot be resolved during LLVM codegen, compilation fails with an unresolved imported constant error instead of emitting an unresolved `%NAME` LLVM variable load.

## Example: Cross-Module Constant Import

`mathlib.sage`:

```sage
let PI = 3.14159
let TAU = PI * 2
```

`main.sage`:

```sage
from mathlib import TAU as CIRCLE
print CIRCLE
```

When compiled with `--compile-llvm`, `CIRCLE` is emitted as a constant value in generated IR.
