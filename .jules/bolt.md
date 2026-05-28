## 2025-05-15 - [Optimized Property Access]
**Learning:** The interpreter was performing expensive `SAGE_ALLOC`, `strncpy`, and `free` operations for every property access because it needed a null-terminated string for dictionary lookups, even though the `Token` already contained the start pointer and length.
**Action:** Implement and use length-aware dictionary and instance field lookup functions (`dict_get_len`, `instance_get_field`, etc.) to allow direct lookups using `Token` data without temporary allocations.

## 2025-05-15 - [JSON String Handling Optimization]
**Learning:** Manual character-by-character string building in SageLang (e.g., `result = result + c`) has quadratic complexity due to string immutability. Chaining native `replace()` and using `slice()` for bulk copies significantly outperforms manual loops.
**Action:** Always prefer `slice()` for substrings and native `replace()` or `join()` over manual concatenation loops in performance-critical code.

## 2025-05-15 - [Dictionary Key Type Constraints]
**Learning:** SageLang dictionaries only support string keys. Non-string keys result in a "Runtime Error: Invalid index assignment". This necessitates converting other types to strings for deduplication or lookup tasks.
**Action:** When using dictionaries for deduplication of arbitrary values, use `str(item) + type(item)` as the key to ensure uniqueness across types while adhering to the string-key-only constraint.

## 2025-05-26 - [Optimized Array Take/Drop]
**Learning:** Interpreted loops for array subset operations (`take` and `drop`) are significantly slower than native `slice()` calls because they incur per-iteration interpreter overhead and multiple `push()` calls.
**Action:** Use native `slice()` for all array and string subset operations in library code. Added @inline hints to help compiled backends.

## 2025-05-27 - [Optimized JSON ParseWithLength]
**Learning:** Manual character-by-character string building in SageLang for creating substrings has O(N^2) complexity. Using the native `slice()` builtin offloads the operation to the C-level VM, resulting in a ~4000x speedup for 100k character strings.
**Action:** Replace manual loop-based substring creation with native `slice()` whenever a buffer_length or range is specified.
