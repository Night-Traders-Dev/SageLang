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
