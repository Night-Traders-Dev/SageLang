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
