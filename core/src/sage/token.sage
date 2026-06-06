# -----------------------------------------
# token.sage - Token type constants and Token class
# Self-hosted SageLang tokenizer types
# -----------------------------------------

# Token type constants (enum equivalent)
# MUST MATCH core/include/token.h EXACTLY

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
let TOKEN_SUPER = 18

# Advanced control flow
let TOKEN_MATCH = 19
let TOKEN_CASE = 20
let TOKEN_DEFAULT = 21
let TOKEN_TRY = 22
let TOKEN_CATCH = 23
let TOKEN_FINALLY = 24
let TOKEN_RAISE = 25
let TOKEN_DEFER = 26
let TOKEN_YIELD = 27
let TOKEN_ASYNC = 28
let TOKEN_AWAIT = 29

# Data Modeling
let TOKEN_STRUCT = 30
let TOKEN_ENUM = 31
let TOKEN_TRAIT = 32

# Systems Layer
let TOKEN_UNSAFE = 33
let TOKEN_END = 34

# Module system
let TOKEN_IMPORT = 35
let TOKEN_FROM = 36
let TOKEN_AS = 37

# Metaprogramming
let TOKEN_COMPTIME = 38
let TOKEN_MACRO = 39
let TOKEN_QUOTE = 40
let TOKEN_UNQUOTE = 41
let TOKEN_AT = 42

# Symbols & operators
let TOKEN_LPAREN = 43
let TOKEN_RPAREN = 44
let TOKEN_PLUS = 45
let TOKEN_MINUS = 46
let TOKEN_STAR = 47
let TOKEN_SLASH = 48
let TOKEN_PERCENT = 49
let TOKEN_ASSIGN = 50
let TOKEN_EQ = 51
let TOKEN_NEQ = 52
let TOKEN_LT = 53
let TOKEN_GT = 54
let TOKEN_LTE = 55
let TOKEN_GTE = 56
let TOKEN_COLON = 57
let TOKEN_COMMA = 58
let TOKEN_LBRACKET = 59
let TOKEN_RBRACKET = 60
let TOKEN_LBRACE = 61
let TOKEN_RBRACE = 62
let TOKEN_DOT = 63
let TOKEN_ARROW = 64

# Bitwise operators
let TOKEN_AMP = 65
let TOKEN_PIPE = 66
let TOKEN_CARET = 67
let TOKEN_TILDE = 68
let TOKEN_LSHIFT = 69
let TOKEN_RSHIFT = 70

# Literals & identifiers
let TOKEN_IDENTIFIER = 71
let TOKEN_NUMBER = 72
let TOKEN_STRING = 73
let TOKEN_TRUE = 74
let TOKEN_FALSE = 75
let TOKEN_NIL = 76

# Structural
let TOKEN_INDENT = 77
let TOKEN_DEDENT = 78
let TOKEN_NEWLINE = 79
let TOKEN_DOC_COMMENT = 80
let TOKEN_EOF = 81
let TOKEN_ERROR = 82

# Token type name lookup for debugging
proc token_type_name(t):
    if t == TOKEN_LET: return "LET"
    if t == TOKEN_VAR: return "VAR"
    if t == TOKEN_PROC: return "PROC"
    if t == TOKEN_IF: return "IF"
    if t == TOKEN_ELSE: return "ELSE"
    if t == TOKEN_WHILE: return "WHILE"
    if t == TOKEN_FOR: return "FOR"
    if t == TOKEN_RETURN: return "RETURN"
    if t == TOKEN_PRINT: return "PRINT"
    if t == TOKEN_AND: return "AND"
    if t == TOKEN_OR: return "OR"
    if t == TOKEN_NOT: return "NOT"
    if t == TOKEN_IN: return "IN"
    if t == TOKEN_BREAK: return "BREAK"
    if t == TOKEN_CONTINUE: return "CONTINUE"
    if t == TOKEN_CLASS: return "CLASS"
    if t == TOKEN_SELF: return "SELF"
    if t == TOKEN_INIT: return "INIT"
    if t == TOKEN_SUPER: return "SUPER"
    if t == TOKEN_MATCH: return "MATCH"
    if t == TOKEN_CASE: return "CASE"
    if t == TOKEN_DEFAULT: return "DEFAULT"
    if t == TOKEN_TRY: return "TRY"
    if t == TOKEN_CATCH: return "CATCH"
    if t == TOKEN_FINALLY: return "FINALLY"
    if t == TOKEN_RAISE: return "RAISE"
    if t == TOKEN_DEFER: return "DEFER"
    if t == TOKEN_YIELD: return "YIELD"
    if t == TOKEN_ASYNC: return "ASYNC"
    if t == TOKEN_AWAIT: return "AWAIT"
    if t == TOKEN_STRUCT: return "STRUCT"
    if t == TOKEN_ENUM: return "ENUM"
    if t == TOKEN_TRAIT: return "TRAIT"
    if t == TOKEN_UNSAFE: return "UNSAFE"
    if t == TOKEN_END: return "END"
    if t == TOKEN_IMPORT: return "IMPORT"
    if t == TOKEN_FROM: return "FROM"
    if t == TOKEN_AS: return "AS"
    if t == TOKEN_COMPTIME: return "COMPTIME"
    if t == TOKEN_MACRO: return "MACRO"
    if t == TOKEN_QUOTE: return "QUOTE"
    if t == TOKEN_UNQUOTE: return "UNQUOTE"
    if t == TOKEN_AT: return "AT"
    if t == TOKEN_LPAREN: return "LPAREN"
    if t == TOKEN_RPAREN: return "RPAREN"
    if t == TOKEN_PLUS: return "PLUS"
    if t == TOKEN_MINUS: return "MINUS"
    if t == TOKEN_STAR: return "STAR"
    if t == TOKEN_SLASH: return "SLASH"
    if t == TOKEN_PERCENT: return "PERCENT"
    if t == TOKEN_ASSIGN: return "ASSIGN"
    if t == TOKEN_EQ: return "EQ"
    if t == TOKEN_NEQ: return "NEQ"
    if t == TOKEN_LT: return "LT"
    if t == TOKEN_GT: return "GT"
    if t == TOKEN_LTE: return "LTE"
    if t == TOKEN_GTE: return "GTE"
    if t == TOKEN_COLON: return "COLON"
    if t == TOKEN_COMMA: return "COMMA"
    if t == TOKEN_LBRACKET: return "LBRACKET"
    if t == TOKEN_RBRACKET: return "RBRACKET"
    if t == TOKEN_LBRACE: return "LBRACE"
    if t == TOKEN_RBRACE: return "RBRACE"
    if t == TOKEN_DOT: return "DOT"
    if t == TOKEN_ARROW: return "ARROW"
    if t == TOKEN_AMP: return "AMP"
    if t == TOKEN_PIPE: return "PIPE"
    if t == TOKEN_CARET: return "CARET"
    if t == TOKEN_TILDE: return "TILDE"
    if t == TOKEN_LSHIFT: return "LSHIFT"
    if t == TOKEN_RSHIFT: return "RSHIFT"
    if t == TOKEN_IDENTIFIER: return "IDENTIFIER"
    if t == TOKEN_NUMBER: return "NUMBER"
    if t == TOKEN_STRING: return "STRING"
    if t == TOKEN_TRUE: return "TRUE"
    if t == TOKEN_FALSE: return "FALSE"
    if t == TOKEN_NIL: return "NIL"
    if t == TOKEN_INDENT: return "INDENT"
    if t == TOKEN_DEDENT: return "DEDENT"
    if t == TOKEN_NEWLINE: return "NEWLINE"
    if t == TOKEN_DOC_COMMENT: return "DOC_COMMENT"
    if t == TOKEN_EOF: return "EOF"
    if t == TOKEN_ERROR: return "ERROR"
    return "UNKNOWN"

# Token class
class Token:
    proc init(tok_type, text, tok_line):
        self.type = tok_type
        self.text = text
        self.line = tok_line

    proc to_string():
        return "Token(" + token_type_name(self.type) + ", " + str(self.text) + ", line=" + str(self.line) + ")"
