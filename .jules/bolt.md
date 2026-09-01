## 2026-08-30 - [Optimized Rich Panel Component Operations]
**Learning:** Manual string repetition loops in `Panel._repeat_char` and string concatenation loops for assembling rendered output lines in `Panel.render` (`core/lib/rich/panel.sage`) introduce unnecessary $O(N^2)$ VM overhead. Replacing manual character loops with `string_repeat` VM built-in calls and `join(lines, chr(10))` offloads string assembly to native C code, resulting in faster UI rendering.
**Action:** Always delegate character repetition to `string_repeat` and multi-line string assembly to `join(lines, chr(10))` in TUI components.

## 2026-08-25 - [Optimized Rich Text Component Operations]
**Learning:** Manual character-by-character loops inside `segment_split`, `Text.stylize`, `Text.plain`, `Text.render`, `Text.split_lines`, `Text.wrap`, `Text.render_wrapped`, and `Text.truncate` in `core/lib/rich/text.sage` cause $O(N^2)$ interpreter overhead due to repeated string allocation and manual index management. Replacing manual loops with native `slice()` and array `push` + `join("")` patterns offloads string slicing and assembly to C native built-ins. Always avoid parameter names (like `style`) that shadow imported module names (like `style`) inside library modules.
**Action:** Use native `slice()` for contiguous string/array extractions and array `push` + `join("")` for multi-part string assembly in `rich` TUI components. Ensure procedure parameter names do not shadow imported module namespaces.

## 2026-08-13 - [Optimized React Rendering with Component Memoization]
**Learning:** Re-rendering static JSX elements (such as header or footer text boxes) on every keystroke within a React app causes unnecessary virtual DOM reconstruction and diffing. Wrapping these elements with `React.memo` keeps keypress responses fast and lightweight. Additionally, pre-computing string formats (such as `.toLocaleString()`) outside render loops avoids expensive operations in the hot path.
**Action:** Extract large static blocks of markup into separate components and wrap them in `memo` to avoid re-render overhead. Lift any immutable computations or format transformations out of render loops as module-level constants.

## 2026-07-12 - [O(N) Direct Pointer Copy for Path Joins]
**Learning:** Naively constructing paths or joining string buffers using `strcat` in a loop has $O(N^2)$ complexity due to repeated traversals to find the string's end. Converting this to a cursor-tracked buffer with direct `memcpy` reduces the complexity to $O(N)$.
**Action:** Always construct multi-segment strings by maintaining a running pointer offset and copying segments directly with `memcpy` instead of calling `strcat` or `strlen` repeatedly.

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
**Learning:** SageLang's `cJSON` port used a naive linked-list implementation for arrays and objects, making size checks and appends O(N). Adding `count` and `last_child` metadata to the node structure allows O(1) operations while maintaining compatibility through a lazy reconstruction helper (`_cJSON_EnsureMetadata`).
**Action:** Use cached metadata for linked-list based collections to avoid O(N) traversals. Measured a ~178x speedup (12.3s to 0.069s) for 8000-element array creation.

## 2026-06-21 - [Optimized Loop Performance Pattern]
**Learning:** In the SageLang interpreter, 'for' loops (either 'for item in collection' or 'for i in range(n)') are significantly more efficient than 'while' loops with manual index management. Benchmarks showed 'for item in arr' is ~2.7x faster than 'while i < len(arr)', and 'for i in range(n)' is ~1.7x faster than 'while i < n'.
**Action:** Prefer 'for' loops for all iteration tasks in library code. Use 'for i in range(limit)' for indexed loops and 'for i in range(start, stop, step)' for complex progressions to leverage the VM's optimized iteration path.

## 2026-06-25 - [Optimized Crypto Encodings]
**Learning:** String concatenation using '+=' in SageLang has O(N^2) complexity due to string immutability. Replacing this with an array-push and join("") pattern achieves O(N) complexity and significant performance gains. Additionally, leveraging the native 'replace()' builtin for character translation is much faster than manual interpreted loops.
**Action:** Use array-push + join("") for building large strings in loops. Use native 'replace()' for bulk string substitutions. Measured ~100x-130x speedup for 10k byte encoding.

## 2025-05-30 - [Generator Yield-in-For Anti-pattern]
**Learning:** In SageLang v3.9.9, using 'yield' inside a 'for' loop does not correctly advance the loop state, causing it to repeatedly yield the first element.
**Action:** Always use 'while' loops with manual index management in generator procedures until the interpreter bug is resolved.

## 2025-06-03 - [Optimized URL Parsing and Encoding]
**Learning:** String concatenation using '+=' in SageLang has O(N^2) complexity. URL utilities like `encode`, `decode`, `build`, and `build_query` were suffering from this. Additionally, manual character-by-character loops for extracting substrings are much slower than the native `slice()` builtin.
**Action:** Replace string concatenation loops with array-push + `join("")` patterns. Use native `slice()` for all substring extraction. Replace linear scans for safe characters with O(1) dictionary lookups. Measured speedups: Encoding (~37x), Decoding (~8x), and Parsing (~3100x).

## 2026-06-28 - [Optimized Flat Environment Cache]
**Learning:** In the SageLang interpreter, manual index `while` loops (e.g. `while i < len(arr)`) are significantly slower (~2.7x) than native element-based `for` loops. The performance utility library `core/lib/perf.sage` was doing manual `while` loops inside the crucial environment snapshot and flush handlers (`flat_cache_snapshot` and `flat_cache_flush`), causing unnecessary VM overhead in hot loops.
**Action:** Replace manual `while` indexing with native `for` loops inside standard library performance-critical procedures to leverage the VM's optimized iteration path. This also completely eliminates name shadowing warnings.

## 2026-07-20 - [O(1) String-to-Bytes Length-Aware Native Allocation]
**Learning:** Initializing the native `Bytes` value with a Sage `VAL_STRING` used to compute the string length via `strlen(s)`, which is O(N) complexity. Since all SageLang strings are GC-managed and track their allocation size in the `GCHeader`, the length is already pre-computed.
**Action:** Always prefer the O(1) length-aware `SAGE_STRING_LEN(args[0])` macro over an O(N) `strlen(s)` call in native interpreter functions handling Sage string values to eliminate linear overhead.

## 2026-07-21 - [Optimizing Binary Conversion Loop]
**Learning:** Index-based `while` loops in the SageLang VM incur significant interpreter overhead because index increments and condition evaluations occur in the interpreted VM space. Replacing a `while` loop with a range-based `for` loop (e.g., `for i in range(start, end)`) offloads the loop state management and increment logic to the VM's native C implementation.
**Action:** Always prefer range-based `for` loops (`for i in range(...)`) over index-based `while` loops in standard library performance paths to yield ~1.7x speedups.

## 2026-07-22 - [Optimized Key Generation in Array Deduplication]
**Learning:** Using `str(item) + type(item)` as a key inside `unique(values)` array deduplication helper is expensive because calling native `str()` and performing string concatenation on string types creates unnecessary allocations and string copy overhead in the interpreter.
**Action:** By checking if `type(item) == "string"` first and directly using `item` as the key (bypassing `str()` and concatenation), we yield a major ~40% speedup.

## 2026-08-14 - [Optimized Rich Text Measurement Utilities]
**Learning:** Checking for special characters (`chr(27)` / ANSI escape codes) using `contains(text, chr(27))` enables a zero-allocation early return path for plain strings in text measurement utilities (`strip_ansi`, `measure_text`). For strings with ANSI codes, replacing O(N^2) character-by-character string concatenation with array-push, `slice()`, and `join("")` patterns avoids quadratic string allocation overhead. Furthermore, replacing manual character loops with `string_repeat` for string padding (`pad_right_to_width`, `pad_left_to_width`, `center_text`) offloads repetitive character assembly to C native code.
**Action:** Always add early exits for fast paths when common inputs don't require heavy processing (e.g., plain strings without escape codes). Use `string_repeat` for character repetition and array `push` + `join("")` with `slice()` for multi-segment string assembly.

## 2026-08-22 - [Optimized Standard Library String Formatting]
**Learning:** Manual character-by-character loops inside `pad_left`, `pad_right`, `repeat_char`, `template`, `format_int`, and `table` in `core/lib/std/fmt.sage` cause $O(N^2)$ interpreter overhead due to string immutability and repeated allocation. Replacing manual character loops with native C VM built-ins (`string_repeat`, `slice()`, `indexof()`) and array assembly offloads execution to native code, achieving up to ~19.4x faster padding and ~12.7x faster character repetition. Note that within module scope, unqualified procedure calls resolve to module procedure declarations before global VM built-ins.
**Action:** Use native C VM built-ins (`string_repeat`, `slice()`, `indexof()`) for string assembly and manipulations in standard library code. Be aware of module namespace resolution when calling built-in functions with names matching module procedures.

## 2026-09-02 - [Optimized Standard Library String Padding]
**Learning:** Re-evaluating `len(text)` multiple times in string padding procedures (`pad_left`, `pad_right` in `core/lib/strings.sage`) creates redundant VM evaluation overhead. Caching `text_len = len(text)` and marking procedures with `@inline` eliminates redundant length calls and procedure call frame setup for compiled backends, speeding up hot-path string formatting.
**Action:** Cache collection/string lengths in local variables when referenced multiple times in procedure bodies, and apply `@inline` annotations to small utility procedures.
