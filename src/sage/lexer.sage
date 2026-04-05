# -----------------------------------------
# lexer.sage - Self-hosted SageLang lexer
# Tokenizes Sage source code into tokens
# -----------------------------------------

import token
from token import Token

# Keyword lookup table
let KEYWORDS = {}
KEYWORDS["let"] = token.TOKEN_LET
KEYWORDS["var"] = token.TOKEN_VAR
KEYWORDS["proc"] = token.TOKEN_PROC
KEYWORDS["if"] = token.TOKEN_IF
KEYWORDS["else"] = token.TOKEN_ELSE
KEYWORDS["elif"] = token.TOKEN_IF
KEYWORDS["while"] = token.TOKEN_WHILE
KEYWORDS["for"] = token.TOKEN_FOR
KEYWORDS["return"] = token.TOKEN_RETURN
KEYWORDS["print"] = token.TOKEN_PRINT
KEYWORDS["and"] = token.TOKEN_AND
KEYWORDS["or"] = token.TOKEN_OR
KEYWORDS["not"] = token.TOKEN_NOT
KEYWORDS["in"] = token.TOKEN_IN
KEYWORDS["break"] = token.TOKEN_BREAK
KEYWORDS["continue"] = token.TOKEN_CONTINUE
KEYWORDS["class"] = token.TOKEN_CLASS
KEYWORDS["self"] = token.TOKEN_SELF
KEYWORDS["init"] = token.TOKEN_INIT
KEYWORDS["true"] = token.TOKEN_TRUE
KEYWORDS["false"] = token.TOKEN_FALSE
KEYWORDS["nil"] = token.TOKEN_NIL
KEYWORDS["try"] = token.TOKEN_TRY
KEYWORDS["catch"] = token.TOKEN_CATCH
KEYWORDS["finally"] = token.TOKEN_FINALLY
KEYWORDS["raise"] = token.TOKEN_RAISE
KEYWORDS["defer"] = token.TOKEN_DEFER
KEYWORDS["yield"] = token.TOKEN_YIELD
KEYWORDS["async"] = token.TOKEN_ASYNC
KEYWORDS["await"] = token.TOKEN_AWAIT
KEYWORDS["import"] = token.TOKEN_IMPORT
KEYWORDS["from"] = token.TOKEN_FROM
KEYWORDS["as"] = token.TOKEN_AS
KEYWORDS["case"] = token.TOKEN_CASE
KEYWORDS["default"] = token.TOKEN_DEFAULT
KEYWORDS["end"] = token.TOKEN_END

# Character classification helpers
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

proc is_binary_digit(c):
    if c == nil:
        return false
    return c == "0" or c == "1"

proc is_alnum(c):
    return is_alpha(c) or is_digit(c)

class Lexer:
    proc init(source):
        self.source = source
        self.pos = 0
        self.source_len = len(source)
        self.line = 1
        self.at_bol = true
        self.indent_stack = [0]
        self.pending_dedents = 0

    # Peek at current character without advancing
    proc peek():
        if self.pos >= self.source_len:
            return nil
        return self.source[self.pos]

    # Peek at next character
    proc peek_next():
        if self.pos + 1 >= self.source_len:
            return nil
        return self.source[self.pos + 1]

    # Advance and return the character consumed
    proc advance():
        if self.pos >= self.source_len:
            return nil
        let c = self.source[self.pos]
        self.pos = self.pos + 1
        return c

    # Check if at end of source
    proc is_at_end():
        return self.pos >= self.source_len

    # Match next char and consume if matches
    proc match_char(expected):
        if self.is_at_end():
            return false
        if self.source[self.pos] != expected:
            return false
        self.pos = self.pos + 1
        return true

    # Make a token
    proc make_token(tok_type, text):
        return Token(tok_type, text, self.line)

    # Make an error token
    proc error_token(msg):
        return Token(token.TOKEN_ERROR, msg, self.line)

    # Scan an identifier or keyword
    proc scan_identifier():
        let start_pos = self.pos - 1
        while is_alnum(self.peek()):
            self.advance()
        let text = slice(self.source, start_pos, self.pos)
        let tok_type = token.TOKEN_IDENTIFIER
        if dict_has(KEYWORDS, text):
            tok_type = KEYWORDS[text]
        return self.make_token(tok_type, text)

    # Scan a number literal
    proc scan_number():
        let start_pos = self.pos - 1
        if self.source[start_pos] == "0" and (self.peek() == "b" or self.peek() == "B"):
            self.advance()
            if not is_binary_digit(self.peek()):
                return self.error_token("Invalid binary literal: expected at least one binary digit after '0b'.")
            while is_binary_digit(self.peek()):
                self.advance()
            if is_alnum(self.peek()) or self.peek() == "_":
                return self.error_token("Invalid binary literal: use only 0 or 1 after '0b'.")
            let binary_text = slice(self.source, start_pos, self.pos)
            return self.make_token(token.TOKEN_NUMBER, binary_text)

        while is_digit(self.peek()):
            self.advance()
        # Check for decimal point
        if self.peek() == "." and is_digit(self.peek_next()):
            self.advance()
            while is_digit(self.peek()):
                self.advance()
        let text = slice(self.source, start_pos, self.pos)
        return self.make_token(token.TOKEN_NUMBER, text)

    # Scan a string literal (double-quoted)
    proc scan_string():
        let start_pos = self.pos - 1
        while self.peek() != nil and self.peek() != self.source[start_pos]:
            if self.peek() == chr(10):
                self.line = self.line + 1
            self.advance()
        if self.is_at_end():
            return self.error_token("Unterminated string.")
        # Consume closing quote
        self.advance()
        let text = slice(self.source, start_pos, self.pos)
        return self.make_token(token.TOKEN_STRING, text)

    # Main scan function - returns next token
    proc scan_token():
        while true:
            # Handle pending dedents
            if self.pending_dedents > 0:
                self.pending_dedents = self.pending_dedents - 1
                return self.make_token(token.TOKEN_DEDENT, "")

            # Handle beginning of line (indentation)
            if self.at_bol:
                self.at_bol = false
                let spaces = 0
                while self.peek() == " ":
                    self.advance()
                    spaces = spaces + 1

                # Skip blank lines
                if self.peek() == chr(10):
                    self.line = self.line + 1
                    self.advance()
                    self.at_bol = true
                    continue

                let current_indent = self.indent_stack[len(self.indent_stack) - 1]
                if spaces > current_indent:
                    push(self.indent_stack, spaces)
                    return self.make_token(token.TOKEN_INDENT, "")
                elif spaces < current_indent:
                    while len(self.indent_stack) > 1 and self.indent_stack[len(self.indent_stack) - 1] > spaces:
                        pop(self.indent_stack)
                        self.pending_dedents = self.pending_dedents + 1
                    if self.indent_stack[len(self.indent_stack) - 1] != spaces:
                        return self.error_token("Indentation error.")
                    self.pending_dedents = self.pending_dedents - 1
                    return self.make_token(token.TOKEN_DEDENT, "")

            # Skip whitespace (non-newline)
            while self.peek() == " " or self.peek() == chr(9) or self.peek() == chr(13):
                self.advance()

            # Check for end of file
            if self.is_at_end():
                if len(self.indent_stack) > 1:
                    pop(self.indent_stack)
                    return self.make_token(token.TOKEN_DEDENT, "")
                return self.make_token(token.TOKEN_EOF, "")

            let c = self.advance()

            # Newline
            if c == chr(10):
                self.line = self.line + 1
                self.at_bol = true
                return self.make_token(token.TOKEN_NEWLINE, c)

            # Comments
            if c == "#":
                while self.peek() != nil and self.peek() != chr(10):
                    self.advance()
                continue

            # String
            if c == chr(34):
                return self.scan_string()

            # Single-quoted string
            if c == "'":
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
            if c == "+":
                return self.make_token(token.TOKEN_PLUS, c)
            if c == "-":
                return self.make_token(token.TOKEN_MINUS, c)
            if c == "*":
                return self.make_token(token.TOKEN_STAR, c)
            if c == "/":
                return self.make_token(token.TOKEN_SLASH, c)
            if c == "%":
                return self.make_token(token.TOKEN_PERCENT, c)
            if c == ",":
                return self.make_token(token.TOKEN_COMMA, c)
            if c == ":":
                return self.make_token(token.TOKEN_COLON, c)
            if c == ".":
                return self.make_token(token.TOKEN_DOT, c)
            if c == "&":
                return self.make_token(token.TOKEN_AMP, c)
            if c == "|":
                return self.make_token(token.TOKEN_PIPE, c)
            if c == "^":
                return self.make_token(token.TOKEN_CARET, c)
            if c == "~":
                return self.make_token(token.TOKEN_TILDE, c)

            # Two-character tokens
            if c == "!":
                if self.match_char("="):
                    return self.make_token(token.TOKEN_NEQ, "!=")
                return self.error_token("Unexpected '!' (use 'not')")
            if c == "=":
                if self.match_char("="):
                    return self.make_token(token.TOKEN_EQ, "==")
                return self.make_token(token.TOKEN_ASSIGN, "=")
            if c == "<":
                if self.match_char("<"):
                    return self.make_token(token.TOKEN_LSHIFT, "<<")
                if self.match_char("="):
                    return self.make_token(token.TOKEN_LTE, "<=")
                return self.make_token(token.TOKEN_LT, "<")
            if c == ">":
                if self.match_char(">"):
                    return self.make_token(token.TOKEN_RSHIFT, ">>")
                if self.match_char("="):
                    return self.make_token(token.TOKEN_GTE, ">=")
                return self.make_token(token.TOKEN_GT, ">")

            return self.error_token("Unexpected character: " + c)

# Convenience: tokenize an entire source string
proc tokenize(source):
    let lex = Lexer(source)
    let tokens = []
    while true:
        let tok = lex.scan_token()
        push(tokens, tok)
        if tok.type == token.TOKEN_EOF:
            break
    return tokens
