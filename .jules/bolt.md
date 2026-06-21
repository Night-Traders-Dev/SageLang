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

## 2025-05-30 - [Native Aggregate Optimization]
**Learning:** Interpreted loops for basic arithmetic aggregations (sum, product) are a major bottleneck. Implementing these in C and providing a Sage-side fallback achieves ~25x speedup for 1M elements.
**Action:** Move hot-path array aggregations to native C built-ins. Always provide a `nil` fallback check in Sage to maintain robustness for non-numeric arrays.

## 2025-05-27 - [Optimized JSON ParseWithLength]
**Learning:** Manual character-by-character string building in SageLang for creating substrings has O(N^2) complexity. Using the native `slice()` builtin offloads the operation to the C-level VM, resulting in a ~4000x speedup for 100k character strings.
**Action:** Replace manual loop-based substring creation with native `slice()` whenever a buffer_length or range is specified.

## 2025-05-28 - [Optimized Dictionary Size Lookup]
**Learning:** `dicts.size(d)` was implemented as `len(dict_keys(d))`, which had O(N) complexity because `dict_keys` allocates and populates a new array with all keys. The native `len(d)` builtin already supports dictionaries and returns the count in O(1).
**Action:** Use native `len()` for dictionary size checks. Verified a ~250x-600x speedup in benchmarks.

## 2025-05-29 - [Interpreter Loop Performance Pattern]
**Learning:** In the SageLang interpreter, 'for item in values' loops are significantly more efficient than 'while' loops using manual indexing (e.g., 'values[i]'). Baseline benchmarks for 10,000 elements showed 'contains' (using 'for') at ~0.09s vs 'index_of' (using 'while') at ~0.41s.
**Action:** Prefer 'for' loops for array iteration in SageLang whenever possible. For high-frequency search operations, implement as native C built-ins to bypass VM overhead entirely.

## 2026-06-10 - [Optimized Array Chunking]
**Learning:** Manual element-by-element chunking in SageLang is significantly slower than using the native `slice()` builtin. Slicing offloads the memory copying to C's `memcpy`, whereas manual loops incur high VM overhead for every element.
**Action:** Always use `slice()` for extracting contiguous sub-segments of arrays or strings. Measured an ~8x speedup (1.5s to 0.19s) for chunking operations.

## 2026-06-12 - [Optimized Native Min/Max Aggregation]
**Learning:** Interpreted `for` loops in SageLang for finding minimum and maximum values in large arrays are a major bottleneck (~0.1s - 0.3s for 1M elements). Implementing these as native C built-ins bypasses VM overhead, achieving ~50x-100x speedups (~0.002s for 1M elements).
**Action:** Move hot-path array aggregations (min, max, sum, product) to native C built-ins. Use a pattern of returning `nil` from C on encountering unsupported/mixed types to safely trigger a robust SageLang fallback.

## 2026-06-16 - [O(1) String Length Optimization]
**Learning:** SageLang's string length retrieval via `strlen()` was O(N), causing significant performance degradation for large strings in loops, concatenation, and slicing. Since all Sage strings are GC-managed and their allocation size is stored in the `GCHeader`, the length is already known at O(1).
**Action:** Use the `SAGE_STRING_LEN(v)` macro to retrieve cached length from the GC header. Applied this optimization across the interpreter, standard library native functions, and the C backend runtime prelude, achieving up to ~267x speedup for large strings.

## 2026-06-20 - [Optimized JSON Array/Object Operations]
**Learning:** SageLang's  port used a naive linked-list implementation for arrays and objects, making size checks and appends (N)$. Adding  and  metadata to the node structure allows (1)$ operations while maintaining compatibility through a lazy reconstruction helper ().
**Action:** Use cached metadata for linked-list based collections to avoid (N)$ traversals. Measured a ~178x speedup (12.3s to 0.069s) for 8000-element array creation.

## 2026-06-20 - [Optimized JSON Array/Object Operations]
**Learning:** SageLang's `cJSON` port used a naive linked-list implementation for arrays and objects, making size checks and appends O(N). Adding `count` and `last_child` metadata to the node structure allows O(1) operations while maintaining compatibility through a lazy reconstruction helper (`_cJSON_EnsureMetadata`).
**Action:** Use cached metadata for linked-list based collections to avoid O(N) traversals. Measured a ~178x speedup (12.3s to 0.069s) for 8000-element array creation.

## 2026-06-21 - [Optimized Loop Performance Pattern]
**Learning:** In the SageLang interpreter, 'for' loops (either 'for item in collection' or 'for i in range(n)') are significantly more efficient than 'while' loops with manual index management. Benchmarks showed 'for item in arr' is ~2.7x faster than 'while i < len(arr)', and 'for i in range(n)' is ~1.7x faster than 'while i < n'.
**Action:** Prefer 'for' loops for all iteration tasks in library code. Use 'for i in range(limit)' for indexed loops and 'for i in range(start, stop, step)' for complex progressions to leverage the VM's optimized iteration path.
