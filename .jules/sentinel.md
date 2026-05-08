## 2025-05-22 - Predictable Temporary Filenames in /tmp
**Vulnerability:** Use of `snprintf` with `getpid()` to create temporary files in `/tmp/` (CWE-377).
**Learning:** This pattern is susceptible to race conditions and symlink attacks because PIDs are predictable and recycled. Even if the file is unlinked later, an attacker can create a symlink at the predicted path to cause the application to write to an arbitrary file.
**Prevention:** Always use `mkstemp()` or `mkstemps()` (if a suffix is needed). These functions securely create and open a unique file with `O_EXCL` and restrictive permissions. Ensure the template ends with `XXXXXX` and the file descriptor is closed if not immediately needed.
