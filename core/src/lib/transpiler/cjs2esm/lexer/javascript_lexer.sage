# -----------------------------------------
# javascript_lexer.sage - JavaScript/ECMAScript Lexer for cjs2esm
# Tokenizes JS/ECMAScript source code with full ASI, comments, spans
# -----------------------------------------

import token
from token import Token

# JavaScript keyword lookup table
let JS_KEYWORDS = {}
JS_KEYWORDS["break"] = token.TOKEN_BREAK
JS_KEYWORDS["case"] = token.TOKEN_CASE
JS_KEYWORDS["catch"] = token.TOKEN_CATCH
JS_KEYWORDS["class"] = token.TOKEN_CLASS
JS_KEYWORDS["const"] = token.TOKEN_VAR  # treated as var in CJS context initially
JS_KEYWORDS["continue"] = token.TOKEN_CONTINUE
JS_KEYWORDS["debugger"] = token.TOKEN_IDENTIFIER  # special handling later
JS_KEYWORDS["default"] = token.TOKEN_DEFAULT
JS_KEYWORDS["delete"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["do"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["else"] = token.TOKEN_ELSE
JS_KEYWORDS["export"] = token.TOKEN_IDENTIFIER  # special ESM handling
JS_KEYWORDS["extends"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["finally"] = token.TOKEN_FINALLY
JS_KEYWORDS["for"] = token.TOKEN_FOR
JS_KEYWORDS["function"] = token.TOKEN_IDENTIFIER  # special handling
JS_KEYWORDS["if"] = token.TOKEN_IF
JS_KEYWORDS["import"] = token.TOKEN_IMPORT
JS_KEYWORDS["import.meta"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["in"] = token.TOKEN_IN
JS_KEYWORDS["instanceof"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["new"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["null"] = token.TOKEN_NIL
JS_KEYWORDS["return"] = token.TOKEN_RETURN
JS_KEYWORDS["super"] = token.TOKEN_SUPER
JS_KEYWORDS["switch"] = token.TOKEN_CASE
JS_KEYWORDS["this"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["throw"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["try"] = token.TOKEN_TRY
JS_KEYWORDS["typeof"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["var"] = token.TOKEN_VAR
JS_KEYWORDS["void"] = token.TOKEN_IDENTIFIER
JS_KEYWORDS["while"] = token.TOKEN_WHILE
JS_KEYWORDS["with"] = token.TOKEN_IDENTIFIER

# Punctuators & operators
let JS_PUNCTUATORS = {}
JS_PUNCTUATORS["("] = token.TOKEN_LPAREN
JS_PUNCTUATORS[")"] = token.TOKEN_RPAREN
JS_PUNCTUATORS["["] = token.TOKEN_LBRACKET
JS_PUNCTUATORS["]"] = token.TOKEN_RBRACKET
JS_PUNCTUATORS["{"] = token.TOKEN_LBRACE
JS_PUNCTUATORS["}"] = token.TOKEN_RBRACE
JS_PUNCTUATORS["."] = token.TOKEN_DOT
JS_PUNCTUATORS["..."] = token.TOKEN_ELLIPSE  # will need to add
JS_PUNCTUATORS[";"] = token.TOKEN_SEMICOLON
JS_PUNCTUATORS[","] = token.TOKEN_COMMA
JS_PUNCTUATORS["="] = token.TOKEN_ASSIGN
JS_PUNCTUATORS["=="] = token.TOKEN_EQ
JS_PUNCTUATORS["!="] = token.TOKEN_NEQ
JS_PUNCTUATORS["<"] = token.TOKEN_LT
JS_PUNCTUATORS["<="] = token.TOKEN_LTE
JS_PUNCTUATORS[">"] = token.TOKEN_GT
JS_PUNCTUATORS[">="] = token.TOKEN_GTE
JS_PUNCTUATORS["+"] = token.TOKEN_PLUS
JS_PUNCTUATORS["++"] = token.TOKEN_PLUS_PLUS  # need to handle increment
JS_PUNCTUATORS["-"] = token.TOKEN_MINUS
JS_PUNCTUATORS["--"] = token.TOKEN_MINUS_MINUS
JS_PUNCTUATORS["*"] = token.TOKEN_STAR
JS_PUNCTUATORS["/"] = token.TOKEN_SLASH
JS_PUNCTUATORS["%"] = token.TOKEN_PERCENT
JS_PUNCTUATORS["&"] = token.TOKEN_AMP
JS_PUNCTUATORS["|"] = token.TOKEN_PIPE
JS_PUNCTUATORS["^"] = token.TOKEN_CARET
JS_PUNCTUATORS["~"] = token.TOKEN_TILDE
JS_PUNCTUATORS["&&"] = token.TOKEN_LOGICAL_AND  # need to handle two-char
JS_PUNCTUATORS["||"] = token.TOKEN_LOGICAL_OR
JS_PUNCTUATORS["?"] = token.TOKEN_QUESTION

# String escape handling
proc js_scan_escape():
    let c = peek_next()
    if c == nil:
        return "\\"  # trailing backslash
    return c

# JavaScript Lexer class
class JSLexer:
    proc init(source):
        self.source = source
        self.pos = 0
        self.source_len = len(source)
        self.line = 1
        self.at_bol = true

    proc peek():
        if self.pos >= self.source_len:
            return nil
        return self.source[self.pos]

    proc peek_next():
        if self.pos + 1 >= self.source_len:
            return nil
        return self.source[self.pos + 1]

    proc advance():
        if self.pos >= self.source_len:
            return nil
        let c = self.source[self.pos]
        self.pos = self.pos + 1
        if c == chr(10):
            self.line = self.line + 1
            self.at_bol = true
        return c

    proc is_at_end():
        return self.pos >= self.source_len

    # Scan an identifier or keyword
    proc scan_identifier():
        let start_pos = self.pos - 1
        while is_alnum(self.peek()):
            self.advance()
        let text = slice(self.source, start_pos, self.pos)
        let tok_type = token.TOKEN_IDENTIFIER
        if dict_has(JS_KEYWORDS, text):
            tok_type = JS_KEYWORDS[text]
        return self.make_token(tok_type, text)

    # Scan a number literal (JS flavored)
    proc scan_number():
        let start_pos = self.pos - 1
        if self.source[start_pos] == "0" and (self.peek() == "b" or self.peek() == "B"):
            self.advance()
            if not is_binary_digit(self.peek()):
                return self.error_token("Invalid binary literal: expected at least one binary digit after '0b'.")
            while is_binary_digit(self.peek()):
                self.advance()
            let binary_text = slice(self.source, start_pos, self.pos)
            return self.make_token(token.TOKEN_NUMBER, binary_text)

        if self.source[start_pos] == "0" and (self.peek() == "x" or self.peek() == "X"):
            self.advance()
            if not is_hex_digit(self.peek()):
                return self.error_token("Invalid hex literal: expected at least one hex digit after '0x'.")
            while is_hex_digit(self.peek()):
                self.advance()
            let hex_text = slice(self.source, start_pos, self.pos)
            return self.make_token(token.TOKEN_NUMBER, hex_text)

        if self.source[start_pos] == "0" and (self.peek() == "o" or self.peek() == "O"):
            self.advance()
            if not (self.peek() >= "0" and self.peek() <= "7"):
                return self.error_token("Invalid octal literal: expected at least one octal digit after '0o'.")
            while self.peek() >= "0" and self.peek() <= "7":
                self.advance()
            let octal_text = slice(self.source, start_pos, self.pos)
            return self.make_token(token.TOKEN_NUMBER, octal_text)

        while is_digit(self.peek()):
            self.advance()
        # Check for decimal point
        if self.peek() == "." and is_digit(self.peek_next()):
            self.advance()
            while is_digit(self.peek()):
                self.advance()
        let text = slice(self.source, start_pos, self.pos)
        return self.make_token(token.TOKEN_NUMBER, text)

    # Scan a string literal (double-quoted or single-quoted)
    proc scan_string():
        let quote = self.peek()
        self.advance()  # consume opening quote
        let start_pos = self.pos - 1
        while self.peek() != nil and self.peek() != quote:
            if self.peek() == chr(10):
                self.line = self.line + 1
                self.at_bol = true
            if self.peek() == "\\" and self.peek_next() != nil:
                self.advance()
                if self.peek() == chr(10):
                    self.line = self.line + 1
                    self.at_bol = true
                self.advance()
            else:
                self.advance()
        if self.is_at_end():
            return self.error_token("Unterminated string literal.")
        # Consume closing quote
        self.advance()
        let text = slice(self.source, start_pos, self.pos)
        return self.make_token(token.TOKEN_STRING, text)

    # Main scan function - returns next token
    proc scan_token():
        while true:
            # Handle beginning of line (indentation/newline)
            if self.at_bol:
                self.at_bol = false
                # Skip blank lines
                if self.peek() == chr(10):
                    self.line = self.line + 1
                    self.advance()
                    continue

                # Skip single-line comments //
                if self.peek() == "/" and self.peek_next() == "/":
                    self.advance()  # consume first /
                    self.advance()  # consume second /
                    while self.peek() != nil and self.peek() != chr(10):
                        self.advance()
                    continue

                # Skip multi-line comments /* ... */
                if self.peek() == "/" and self.peek_next() == "*":
                    self.advance()  # consume first /
                    self.advance()  # consume second *
                    while self.peek() != nil and not (self.peek() == "*" and self.peek_next() == "/"):
                        if self.peek() == chr(10):
                            self.line = self.line + 1
                            self.at_bol = true
                        self.advance()
                    if self.peek() == "*" and self.peek_next() == "/":
                        self.advance()  # consume *
                        self.advance()  # consume /
                    continue

            # Skip whitespace (non-newline)
            while self.peek() == " " or self.peek() == chr(9) or self.peek() == chr(13) or self.peek() == chr(10):
                if self.peek() == chr(10):
                    self.line = self.line + 1
                    self.at_bol = true
                self.advance()

            # Check for end of file
            if self.is_at_end():
                return self.make_token(token.TOKEN_EOF, "")

            let c = self.advance()

            # Newline
            if c == chr(10):
                self.line = self.line + 1
                self.at_bol = true
                return self.make_token(token.TOKEN_NEWLINE, c)

            # Single-line comments (already handled at bol, but handle inline too)
            if c == "/" and self.peek() == "/":
                self.advance()  # consume second /
                while self.peek() != nil and self.peek() != chr(10):
                    self.advance()
                continue

            # Block comments /* ... */ (inline)
            if c == "/" and self.peek() == "*":
                self.advance()  # consume first /
                self.advance()  # consume second *
                while self.peek() != nil and not (self.peek() == "*" and self.peek_next() == "/"):
                    if self.peek() == chr(10):
                        self.line = self.line + 1
                        self.at_bol = true
                    self.advance()
                if self.peek() == "*" and self.peek_next() == "/":
                    self.advance()  # consume *
                    self.advance()  # consume /
                continue

            # String literals
            if c == chr(34) or c == chr(39):  # " or '
                return self.scan_string()

            # Identifiers and keywords
            if is_alpha(c):
                return self.scan_identifier()

            # Numbers
            if is_digit(c):
                return self.scan_number()

            # Single-character tokens
            if c == "(":
                return self.make_token(token.TOKEN_LPAREN, c)
            if c == ")":
                return self.make_token(token.TOKEN_RPAREN, c)
            if c == "[":
                return self.make_token(token.TOKEN_LBRACKET, c)
            if c == "]":
                return self.make_token(token.TOKEN_RBRACKET, c)
            if c == "{":
                return self.make_token(token.TOKEN_LBRACE, c)
            if c == "}":
                return self.make_token(token.TOKEN_RBRACE, c)
            if c == ";":
                return self.make_token(token.TOKEN_SEMICOLON, c)
            if c == ",":
                return self.make_token(token.TOKEN_COMMA, c)
            if c == "+":
                # Check for ++
                if self.peek() == "+":
                    self.advance()
                    return self.make_token(token.TOKEN_PLUS_PLUS, "++")
                return self.make_token(token.TOKEN_PLUS, c)
            if c == "-":
                # Check for --
                if self.peek() == "-":
                    self.advance()
                    return self.make_token(token.TOKEN_MINUS_MINUS, "--")
                # Check for ->
                if self.peek() == ">":
                    self.advance()
                    return self.make_token(token.TOKEN_ARROW, "->")
                return self.make_token(token.TOKEN_MINUS, c)
            if c == "*":
                return self.make_token(token.TOKEN_STAR, c)
            if c == "/":
                # Check for /=
                if self.peek() == "=":
                    self.advance()
                    return self.make_token(token.TOKEN_DIV_ASSIGN, "/=")
                return self.make_token(token.TOKEN_SLASH, c)
            if c == "%":
                return self.make_token(token.TOKEN_PERCENT, c)
            if c == ":":
                # Check for :: or :
                if self.peek() == ":":
                    self.advance()
                    return self.make_token(token.TOKEN_DOUBLE_COLON, "::")
                return self.make_token(token.TOKEN_COLON, c)
            if c == "@":
                return self.make_token(token.TOKEN_AT, c)
            if c == "=":
                # Check for == or =
                if self.peek() == "=":
                    self.advance()
                    return self.make_token(token.TOKEN_EQ, "==")
                return self.make_token(token.TOKEN_ASSIGN, "=")
            if c == "!":
                # Check for !=
                if self.peek() == "=":
                    self.advance()
                    return self.make_token(token.TOKEN_NEQ, "!=")
                return self.make_token(token.TOKEN_ERROR, "Unexpected '!' (use 'not')")
            if c == "<":
                # Check for <<, <=
                if self.peek() == "<":
                    self.advance()
                    return self.make_token(token.TOKEN_LSHIFT, "<<")
                if self.peek() == "=":
                    self.advance()
                    return self.make_token(token.TOKEN_LTE, "<=")
                return self.make_token(token.TOKEN_LT, "<")
            if c == ">":
                # Check for >>, >=
                if self.peek() == ">":
                    self.advance()
                    return self.make_token(token.TOKEN_RSHIFT, ">>")
                if self.peek() == "=":
                    self.advance()
                    return self.make_token(token.TOKEN_GTE, ">=")
                return self.make_token(token.TOKEN_GT, ">")

            # Two-character operators
            if c == "&":
                if self.peek() == "&":
                    self.advance()
                    return self.make_token(token.TOKEN_LOGICAL_AND, "&&")
                return self.make_token(token.TOKEN_ERROR, "Unexpected '&'")
            if c == "|":
                if self.peek() == "|":
                    self.advance()
                    return self.make_token(token.TOKEN_LOGICAL_OR, "||")
                return self.make_token(token.TOKEN_ERROR, "Unexpected '|'")
            if c == "^":
                return self.make_token(token.TOKEN_CARET, c)
            if c == "~":
                return self.make_token(token.TOKEN_TILDE, c)

            return self.error_token("Unexpected character: " + c)

    # Convenience: tokenize an entire source string
    proc tokenize():
        let tokens = []
        while true:
            let tok = scan_token()
            push(tokens, tok)
            if tok.type == token.TOKEN_EOF:
                break
        return tokens

    # Convenience factory
    proc make_token(tok_type, text):
        return Token(tok_type, text, self.line)


# Helper functions (shared with lexer.sage)
proc is_alpha(c):
    if c == nil:
        return false
    if c >= "a" and c <= "z":
        return true
    if c >= "A" and c <= "Z":
        return true
    if c == "_":
        return true
    return false

proc is_digit(c):
    if c == nil:
        return false
    return c >= "0" and c <= "9"

proc is_hex_digit(c):
    if c == nil:
        return false
    if c >= "0" and c <= "9":
        return true
    if c >= "a" and c <= "f":
        return true
    if c >= "A" and c <= "F":
        return true
    return false

proc is_binary_digit(c):
    return c == "0" or c == "1"

proc is_alnum(c):
    return is_alpha(c) or is_digit(c)

proc slice(source, start, end):
    let result = ""
    var i = start
    while i < end and i < len(source):
        push(result, source[i])
        i = i + 1
    return result

proc dict_has(dict, key):
    var i = 0
    while i < len(dict):
        if dict[i][0] == key:
            return true
        i = i + 1
    return false

# Convenience factory: tokenize entire JS source string
proc js_tokenize(source):
    let lex = JSLexer(source)
    return lex.tokenize()