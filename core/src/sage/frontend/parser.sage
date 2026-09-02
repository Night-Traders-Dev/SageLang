// ============================================================================
# Frontend Parser - Syntax analysis
# ============================================================================
// Part of the Frontend concern: parsing and semantic analysis
// Produces AST for diagnostics, tooling, and reference execution
// ============================================================================

import ast
import token

// Parser state
class Parser {
    let tokens: List<Token>
    let position: Int
    let errors: List<Diagnostic>
    let ast: Option<AST_Module>
}

// Create a new parser
proc parser_new(tokens: List<Token>): Parser = Parser(
    tokens: tokens,
    position: 0,
    errors: [],
    ast: None
)

// Run the parser
proc parser_run(parser: Parser): AST_Module =
    // Parse module
    let module = parser_parse_module(parser)
    parser.ast = Some(module)
    return module

// Current token
proc parser_peek(parser: Parser): Token =
    if parser.position < len(parser.tokens):
        return parser.tokens[parser.position]
    return Token(TOKEN_EOF, "", 0, 0)

// Advance parser
proc parser_advance(parser: Parser): Token =
    let tok = parser_peek(parser)
    parser.position = parser.position + 1
    return tok

// Parse a module
proc parser_parse_module(parser: Parser): AST_Module =
    let statements = []
    while parser_peek(parser).kind != TOKEN_EOF:
        let stmt = parser_parse_statement(parser)
        if stmt != None:
            statements = statements.push(stmt)
    return AST_Module(statements: statements)

// Parse a statement
proc parser_parse_statement(parser: Parser): Option<AST_Stmt> =
    let tok = parser_peek(parser)
    match tok.kind:
        TOKEN_LET:
            return Some(parser_parse_let(parser))
        TOKEN_IF:
            return Some(parser_parse_if(parser))
        TOKEN_WHILE:
            return Some(parser_parse_while(parser))
        TOKEN_FOR:
            return Some(parser_parse_for(parser))
        TOKEN_PROC:
            return Some(parser_parse_proc(parser))
        TOKEN_CLASS:
            return Some(parser_parse_class(parser))
        TOKEN_IMPORT:
            return Some(parser_parse_import(parser))
        TOKEN_RETURN:
            return Some(parser_parse_return(parser))
        TOKEN_BREAK:
            return Some(parser_parse_break(parser))
        TOKEN_CONTINUE:
            return Some(parser_parse_continue(parser))
        TOKEN_TRY:
            return Some(parser_parse_try(parser))
        TOKEN_DEFER:
            return Some(parser_parse_defer(parser))
        TOKEN_MATCH:
            return Some(parser_parse_match(parser))
        TOKEN_STRUCT:
            return Some(parser_parse_struct(parser))
        TOKEN_ENUM:
            return Some(parser_parse_enum(parser))
        TOKEN_TRAIT:
            return Some(parser_parse_trait(parser))
        TOKEN_COMPTIME:
            return Some(parser_parse_comptime(parser))
        TOKEN_MACRO:
            return Some(parser_parse_macro(parser))
        _:
            // Expression statement
            let expr = parser_parse_expression(parser)
            return Some(AST_Stmt(STMT_EXPRESSION, expr: expr))

// Parse expressions with precedence
proc parser_parse_expression(parser: Parser): AST_Expr =
    return parser_parse_binary(parser, 0)

// Binary operator precedence parsing
proc parser_parse_binary(parser: Parser, min_prec: Int): AST_Expr =
    let lhs = parser_parse_unary(parser)
    while true:
        let tok = parser_peek(parser)
        let prec = get_operator_precedence(tok.kind)
        if prec < min_prec:
            break
        parser_advance(parser)
        let rhs = parser_parse_binary(parser, prec + 1)
        lhs = AST_Expr(EXPR_BINARY, lhs: lhs, rhs: rhs, op: tok.kind)
    return lhs

// Parse unary expressions
proc parser_parse_unary(parser: Parser): AST_Expr =
    let tok = parser_peek(parser)
    if tok.kind in [TOKEN_NOT, TOKEN_TILDE, TOKEN_MINUS, TOKEN_AMP]:
        parser_advance(parser)
        let expr = parser_parse_unary(parser)
        return AST_Expr(EXPR_UNARY, operand: expr, op: tok.kind)
    return parser_parse_primary(parser)

// Parse primary expressions
proc parser_parse_primary(parser: Parser): AST_Expr =
    let tok = parser_peek(parser)
    match tok.kind:
        TOKEN_NUMBER:
            parser_advance(parser)
            return AST_Expr(EXPR_NUMBER, value: tok.value)
        TOKEN_STRING:
            parser_advance(parser)
            return AST_Expr(EXPR_STRING, value: tok.value)
        TOKEN_BOOL:
            parser_advance(parser)
            return AST_Expr(EXPR_BOOL, value: tok.value)
        TOKEN_NIL:
            parser_advance(parser)
            return AST_Expr(EXPR_NIL)
        TOKEN_IDENT:
            return parser_parse_ident(parser)
        TOKEN_LPAREN:
            return parser_parse_group(parser)
        TOKEN_LBRACKET:
            return parser_parse_array(parser)
        TOKEN_LBRACE:
            return parser_parse_dict(parser)
        _:
            parser_error(parser, "Unexpected token: " + tok.kind)
            parser_advance(parser)
            return AST_Expr(EXPR_NIL)

// Parse identifier (variable, function call, etc.)
proc parser_parse_ident(parser: Parser): AST_Expr =
    let tok = parser_peek(parser)
    let name = tok.value
    parser_advance(parser)
    
    let next = parser_peek(parser)
    if next.kind == TOKEN_LPAREN:
        // Function call
        return parser_parse_call(parser, name)
    if next.kind == TOKEN_DOT:
        // Property access
        return parser_parse_property(parser, name)
    if next.kind == TOKEN_LBRACKET:
        // Index access
        return parser_parse_index(parser, name)
    
    // Simple variable reference
    return AST_Expr(EXPR_VARIABLE, name: name)

// Parse function call
proc parser_parse_call(parser: Parser, name: String): AST_Expr =
    parser_advance(parser)  // consume '('
    let args = []
    let kwargs = []
    while parser_peek(parser).kind != TOKEN_RPAREN:
        let arg = parser_parse_expression(parser)
        // Check for keyword argument
        if parser_peek(parser).kind == TOKEN_COLON:
            parser_advance(parser)
            let kw_name = name
            let kw_value = parser_parse_expression(parser)
            kwargs = kwargs.push((kw_name, kw_value))
        else:
            args = args.push(arg)
        if parser_peek(parser).kind == TOKEN_COMMA:
            parser_advance(parser)
    parser_advance(parser)  // consume ')'
    return AST_Expr(EXPR_CALL, name: name, args: args, kwargs: kwargs)

// Error reporting
proc parser_error(parser: Parser, msg: String): Unit =
    let tok = parser_peek(parser)
    parser.errors = parser.errors.push(Diagnostic(
        level: "error",
        message: msg,
        location: SourceLocation(
            file: "<input>",
            line: tok.line,
            column: tok.column,
            length: len(tok.value)
        )
    ))

// Get diagnostics
proc parser_get_diagnostics(parser: Parser): List<Diagnostic> = parser.errors
