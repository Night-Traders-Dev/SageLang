## 2025-05-22 - Predictable Temporary Filenames in /tmp
**Vulnerability:** Use of `snprintf` with `getpid()` to create temporary files in `/tmp/` (CWE-377).
**Learning:** This pattern is susceptible to race conditions and symlink attacks because PIDs are predictable and recycled. Even if the file is unlinked later, an attacker can create a symlink at the predicted path to cause the application to write to an arbitrary file.
**Prevention:** Always use `mkstemp()` or `mkstemps()` (if a suffix is needed). These functions securely create and open a unique file with `O_EXCL` and restrictive permissions. Ensure the template ends with `XXXXXX` and the file descriptor is closed if not immediately needed.

## 2025-05-24 - Buffer Overflows in Compiler Code Generation
**Vulnerability:** Use of fixed-size (e.g., 4096 bytes) stack or heap buffers for concatenating generated C code in the AOT compiler.
**Learning:** Even large buffers are insufficient for compiler output where input data (like large array literals or deeply nested expressions) can cause linear or exponential growth in the generated string length. Using `sprintf` into these buffers leads to memory corruption.
**Prevention:** Always use dynamic allocation for generated output. Use `vsnprintf(NULL, 0, ...)` to pre-calculate required lengths for formatted strings, or aggregate lengths of sub-components before final allocation.

## 2026-05-25 - Shell Injection in REPL Commands
**Vulnerability:** User-provided arguments to REPL commands (:ls, :cat, :edit) were passed directly to the shell via `system()` without sanitization (CWE-78).
**Learning:** High-level REPL commands that provide convenience features (like listing files) often bypass the language's own security model. Even if the language has a safe mode, these native commands can remain vulnerable if they shell out to system utilities.
**Prevention:** Always sanitize or whitelist arguments before passing them to `system()` or similar functions. A strict whitelist of safe characters (alphanumeric, path separators, etc.) is the most robust defense against shell metacharacters.
