# Developer Tooling Guide

SageLang ships a complete developer tooling ecosystem: an interactive REPL, code
formatter, linter, syntax highlighting, and a Language Server Protocol (LSP)
server.

## REPL

Launch with `sage` (no args) or `sage --repl`. Supports multi-line blocks
(automatic continuation for indented `if`/`while`/`proc`/`class`), error
recovery without exiting the session, and the following commands:

| Command | Meaning |
| ------- | ------- |
| `:help` | Print REPL help |
| `:quit` / `:exit` | Leave the session (also Ctrl-D) |
| `:reset` | Reset the session, global bindings, and module cache |
| `:clear` | Clear the terminal screen |
| `:history [n]` | Show last n history entries (default: 20) |
| `:save <file>` | Save session history to a Sage source file |
| `:vars [prefix]` | List current REPL bindings, optionally filtered by prefix |
| `:type <expr>` | Evaluate an expression and print its runtime type and value |
| `:ast <code>` | Show parsed AST for an expression or statement |
| `:env` | Show the full scope chain with parent environments |
| `:modules` | List loaded modules and search paths |
| `:doc <name>` | Show documentation for builtins, keywords, or user-defined functions (via docstrings) |
| `:edit [file]` | Open an external editor to compose code and execute it in the session |
| `:ls [dir]` | List directory contents from the REPL |
| `:cat <file>` | Print a file from the REPL |
| `:sh <command>` | Run a shell command from the REPL |
| `:search <pattern>` | Search command history |
| `:clear-history` | Clear command history |
| `:emit-c <code>` | Show C backend output for a statement |
| `:emit-llvm <code>` | Show LLVM IR output for a statement |
| `:emit-kotlin <code>` | Show Kotlin transpiler output |
| `:stats` | Show GC stats, stack depth, and CPU time |
| `:time <expr>` | Time a single expression evaluation |
| `:bench <n> <expr>` | Run expression n times, show min/avg/max |
| `:load <file>` | Execute a Sage file inside the current session |
| `:pwd` | Print the current working directory |
| `:cd <dir>` | Change the working directory |
| `:gc` | Run garbage collection and print GC statistics |
| `:runtime [mode]` | Show or switch runtime (ast, bytecode, auto) |

REPL path validation is hardened — commands like `:ls`/`:cat` reject leading
dashes to prevent injection.

## Code Formatter

- `sage fmt <file>` — Format a Sage source file in place (prints `Formatted: <file>` on success)
- `sage fmt --check <file>` — Check formatting without rewriting (exit code `1` when formatting is needed)

Normalizes indentation, spacing, and blank lines for consistent style.

## Linter

`sage lint <file>` — Static analysis with 13 rules across three categories:

- **Errors (E001–E003)** — Syntax and structural errors
- **Warnings (W001–W005)** — Potential bugs and bad practices
- **Style (S001–S005)** — Code style and naming conventions (e.g. S003 missing docstring, S005 multiple statements per line)

Reports file, line, rule code, and message for each finding. Exit code `1` when
issues are found.

## Syntax Highlighting

- **TextMate grammar** — `editors/sage.tmLanguage.json` for any TextMate-compatible editor
- **VSCode extension** — `editors/vscode/` with language configuration and theme support

## Language Server Protocol (LSP)

- `sage --lsp` — LSP server on stdin/stdout (integrated into the main `sage` binary)
- `sage-lsp` — Standalone LSP server binary for editor integration

Features:

- **Diagnostics** — Real-time error and warning reporting on save
- **Completion** — Keyword and symbol completions
- **Hover** — Type information and documentation on hover, including user-defined
  procedures (docstrings extracted from the environment via the shared
  `g_hover_docs` source of truth in `diagnostic.c`)
- **Formatting** — Format-on-save via `textDocument/formatting`
