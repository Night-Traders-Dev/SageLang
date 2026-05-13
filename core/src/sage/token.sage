# -----------------------------------------
# token.sage - Token type constants and Token class
# Self-hosted SageLang tokenizer types
# -----------------------------------------

# Token type constants (enum equivalent)
# Keywords
let TOKEN_LET = 0
let TOKEN_VAR = 1
let TOKEN_PROC = 2
let TOKEN_IF = 3
let TOKEN_ELSE = 4
let TOKEN_WHILE = 5
let TOKEN_FOR = 6
let TOKEN_RETURN = 7
let TOKEN_PRINT = 8
let TOKEN_AND = 9
let TOKEN_OR = 10
let TOKEN_NOT = 11
let TOKEN_IN = 12
let TOKEN_BREAK = 13
let TOKEN_CONTINUE = 14
let TOKEN_CLASS = 15
let TOKEN_SELF = 16
let TOKEN_INIT = 17

# Advanced control flow
let TOKEN_MATCH = 18
let TOKEN_CASE = 19
let TOKEN_DEFAULT = 20
let TOKEN_TRY = 21
let TOKEN_CATCH = 22
let TOKEN_FINALLY = 23
let TOKEN_RAISE = 24
let TOKEN_DEFER = 25
let TOKEN_YIELD = 26
let TOKEN_ASYNC = 27
let TOKEN_AWAIT = 28

# Module system
let TOKEN_IMPORT = 29
let TOKEN_FROM = 30
let TOKEN_AS = 31

# Symbols & operators
let TOKEN_LPAREN = 32
let TOKEN_RPAREN = 33
let TOKEN_PLUS = 34
let TOKEN_MINUS = 35
let TOKEN_STAR = 36
let TOKEN_SLASH = 37
let TOKEN_PERCENT = 38
let TOKEN_ASSIGN = 39
let TOKEN_EQ = 40
let TOKEN_NEQ = 41
let TOKEN_LT = 42
let TOKEN_GT = 43
let TOKEN_LTE = 44
let TOKEN_GTE = 45
let TOKEN_COLON = 46
let TOKEN_COMMA = 47
let TOKEN_LBRACKET = 48
let TOKEN_RBRACKET = 49
let TOKEN_LBRACE = 50
let TOKEN_RBRACE = 51
let TOKEN_DOT = 52

# Bitwise operators
let TOKEN_AMP = 53
let TOKEN_PIPE = 54
let TOKEN_CARET = 55
let TOKEN_TILDE = 56
let TOKEN_LSHIFT = 57
let TOKEN_RSHIFT = 58

# Literals & identifiers
let TOKEN_IDENTIFIER = 59
let TOKEN_NUMBER = 60
let TOKEN_STRING = 61
let TOKEN_TRUE = 62
let TOKEN_FALSE = 63
let TOKEN_NIL = 64

# Block terminator
let TOKEN_END = 65

# Structural
let TOKEN_INDENT = 66
let TOKEN_DEDENT = 67
let TOKEN_NEWLINE = 68
let TOKEN_EOF = 69
let TOKEN_ERROR = 70

# Token type name lookup for debugging
proc token_type_name(t):
    if t == TOKEN_LET:
        return "LET"
    if t == TOKEN_VAR:
        return "VAR"
    if t == TOKEN_PROC:
        return "PROC"
    if t == TOKEN_IF:
        return "IF"
    if t == TOKEN_ELSE:
        return "ELSE"
    if t == TOKEN_WHILE:
        return "WHILE"
    if t == TOKEN_FOR:
        return "FOR"
    if t == TOKEN_RETURN:
        return "RETURN"
    if t == TOKEN_PRINT:
        return "PRINT"
    if t == TOKEN_AND:
        return "AND"
    if t == TOKEN_OR:
        return "OR"
    if t == TOKEN_NOT:
        return "NOT"
    if t == TOKEN_IN:
        return "IN"
    if t == TOKEN_BREAK:
        return "BREAK"
    if t == TOKEN_CONTINUE:
        return "CONTINUE"
    if t == TOKEN_CLASS:
        return "CLASS"
    if t == TOKEN_SELF:
        return "SELF"
    if t == TOKEN_INIT:
        return "INIT"
    if t == TOKEN_MATCH:
        return "MATCH"
    if t == TOKEN_CASE:
        return "CASE"
    if t == TOKEN_DEFAULT:
        return "DEFAULT"
    if t == TOKEN_TRY:
        return "TRY"
    if t == TOKEN_CATCH:
        return "CATCH"
    if t == TOKEN_FINALLY:
        return "FINALLY"
    if t == TOKEN_RAISE:
        return "RAISE"
    if t == TOKEN_DEFER:
        return "DEFER"
    if t == TOKEN_YIELD:
        return "YIELD"
    if t == TOKEN_ASYNC:
        return "ASYNC"
    if t == TOKEN_AWAIT:
        return "AWAIT"
    if t == TOKEN_IMPORT:
        return "IMPORT"
    if t == TOKEN_FROM:
        return "FROM"
    if t == TOKEN_AS:
        return "AS"
    if t == TOKEN_LPAREN:
        return "LPAREN"
    if t == TOKEN_RPAREN:
        return "RPAREN"
    if t == TOKEN_PLUS:
        return "PLUS"
    if t == TOKEN_MINUS:
        return "MINUS"
    if t == TOKEN_STAR:
        return "STAR"
    if t == TOKEN_SLASH:
        return "SLASH"
    if t == TOKEN_PERCENT:
        return "PERCENT"
    if t == TOKEN_ASSIGN:
        return "ASSIGN"
    if t == TOKEN_EQ:
        return "EQ"
    if t == TOKEN_NEQ:
        return "NEQ"
    if t == TOKEN_LT:
        return "LT"
    if t == TOKEN_GT:
        return "GT"
    if t == TOKEN_LTE:
        return "LTE"
    if t == TOKEN_GTE:
        return "GTE"
    if t == TOKEN_COLON:
        return "COLON"
    if t == TOKEN_COMMA:
        return "COMMA"
    if t == TOKEN_LBRACKET:
        return "LBRACKET"
    if t == TOKEN_RBRACKET:
        return "RBRACKET"
    if t == TOKEN_LBRACE:
        return "LBRACE"
    if t == TOKEN_RBRACE:
        return "RBRACE"
    if t == TOKEN_DOT:
        return "DOT"
    if t == TOKEN_AMP:
        return "AMP"
    if t == TOKEN_PIPE:
        return "PIPE"
    if t == TOKEN_CARET:
        return "CARET"
    if t == TOKEN_TILDE:
        return "TILDE"
    if t == TOKEN_LSHIFT:
        return "LSHIFT"
    if t == TOKEN_RSHIFT:
        return "RSHIFT"
    if t == TOKEN_IDENTIFIER:
        return "IDENTIFIER"
    if t == TOKEN_NUMBER:
        return "NUMBER"
    if t == TOKEN_STRING:
        return "STRING"
    if t == TOKEN_TRUE:
        return "TRUE"
    if t == TOKEN_FALSE:
        return "FALSE"
    if t == TOKEN_NIL:
        return "NIL"
    if t == TOKEN_END:
        return "END"
    if t == TOKEN_INDENT:
        return "INDENT"
    if t == TOKEN_DEDENT:
        return "DEDENT"
    if t == TOKEN_NEWLINE:
        return "NEWLINE"
    if t == TOKEN_EOF:
        return "EOF"
    if t == TOKEN_ERROR:
        return "ERROR"
    return "UNKNOWN"

# Token class
class Token:
    proc init(tok_type, text, tok_line):
        self.type = tok_type
        self.text = text
        self.line = tok_line

    proc to_string():
        return "Token(" + token_type_name(self.type) + ", " + str(self.text) + ", line=" + str(self.line) + ")"
