2026-09-30 - [Update SageLang Guide for f15f2c8]

Discovery:
- Version 4.2.14 bumped.
- Added `io.filesize`, `io.isdir`, `io.remove`, `io.mkdir` to C backend.
- `sys.args`, `sys.clock`, `sys.getenv` and `sys.shell_exec` are now reachable without needing an imported module, preventing "Cannot call non-function value".
- `ffi_call` has been improved, and the C backend can be used properly.

Evidence:
- `VERSION` and `core/VERSION` updated to `v4.2.14`.
- Commit `f15f2c8`: "make the C backend's ffi.call actually usable: argv, sys.*, io.*, array fns"
- `README.md` updated with v4.2.14 release notes.

Documentation Impact:
- Sync all documentation and `.md` files to `v4.2.14`.

2026-09-30 - [Update SageLang Guide for f15f2c8]

Discovery:
- Version 4.2.14 bumped.
- Added `io.filesize`, `io.isdir`, `io.remove`, `io.mkdir` to C backend.
- `sys.args`, `sys.clock`, `sys.getenv` and `sys.shell_exec` are now reachable without needing an imported module, preventing "Cannot call non-function value".
- `ffi_call` has been improved, and the C backend can be used properly.

Evidence:
- `VERSION` and `core/VERSION` updated to `v4.2.14`.
- Commit `f15f2c8`: "make the C backend's ffi.call actually usable: argv, sys.*, io.*, array fns"
- `README.md` updated with v4.2.14 release notes.

Documentation Impact:
- Sync all documentation and `.md` files to `v4.2.14`.
- Updated `core/docs/SageLang_Guide.md` with new io.* methods and notes about `ffi_call` and `sys.*` availability.
