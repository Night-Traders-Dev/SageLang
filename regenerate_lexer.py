content = """# lily_lexer.sage - Frontend lexer for Lily Language
import token
from token import Token

# Custom Lily tokens beyond Sage's token set
let TOKEN_CONST = 1000
let TOKEN_FINAL = 1001
let TOKEN_FUNC = 1002
let TOKEN_PTR = 1003
let TOKEN_ADDR = 1004
let TOKEN_QUESTION = 1005
let TOKEN_BANG = 1006

# Lily Keywords
let KEYWORDS = {}
KEYWORDS["let"] = token.TOKEN_LET
KEYWORDS["var"] = token.TOKEN_VAR
KEYWORDS["const"] = TOKEN_CONST
KEYWORDS["final"] = TOKEN_FINAL
KEYWORDS["func"] = TOKEN_FUNC
KEYWORDS["ptr"] = TOKEN_PTR
KEYWORDS["addr"] = TOKEN_ADDR
KEYWORDS["if"] = token.TOKEN_IF
KEYWORDS["else"] = token.TOKEN_ELSE
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
KEYWORDS["super"] = token.TOKEN_SUPER
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
KEYWORDS["struct"] = token.TOKEN_STRUCT
KEYWORDS["enum"] = token.TOKEN_ENUM
KEYWORDS["trait"] = token.TOKEN_TRAIT
KEYWORDS["match"] = token.TOKEN_MATCH
KEYWORDS["case"] = token.TOKEN_CASE
KEYWORDS["default"] = token.TOKEN_DEFAULT

proc is_alpha(c):
    if c == nil: return false
    if c >= "a" and c <= "z":
        return true
    if c >= "A" and c <= "Z":
        return true
    if c == "_":
        return true
    return false

proc is_digit(c):
    if c == nil: return false
    if c >= "0" and c <= "9":
        return true
    return false

class LilyLexer:
    proc init(self, source):
        self.source = source
        self.pos = 0
        self.length = len(source)
        self.line = 1
        self.col = 1
        self.tokens = []
        self.indents = [0]
        self.start_of_line = true

    proc peek(self):
        if self.pos >= self.length: return nil
        return self.source[self.pos]

    proc advance(self):
        if self.pos >= self.length: return nil
        let c = self.source[self.pos]
        self.pos = self.pos + 1
        if c == chr(10):
            # \\n
            self.line = self.line + 1
            self.col = 1
        else:
            self.col = self.col + 1
        return c

    proc match_char(self, expected):
        if self.peek() == expected:
            self.advance()
            return true
        return false

    proc skip_whitespace(self):
        while true:
            let c = self.peek()
            if c == " " or c == chr(9):
                self.advance()
            elif c == "/":
                let next = self.pos + 1
                if next < self.length and self.source[next] == "/":
                    # skip comment
                    while self.peek() != nil and self.peek() != chr(10):
                        self.advance()
                else:
                    return false
            else:
                return false

    proc make_token(self, type, value):
        let t = Token(type, value, self.line, self.col)
        push(self.tokens, t)
        return t

    proc tokenize(self):
        while self.pos < self.length:
            if self.start_of_line:
                self.handle_indent()
                self.start_of_line = false
                continue
            self.skip_whitespace()
            if self.pos >= self.length:
                break
            let c = self.peek()
            if c == chr(10):
                self.make_token(token.TOKEN_NEWLINE, "newline")
                self.advance()
                self.start_of_line = true
                continue
            if is_alpha(c):
                self.handle_identifier()
            elif is_digit(c):
                self.handle_number()
            elif c == chr(34):
                # "
                self.handle_string()
            else:
                self.handle_symbol()
        
        # Emit remaining dedents
        while len(self.indents) > 1:
            pop(self.indents)
            self.make_token(token.TOKEN_DEDENT, "")
        self.make_token(token.TOKEN_EOF, "")
        return self.tokens

    proc handle_indent(self):
        let spaces = 0
        while true:
            let c = self.peek()
            if c == " ":
                spaces = spaces + 1
                self.advance()
            elif c == chr(9):
                spaces = spaces + 4
                self.advance()
            else:
                break
                
        let c = self.peek()
        if c == chr(10) or c == nil:
            return # empty line, ignore indentation
            
        let current_indent = self.indents[len(self.indents) - 1]
        if spaces > current_indent:
            push(self.indents, spaces)
            self.make_token(token.TOKEN_INDENT, "")
        elif spaces < current_indent:
            while len(self.indents) > 1 and spaces < self.indents[len(self.indents) - 1]:
                pop(self.indents)
                self.make_token(token.TOKEN_DEDENT, "")

    proc handle_identifier(self):
        let start_col = self.col
        let chars = []
        while is_alpha(self.peek()) or is_digit(self.peek()):
            push(chars, self.advance())
        let val = join(chars, "")
        if KEYWORDS[val] != nil:
            self.make_token(KEYWORDS[val], val)
        else:
            self.make_token(token.TOKEN_IDENTIFIER, val)

    proc handle_number(self):
        let chars = []
        while is_digit(self.peek()):
            push(chars, self.advance())
        self.make_token(token.TOKEN_NUMBER, join(chars, ""))

    proc handle_string(self):
        self.advance() # consume quote
        let chars = []
        while self.peek() != nil and self.peek() != chr(34):
            push(chars, self.advance())
        if self.peek() == chr(34):
            self.advance()
        self.make_token(token.TOKEN_STRING, join(chars, ""))

    proc handle_symbol(self):
        let c = self.advance()
        if c == "+":
            self.make_token(token.TOKEN_PLUS, "+")
        elif c == "-":
            if self.match_char(">"):
                self.make_token(token.TOKEN_ARROW, "->")
            else:
                self.make_token(token.TOKEN_MINUS, "-")
        elif c == "*":
            self.make_token(token.TOKEN_STAR, "*")
        elif c == "/":
            self.make_token(token.TOKEN_SLASH, "/")
        elif c == "%":
            self.make_token(token.TOKEN_PERCENT, "%")
        elif c == "=":
            if self.match_char("="):
                self.make_token(token.TOKEN_EQ, "==")
            else:
                self.make_token(token.TOKEN_ASSIGN, "=")
        elif c == "!":
            if self.match_char("="):
                self.make_token(token.TOKEN_NEQ, "!=")
            else:
                self.make_token(TOKEN_BANG, "!")
        elif c == "<":
            if self.match_char("="):
                self.make_token(token.TOKEN_LTE, "<=")
            else:
                self.make_token(token.TOKEN_LT, "<")
        elif c == ">":
            if self.match_char("="):
                self.make_token(token.TOKEN_GTE, ">=")
            else:
                self.make_token(token.TOKEN_GT, ">")
        elif c == "(":
            self.make_token(token.TOKEN_LPAREN, "(")
        elif c == ")":
            self.make_token(token.TOKEN_RPAREN, ")")
        elif c == "{":
            self.make_token(token.TOKEN_LBRACE, "{")
        elif c == "}":
            self.make_token(token.TOKEN_RBRACE, "}")
        elif c == "[":
            self.make_token(token.TOKEN_LBRACKET, "[")
        elif c == "]":
            self.make_token(token.TOKEN_RBRACKET, "]")
        elif c == ",":
            self.make_token(token.TOKEN_COMMA, ",")
        elif c == ":":
            self.make_token(token.TOKEN_COLON, ":")
        elif c == ".":
            self.make_token(token.TOKEN_DOT, ".")
        elif c == "?":
            self.make_token(TOKEN_QUESTION, "?")
        else:
            self.make_token(token.TOKEN_ERROR, c)
"""
with open("core/lib/transpiler/lily/lily_lexer.sage", "w") as f:
    f.write(content)
