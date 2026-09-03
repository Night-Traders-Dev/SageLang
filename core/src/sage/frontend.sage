# ============================================================================
# Frontend Facade - Unified frontend interface
# ============================================================================
# Provides unified interface for lexing, parsing, and semantic analysis
# ============================================================================

import frontend.lexer as lexer
import frontend.parser as parser
import frontend.resolver as resolver
import frontend.diagnostics as diagnostics
import ast

# Parse source code into AST with full diagnostics
proc parse_source(source: String, filename: String): ParseResult =
    // 1. Lex
    let lexer_state = lexer.lexer_new(source)
    let tokens = lexer.lexer_run(lexer_state)
    let lex_diagnostics = lexer.lexer_get_diagnostics(lexer_state)
    
    // 2. Parse
    let parse_result = parser.parse(tokens, filename)
    let ast = parse_result.ast
    let parse_diagnostics = parse_result.diagnostics
    
    // 3. Resolve (semantic analysis)
    let resolver_state = resolver.resolver_new(ast)
    let resolved = resolver.resolver_run(resolver_state)
    let resolve_diagnostics = resolved.diagnostics
    
    // 4. Collect all diagnostics
    let all_diagnostics = []
    all_diagnostics = all_diagnostics.concat(lex_diagnostics)
    all_diagnostics = all_diagnostics.concat(parse_diagnostics)
    all_diagnostics = all_diagnostics.concat(resolve_diagnostics)
    
    return ParseResult(
        ast: ast,
        tokens: tokens,
        resolved: resolved,
        diagnostics: all_diagnostics
    )

# Parse result container
class ParseResult {
    let ast: AST_Module
    let tokens: List<Token>
    let resolved: ResolvedModule
    let diagnostics: List<Diagnostic>
}

# Check if diagnostics contain errors
proc has_errors(diagnostics: List<Diagnostic>): Bool =
    for diag in diagnostics:
        if diag.level == diagnostics.DIAG_ERROR:
            return true
    return false

# Check if diagnostics contain warnings
proc has_warnings(diagnostics: List<Diagnostic>): Bool =
    for diag in diagnostics:
        if diag.level == diagnostics.DIAG_WARNING:
            return true
    return false

# Print diagnostics to stderr
proc print_diagnostics(diagnostics: List<Diagnostic>): Unit =
    for diag in diagnostics:
        let level_str = match diag.level:
            diagnostics.DIAG_ERROR: "error"
            diagnostics.DIAG_WARNING: "warning"
            diagnostics.DIAG_INFO: "info"
            diagnostics.DIAG_HINT: "hint"
        let msg = diag.location.file + ":" + diag.location.line.ToString() + ":" + 
                  diag.location.column.ToString() + ": " + level_str + ": " + diag.message
        if diag.level == diagnostics.DIAG_ERROR:
            sys.stderr_write(msg + "\n")
        else:
            print msg
        for note in diag.notes:
            let note_msg = "  note: " + note.message + " at " + 
                          note.location.file + ":" + note.location.line.ToString()
            sys.stderr_write(note_msg + "\n")