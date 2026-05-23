## 2025-05-15 - [Optimized Property Access]
**Learning:** The interpreter was performing expensive `SAGE_ALLOC`, `strncpy`, and `free` operations for every property access because it needed a null-terminated string for dictionary lookups, even though the `Token` already contained the start pointer and length.
**Action:** Implement and use length-aware dictionary and instance field lookup functions (`dict_get_len`, `instance_get_field`, etc.) to allow direct lookups using `Token` data without temporary allocations.

## 2025-05-15 - [JSON String Handling Optimization]
**Learning:** Manual character-by-character string building in SageLang (e.g., `result = result + c`) has quadratic complexity due to string immutability. Chaining native `replace()` and using `slice()` for bulk copies significantly outperforms manual loops.
**Action:** Always prefer `slice()` for substrings and native `replace()` or `join()` over manual concatenation loops in performance-critical code.
