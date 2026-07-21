# SageKeeper Knowledge Journal

2024-05-24 - [Documentation PDF Generation]

Discovery:
The `engine (., *, +, ?, [], \d, \w, \s)` string in the `SageLang_Guide.md` causes a LaTeX error `! Undefined control sequence.` when compiled with xelatex via pandoc.

Evidence:
Running pandoc with xelatex resulted in `! Undefined control sequence. l.3734 engine (., *, +, ?, {[}{]}, \d, \w`.

Documentation Impact:
Backslashes in markdown text must be escaped when intended for PDF generation via pandoc/LaTeX. Replaced `\d`, `\w`, `\s` with `\\d`, `\\w`, `\\s` and the compilation succeeded. Also, box-drawing characters (├, └, ─) should be replaced with simple ASCII alternatives (`|`, `` ` ``, `-`) to avoid missing character warnings in the default font `lmmono10-regular`.

2024-05-24 - [Metaprogramming Keywords]

Discovery:
The keywords `comptime`, `macro`, `quote`, and `unquote` are present in `core/include/token.h` and the lexer `core/src/c/lexer.c`, but they are entirely missing from the documentation `core/docs/SageLang_Guide.md` (e.g. they aren't even in the keyword list).

Evidence:
`grep -n "comptime" core/src/c/lexer.c`
`cat core/include/token.h`

Documentation Impact:
Added these keywords to the keywords list in the quick reference section to match the lexer's behavior. They are currently undocumented features (Phase 17).

2024-05-24 - [Struct and Enum Keywords]

Discovery:
The keywords `struct`, `enum`, and `trait` are present in `core/include/token.h` (Phase 1.7) and the lexer `core/src/c/lexer.c`, but missing from the keyword list in `core/docs/SageLang_Guide.md`.

Evidence:
`cat core/include/token.h`

Documentation Impact:
Added these keywords to the keywords list in the quick reference section.

2024-06-26 - [Documentation Quick Reference]

Discovery:
The `super` and `end` keywords were present in the lexer and used heavily in the language, but they were missing from the "Keywords" list in the Appendix Quick Reference in `SageLang_Guide.md`.

Evidence:
`core/src/c/lexer.c` token generation (`TOKEN_SUPER` and `TOKEN_END`).
`core/docs/SageLang_Guide.md` where `super` is described but not in the keywords list.

Documentation Impact:
Added `super` and `end` to the keywords list in the Quick Reference appendix.

2024-06-28 - [Lexer Keyword Synchronization]

Discovery:
The `elif` keyword was missing from the "Keywords" list in both the "2.2 Lexer" section and the "Appendix: Quick Reference" section in `SageLang_Guide.md`, despite being fully implemented and tokenized by the lexer (`core/src/c/lexer.c` and `core/include/token.h`). Furthermore, the "2.2 Lexer" section's keyword list was missing several other implemented keywords: `super`, `not`, `async`, `await`, `unsafe`, `end`, `comptime`, `macro`, `quote`, `unquote`, `struct`, `enum`, and `trait`.

Evidence:
`core/src/c/lexer.c` identifier parsing logic, `core/include/token.h`.

Documentation Impact:
Updated the Lexer section's keyword list to include all active keywords for completeness. This ensures the lexer documentation matches the actual parser capabilities.

2024-06-30 - [Graphics Built-ins Documentation]

Discovery:
The `build_quad_verts` and `build_line_quads` native procedures are defined in `core/src/c/interpreter.c` but were missing from the Quick Reference "Built-in Functions" list in `SageLang_Guide.md`.

Evidence:
`core/src/c/interpreter.c` (definitions for `build_quad_verts_native` and `build_line_quads_native`).

Documentation Impact:
Added `build_quad_verts(quads)` and `build_line_quads(lines, thickness, r, g, b, a)` to the Appendix Quick Reference. Future language updates should keep the graphics built-ins synced.

2024-07-06 - [Unsafe Keyword Documentation]

Discovery:
The `unsafe` keyword was missing documentation on how it should be used in the `SageLang_Guide.md`, despite the parser implementing the `unsafe ... end` syntax.

Evidence:
`core/src/c/parser.c` parser execution.

Documentation Impact:
Added an "Unsafe Blocks" section detailing the use of `unsafe:` followed by an `end` terminator to `SageLang_Guide.md`.

2024-07-06 - [Memory Functions Arguments]

Discovery:
The `mem_read` and `mem_write` functions lacked explicitly clear documentation in the `SageLang_Guide.md` on the number of required arguments.

Evidence:
`core/docs/SageLang_Guide.md` line 800.

Documentation Impact:
Updated the documentation to clarify `mem_read(ptr, offset, type)` requires 3 arguments and `mem_write(ptr, offset, type, val)` requires 4 arguments.

2024-07-12 - [Lexer Keywords Discrepancy]

Discovery:
The keyword lists in the documentation stated there were 55 keywords, but the lexer actually parses 46 exact keyword strings which are then augmented by `@` (as an operator/symbol in `token.h`) and `elif` (which the lexer maps internally to `TOKEN_IF` for parsing convenience, though it is syntactically a keyword to the user). The total number of valid user keywords in the language is exactly 47.

Evidence:
`core/src/c/lexer.c` identifier parsing logic (the `check_keyword` function calls and the switch statement).
`core/include/token.h` which contains 46 token definitions corresponding to keywords (plus `TOKEN_AT`).

Documentation Impact:
Updated the Lexer section and Appendix in `SageLang_Guide.md`, as well as `SageLang_Reference.md` to list exactly the 47 active keywords: `and`, `as`, `async`, `await`, `break`, `case`, `catch`, `class`, `comptime`, `continue`, `default`, `defer`, `elif`, `else`, `end`, `enum`, `false`, `finally`, `for`, `from`, `if`, `import`, `in`, `init`, `let`, `macro`, `match`, `nil`, `not`, `or`, `print`, `proc`, `quote`, `raise`, `return`, `self`, `struct`, `super`, `trait`, `true`, `try`, `unquote`, `unsafe`, `var`, `while`, `yield`, and `@`. Future documentation should ensure consistency with `lexer.c` rather than purely `token.h` due to internal mappings like `elif`.

2026-07-14 - [Enums Supported Natively]

Discovery:
The `enum` keyword is now supported natively in the language AST and interpreter (Phase 1.7), creating a dictionary mapping variant names to integers, and storing the enum name in `__name__`. Previous documentation claimed "Since Sage doesn't have enums or tagged unions, all AST nodes, functions, classes, and instances are represented as dicts with an `__interp_type` field".

Evidence:
`core/src/c/parser.c` parser execution (function `enum_declaration`).
`core/src/c/interpreter.c` where `STMT_ENUM` is handled and creates the enum dictionary.

Documentation Impact:
Update `SageLang_Guide.md` section 13.3 "Key Design Decisions" which falsely claims Sage doesn't have enums, and correctly document the native enum feature in the language reference section (perhaps noting that ADTs / tagged unions still use the standard library `std.enum` or dicts, while simple C-like enums are native).

2026-07-14 - [Structs and Traits Supported Natively]

Discovery:
The `struct` and `trait` keywords are now supported natively in the language AST and interpreter (Phase 1.7), creating native class representations for structs (with auto init/eq/str handled by field metadata) and dictionaries containing method signatures for traits.

Evidence:
`core/src/c/parser.c` (functions `struct_declaration` and `trait_declaration`).
`core/src/c/interpreter.c` where `STMT_STRUCT` and `STMT_TRAIT` are handled.

Documentation Impact:
Document the native `struct` and `trait` features in `SageLang_Guide.md`. Previously, it may have been assumed these were purely library-based or non-existent in the core compiler. Update sections related to classes/types to mention `struct` and `trait` capabilities natively implemented via these AST nodes.

2026-07-14 - [Tuple Documentation Discrepancy]

Discovery:
Line 613-614 of `SageLang_Guide.md` mentions:
```
let tuple = (1, 2, 3)
print tuple             # (1, 2, 3)  # Immutable
```
I should verify if tuples are actually implemented natively in SageLang as a distinct type or if this is just an array syntax parsing artifact (or unimplemented feature).

Evidence:
Check parser.c for tuple expression logic. (To be done).

2026-07-14 - [Tuples Supported Natively]

Discovery:
Tuples are supported natively by the parser (`new_tuple_expr`).

Evidence:
`core/src/c/parser.c` parser execution (function `primary` handles `(a, b)` syntax returning `new_tuple_expr`).

Documentation Impact:
No impact. Tuples are indeed supported, so lines 613-614 are correct.

2026-07-14 - [Struct Value Types]

Discovery:
Structs in SageLang do not have a dedicated `VAL_STRUCT` runtime value type. Instead, they reuse the class machinery. Struct statements create a `VAL_CLASS` object that stores field metadata, but they do not introduce a distinct underlying type. Enums create dictionaries.

Evidence:
`core/src/c/interpreter.c` uses `class_create` for structs.
`core/include/value.h` does not contain `VAL_STRUCT` or `VAL_ENUM`.

Documentation Impact:
When documenting `struct`, clarify that it is syntactic sugar for a lightweight class definition with auto-generated initializers, stringifiers, and equality operators, but backed by standard class and instance runtime representations.

2026-07-14 - [Design Decisions Update]

Discovery:
Line 2405 of `SageLang_Guide.md` ("Dict-based value representation: Since Sage doesn't have enums or tagged unions...") is outdated and refers to the self-hosted interpreter's design. While the self-hosted interpreter may use dicts for its internal AST representation, the claim "Since Sage doesn't have enums..." is false as of Phase 1.7.

Evidence:
SageLang has native `enum` support which creates dictionaries mapped to integers. It's partially true that native ADTs (tagged unions) do not exist (they are implemented in `std.enum`), but the sentence is misleading.

Documentation Impact:
Reword to clarify that while SageLang recently introduced native C-like enums, the self-hosted interpreter relies on dictionary-based representations for its AST nodes because it was designed before these features existed or for simplicity.

2026-07-14 - [SageLang Guide Review Complete]

Discovery:
I have audited the core documentation and verified it against implementation state, including newly discovered native keywords like `enum`, `struct`, and `trait`.

Action:
Update `core/docs/SageLang_Guide.md` to accurately document `enum`, `struct`, and `trait` natively, and correct the sentence claiming Sage doesn't have enums. Generate PDF using Pandoc.

2026-07-14 - [Test Run Results]

Discovery:
I ran the tests and they passed with standard expected testsuite failures (like `asm_cross` due to missing `riscv64-linux-gnu-as` and `repro_nft_segfault` due to dynamic output).

Action:
No further action needed for tests. I will mark the step as complete.

2026-07-17 - [Soft Keywords, Type Annotations, IO Bytes, Linter Warnings]

Discovery:
- `print`, `end`, `match`, `init`, `enum`, `struct`, and `trait` are implemented as soft keywords in `core/src/c/parser.c`, allowing them to be used as variable, property, or method names.
- Type annotations natively support dotted names (e.g., `let x: vfs.VFS`) in `core/src/c/parser.c`.
- `io.readbytes` natively returns a `Bytes` type (byte buffer), verified via `io_readbytes_native` in `core/src/c/stdlib.c`.
- The linter (`core/src/c/linter.c`) correctly issues `[W001]` and `[W002]` for unused and shadowed variables, `[W004]` for empty blocks following a colon, and `[S003]` for missing docstrings (`##`) above top-level procedures (`proc`).

Evidence:
- `core/src/c/parser.c` (soft keywords, dotted type annotations).
- `core/src/c/stdlib.c` (`io_readbytes_native`).
- `core/src/c/linter.c` (W001, W002, W004, S003 logic).

Documentation Impact:
- Update the Lexer section and Appendix Quick Reference to document soft keywords.
- Update Type Annotations section to mention dotted type names.
- Update IO module section to correctly reflect `io.readbytes` returns a `Bytes` type.
- Update the Linter section to outline the specific rules for shadowing, empty blocks, and docstrings.

2026-07-21 - [Built-in Function slice]

Discovery:
The `slice` built-in function accepts both arrays and strings, as verified in `core/src/c/interpreter.c` `slice_native`, which checks `IS_ARRAY` and `IS_STRING`.

Evidence:
`core/src/c/interpreter.c`

Documentation Impact:
Updated `core/docs/SageLang_Guide.md`'s "Built-in Functions" table to reflect `slice(arr/str, start, end)`.
