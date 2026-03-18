gc_disable()
# -----------------------------------------
# diagnostic.sage - Rich diagnostic formatting for SageLang
# Port of src/c/diagnostic.c
# Token display names + Rust/Elm-style diagnostic output
# -----------------------------------------

import token

let NL = chr(10)

# -----------------------------------------
# token_display_name - human-readable name for a token type
# Used in error messages to show what was expected/found
# -----------------------------------------
proc token_display_name(t):
    if t == token.TOKEN_IDENTIFIER:
        return "identifier"
    if t == token.TOKEN_NUMBER:
        return "number"
    if t == token.TOKEN_STRING:
        return "string"
    if t == token.TOKEN_NEWLINE:
        return "end of line"
    if t == token.TOKEN_EOF:
        return "end of file"
    if t == token.TOKEN_INDENT:
        return "indentation"
    if t == token.TOKEN_DEDENT:
        return "dedent"
    if t == token.TOKEN_LPAREN:
        return "(" + chr(39) + "(" + chr(39) + ")"
    if t == token.TOKEN_RPAREN:
        return chr(39) + ")" + chr(39)
    if t == token.TOKEN_LBRACKET:
        return chr(39) + "[" + chr(39)
    if t == token.TOKEN_RBRACKET:
        return chr(39) + "]" + chr(39)
    if t == token.TOKEN_LBRACE:
        return chr(39) + "{" + chr(39)
    if t == token.TOKEN_RBRACE:
        return chr(39) + "}" + chr(39)
    if t == token.TOKEN_PLUS:
        return chr(39) + "+" + chr(39)
    if t == token.TOKEN_MINUS:
        return chr(39) + "-" + chr(39)
    if t == token.TOKEN_STAR:
        return chr(39) + "*" + chr(39)
    if t == token.TOKEN_SLASH:
        return chr(39) + "/" + chr(39)
    if t == token.TOKEN_PERCENT:
        return chr(39) + "%" + chr(39)
    if t == token.TOKEN_ASSIGN:
        return chr(39) + "=" + chr(39)
    if t == token.TOKEN_EQ:
        return chr(39) + "==" + chr(39)
    if t == token.TOKEN_NEQ:
        return chr(39) + "!=" + chr(39)
    if t == token.TOKEN_LT:
        return chr(39) + "<" + chr(39)
    if t == token.TOKEN_GT:
        return chr(39) + ">" + chr(39)
    if t == token.TOKEN_LTE:
        return chr(39) + "<=" + chr(39)
    if t == token.TOKEN_GTE:
        return chr(39) + ">=" + chr(39)
    if t == token.TOKEN_COLON:
        return chr(39) + ":" + chr(39)
    if t == token.TOKEN_COMMA:
        return chr(39) + "," + chr(39)
    if t == token.TOKEN_DOT:
        return chr(39) + "." + chr(39)
    if t == token.TOKEN_AMP:
        return chr(39) + "&" + chr(39)
    if t == token.TOKEN_PIPE:
        return chr(39) + "|" + chr(39)
    if t == token.TOKEN_CARET:
        return chr(39) + "^" + chr(39)
    if t == token.TOKEN_TILDE:
        return chr(39) + "~" + chr(39)
    if t == token.TOKEN_LSHIFT:
        return chr(39) + "<<" + chr(39)
    if t == token.TOKEN_RSHIFT:
        return chr(39) + ">>" + chr(39)
    # Default: lowercase the type name
    let name = token.token_type_name(t)
    let result = ""
    let i = 0
    while i < len(name):
        let c = name[i]
        let code = ord(c)
        if code >= 65:
            if code <= 90:
                result = result + chr(code + 32)
            else:
                result = result + c
        else:
            result = result + c
        i = i + 1
    return result

# -----------------------------------------
# Helper: repeat a character n times
# -----------------------------------------
proc repeat_char(ch, n):
    let result = ""
    let i = 0
    while i < n:
        result = result + ch
        i = i + 1
    return result

# -----------------------------------------
# Helper: count digits in a positive integer
# -----------------------------------------
proc digit_count(n):
    if n < 10:
        return 1
    if n < 100:
        return 2
    if n < 1000:
        return 3
    if n < 10000:
        return 4
    return 5

# -----------------------------------------
# Helper: left-pad string to given width
# -----------------------------------------
proc pad_left(s, width):
    let slen = len(s)
    if slen >= width:
        return s
    return repeat_char(" ", width - slen) + s

# -----------------------------------------
# format_diagnostic - format a rich diagnostic message
#
# severity: "error", "warning", "note", etc.
# filename: source file name
# line: 1-based line number (0 if unknown)
# column: 0-based column (-1 if unknown)
# span: length of underline (1 for caret, >1 for range)
# message: the diagnostic message text
# line_text: the source line text (nil if unavailable)
# help: optional help text (nil for none)
#
# Returns formatted string (does not print)
# -----------------------------------------
proc format_diagnostic(severity, filename, line, column, span, message, line_text, help):
    let out = ""

    # Header: "error: message"
    out = out + severity + ": " + message + NL

    # Location: "  --> filename:line:col"
    if line > 0:
        out = out + "  --> " + filename + ":" + str(line) + ":" + str(column + 1) + NL
    else:
        out = out + "  --> " + filename + NL

    # Source context
    if line_text != nil:
        if line > 0:
            let gutter = digit_count(line)
            let blank = repeat_char(" ", gutter)

            # Blank separator
            out = out + blank + " |" + NL

            # Source line
            let line_str = pad_left(str(line), gutter)
            out = out + line_str + " | " + line_text + NL

            # Pointer line
            out = out + blank + " | "
            if column > 0:
                out = out + repeat_char(" ", column)
            if span <= 1:
                out = out + "^"
            else:
                out = out + repeat_char("~", span)
            out = out + NL

    # Help text
    if help != nil:
        out = out + "  = help: " + help + NL

    return out

# -----------------------------------------
# format_token_diagnostic - format diagnostic from a token dict
#
# token should have: type, text, line, column, filename, line_text
# (any can be nil/missing)
# -----------------------------------------
proc format_token_diagnostic(severity, tok, fallback_filename, span, message, help):
    let filename = fallback_filename
    let line = 0
    let column = 0
    let line_text = nil

    if tok != nil:
        if type(tok) == "dict":
            if dict_has(tok, "filename"):
                if tok["filename"] != nil:
                    if len(tok["filename"]) > 0:
                        filename = tok["filename"]
            if dict_has(tok, "line"):
                line = tok["line"]
            if dict_has(tok, "column"):
                column = tok["column"]
            if dict_has(tok, "line_text"):
                line_text = tok["line_text"]
        else:
            if tok.line != nil:
                line = tok.line
            if tok.text != nil:
                line_text = tok.text

    return format_diagnostic(severity, filename, line, column, span, message, line_text, help)

# -----------------------------------------
# Convenience functions
# -----------------------------------------
proc format_error(filename, line, column, span, message, line_text, help):
    return format_diagnostic("error", filename, line, column, span, message, line_text, help)

proc format_warning(filename, line, column, span, message, line_text, help):
    return format_diagnostic("warning", filename, line, column, span, message, line_text, help)

proc format_note(filename, line, column, span, message, line_text, help):
    return format_diagnostic("note", filename, line, column, span, message, line_text, help)
