// ============================================================================
# Frontend Lexer - Lexical analysis
# ============================================================================
// Part of the Frontend concern: parsing and semantic analysis
// ============================================================================

import token

// Lexer state
class Lexer {
    let source: String
    let position: Int
    let line: Int
    let column: Int
    let tokens: List<Token>
    let errors: List<Diagnostic>
}

// Create a new lexer
proc lexer_new(source: String): Lexer = Lexer(
    source: source,
    position: 0,
    line: 1,
    column: 1,
    tokens: [],
    errors: []
)

// Lexer interface - returns tokens
proc lexer_run(lexer: Lexer): List<Token> =
    while not lexer_is_eof(lexer):
        let tok = lexer_next_token(lexer)
        lexer.tokens = lexer.tokens.push(tok)
    return lexer.tokens

// Check if at end of source
proc lexer_is_eof(lexer: Lexer): Bool =
    lexer.position >= len(lexer.source)

// Get current character
proc lexer_peek(lexer: Lexer): Option<Char> =
    if lexer_is_eof(lexer):
        return None
    return Some(lexer.source[lexer.position])

// Advance position
proc lexer_advance(lexer: Lexer): Unit =
    if lexer_is_eof(lexer):
        return
    let ch = lexer.source[lexer.position]
    if ch == '\n':
        lexer.line = lexer.line + 1
        lexer.column = 1
    else:
        lexer.column = lexer.column + 1
    lexer.position = lexer.position + 1

// Get next token (simplified - real implementation would be more complex)
proc lexer_next_token(lexer: Lexer): Token =
    // Skip whitespace
    while not lexer_is_eof(lexer):
        let ch = lexer_peek(lexer)
        if ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n':
            lexer_advance(lexer)
        else:
            break
    
    if lexer_is_eof(lexer):
        return Token(TOKEN_EOF, "", lexer.line, lexer.column)
    
    // Handle identifiers, keywords, numbers, strings, operators
    // ... full implementation in existing lexer.sage
    // This module provides the interface definition
    
    // For now, delegate to existing implementation
    return token.lex_next(lexer.source, lexer.position)

// Diagnostics during lexing
proc lexer_error(lexer: Lexer, msg: String): Unit =
    lexer.errors = lexer.errors.push(Diagnostic(
        level: "error",
        message: msg,
        location: SourceLocation(
            file: "<input>",
            line: lexer.line,
            column: lexer.column,
            length: 1
        )
    ))

proc lexer_warning(lexer: Lexer, msg: String): Unit =
    lexer.errors = lexer.errors.push(Diagnostic(
        level: "warning",
        message: msg,
        location: SourceLocation(
            file: "<input>",
            line: lexer.line,
            column: lexer.column,
            length: 1
        )
    ))

// Get diagnostics
proc lexer_get_diagnostics(lexer: Lexer): List<Diagnostic> = lexer.errors
