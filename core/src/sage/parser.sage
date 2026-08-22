gc_disable()
# -----------------------------------------
# parser.sage - Recursive descent parser for SageLang
# Ported from src/parser.c
# -----------------------------------------

import token
from token import Token
from lexer import tokenize
from ast import Expr, Stmt, CatchClause
import errors

from ast import EXPR_NUMBER, EXPR_STRING, EXPR_BOOL, EXPR_NIL
from ast import EXPR_BINARY, EXPR_VARIABLE, EXPR_CALL, EXPR_ARRAY
from ast import EXPR_INDEX, EXPR_DICT, EXPR_TUPLE, EXPR_SLICE
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT, EXPR_PROC
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC, STMT_DEFER, STMT_STRUCT
from ast import number_expr, string_expr, bool_expr, nil_expr
from ast import binary_expr, variable_expr, call_expr, array_expr
from ast import index_expr, index_set_expr, dict_expr, tuple_expr
from ast import slice_expr, get_expr, set_expr, await_expr, proc_expr
from ast import print_stmt, expr_stmt, let_stmt, if_stmt
from ast import block_stmt, while_stmt, proc_stmt, for_stmt
from ast import return_stmt, break_stmt, continue_stmt, class_stmt
from ast import try_stmt, raise_stmt, yield_stmt, import_stmt
from ast import async_proc_stmt, defer_stmt, struct_stmt
from ast import enum_stmt, trait_stmt, match_stmt, comptime_stmt
from ast import macro_def_stmt, comptime_expr, super_expr

# Maximum parser recursion depth
let MAX_DEPTH = 500

let TYPE_UNKNOWN = 0
let TYPE_NUMBER = 1
let TYPE_STRING = 2
let TYPE_BOOL = 3
let TYPE_NIL = 4
let TYPE_ARRAY = 5
let TYPE_DICT = 6
let TYPE_TUPLE = 7
let TYPE_PROC = 8

proc parse_type_name(parser):
    let tok = parser.peek()
    if tok.type == token.TOKEN_IDENTIFIER:
        let t_text = tok.text
        let t_kind = annotation_to_kind(t_text)
        parser.advance()  # consume the type name token
        return [t_text, t_kind]
    return [nil, TYPE_UNKNOWN]

proc annotation_to_kind(name):
    let n = name
    let len = len(n)
    if len == 3 and n == "Int": return TYPE_NUMBER
    if len == 5 and n == "Float": return TYPE_NUMBER
    if len == 6 and n == "Number": return TYPE_NUMBER
    if len == 4 and n == "Bool": return TYPE_BOOL
    if len == 6 and n == "String": return TYPE_STRING
    if len == 3 and n == "Str": return TYPE_STRING
    if len == 5 and n == "Array": return TYPE_ARRAY
    if len == 4 and n == "Dict": return TYPE_DICT
    if len == 5 and n == "Tuple": return TYPE_TUPLE
    if len == 3 and n == "Nil": return TYPE_NIL
    if len == 8 and n == "Function": return TYPE_PROC
    if len == 4 and n == "Proc": return TYPE_PROC
    return TYPE_UNKNOWN

let TYPE_UNKNOWN = 0
let TYPE_NUMBER = 1
let TYPE_STRING = 2
let TYPE_BOOL = 3
let TYPE_NIL = 4
let TYPE_ARRAY = 5
let TYPE_DICT = 6
let TYPE_TUPLE = 7
let TYPE_PROC = 8

proc parse_type_name(parser):
    let tok = parser.peek()
    if tok.type == token.TOKEN_IDENTIFIER:
        let t_text = tok.text
        let t_kind = annotation_to_kind(t_text)
        parser.advance()  # consume the type name token
        return [t_text, t_kind]
    return [nil, TYPE_UNKNOWN]

proc annotation_to_kind(name):
    let n = name.text
    let len = len(n)
    if len == 3 and n == "Int": return TYPE_NUMBER
    if len == 5 and n == "Float": return TYPE_NUMBER
    if len == 6 and n == "Number": return TYPE_NUMBER
    if len == 4 and n == "Bool": return TYPE_BOOL
    if len == 6 and n == "String": return TYPE_STRING
    if len == 3 and n == "Str": return TYPE_STRING
    if len == 5 and n == "Array": return TYPE_ARRAY
    if len == 4 and n == "Dict": return TYPE_DICT
    if len == 5 and n == "Tuple": return TYPE_TUPLE
    if len == 3 and n == "Nil": return TYPE_NIL
    if len == 8 and n == "Function": return TYPE_PROC
    if len == 4 and n == "Proc": return TYPE_PROC
    return TYPE_UNKNOWN


let TYPE_UNKNOWN = 0
let TYPE_NUMBER = 1
let TYPE_STRING = 2
let TYPE_BOOL = 3
let TYPE_NIL = 4
let TYPE_ARRAY = 5
let TYPE_DICT = 6
let TYPE_TUPLE = 7
let TYPE_PROC = 8


proc annotation_to_kind(name):
    let n = name
    let len = len(n)
    if len == 3 and n == "Int": return TYPE_NUMBER
    if len == 5 and n == "Float": return TYPE_NUMBER
    if len == 6 and n == "Number": return TYPE_NUMBER
    if len == 4 and n == "Bool": return TYPE_BOOL
    if len == 6 and n == "String": return TYPE_STRING
    if len == 3 and n == "Str": return TYPE_STRING
    if len == 5 and n == "Array": return TYPE_ARRAY
    if len == 4 and n == "Dict": return TYPE_DICT
    if len == 5 and n == "Tuple": return TYPE_TUPLE
    if len == 3 and n == "Nil": return TYPE_NIL
    if len == 8 and n == "Function": return TYPE_PROC
    if len == 4 and n == "Proc": return TYPE_PROC
    return TYPE_UNKNOWN

proc parse_number_literal(text):
    if len(text) >= 2 and text[0] == "0" and (text[1] == "b" or text[1] == "B"):
        let value = 0
        let i = 2
        while i < len(text):
            value = value * 2
            if text[i] == "1":
                value = value + 1
            elif text[i] != "0":
                return tonumber(text)
            i = i + 1
        return value
    return tonumber(text)

proc hex_digit_value(c):
    if c >= "0" and c <= "9":
        return ord(c) - ord("0")
    if c >= "a" and c <= "f":
        return ord(c) - ord("a") + 10
    if c >= "A" and c <= "F":
        return ord(c) - ord("A") + 10
    return -1

# Process string escapes, mirroring C parser.c process_string_escapes
proc unescape_string(raw):
    let j = 0
    let out = ""
    while j < len(raw):
        if raw[j] == "\\" and j + 1 < len(raw):
            j = j + 1
            let c = raw[j]
            if c == "n":
                out = out + chr(10)
            elif c == "t":
                out = out + chr(9)
            elif c == "r":
                out = out + chr(13)
            elif c == "\\":
                out = out + "\\"
            elif c == "\"":
                out = out + chr(34)
            elif c == "'":
                out = out + chr(39)
            elif c == "0":
                out = out + chr(0)
            elif c == "a":
                out = out + chr(7)
            elif c == "b":
                out = out + chr(8)
            elif c == "f":
                out = out + chr(12)
            elif c == "v":
                out = out + chr(11)
            elif c == "x":
                if j + 2 < len(raw):
                    let hi = hex_digit_value(raw[j + 1])
                    let lo = hex_digit_value(raw[j + 2])
                    if hi >= 0 and lo >= 0:
                        out = out + chr(hi * 16 + lo)
                        j = j + 2
                    else:
                        out = out + "\\x"
                else:
                    out = out + "\\x"
            else:
                out = out + "\\" + c
        else:
            out = out + raw[j]
        j = j + 1
    return out

class Parser:
    proc init(tokens, source, filename):
        self.tokens = tokens
        self.pos = 0
        self.depth = 0
        self.source = source
        self.filename = filename
        self.pending_doc = nil
        self.error_ctx = nil

    proc collect_doc_comment():
        # Collect consecutive ## lines into one doc string
        self.pending_doc = nil
        let parts = []
        while self.check(token.TOKEN_DOC_COMMENT):
            let doc_tok = self.advance()
            push(parts, doc_tok.text)
            self.match_tok(token.TOKEN_NEWLINE)
        if len(parts) > 0:
            self.pending_doc = join(parts, chr(10))

    proc take_pending_doc():
        let doc = self.pending_doc
        self.pending_doc = nil
        return doc

    proc get_error_ctx():
        if self.error_ctx == nil:
            self.error_ctx = errors.make_error_context(self.source, self.filename)
        return self.error_ctx

    proc parse_error(tok, message, hint):
        let ctx = self.get_error_ctx()
        let col = -1
        # Match the C host's diagnostic style: lowercase severity, and strip
        # any duplicated "Error:" prefix from hand-written messages.
        let msg = message
        if len(msg) >= 7 and msg[0:7] == "Error: ":
            msg = msg[7:]
        let formatted = errors.format_error(ctx, tok.line, col, "error", msg, hint)
        raise formatted

    # --- Token access ---

    proc is_at_end():
        return self.pos >= len(self.tokens)

    proc peek():
        if self.is_at_end():
            return self.tokens[len(self.tokens) - 1]
        return self.tokens[self.pos]

    proc peek_type():
        if self.is_at_end():
            return self.tokens[len(self.tokens) - 1].type
        return self.tokens[self.pos].type

    proc advance():
        let tok = self.tokens[self.pos]
        self.pos = self.pos + 1
        return tok

    proc previous():
        if self.pos <= 0:
            return self.tokens[0]
        return self.tokens[self.pos - 1]

    proc check(tok_type):
        return self.peek_type() == tok_type

    proc match_tok(tok_type):
        if self.check(tok_type):
            self.advance()
            return true
        return false

    proc consume(tok_type, message):
        if self.check(tok_type):
            return self.advance()
        let tok = self.peek()
        let got_name = token.token_type_name(tok.type)
        let hint = "got " + got_name
        if got_name == "NEWLINE":
            hint = "got end of line -- did you forget something?"
        if got_name == "EOF":
            hint = "got end of file -- the code may be incomplete"
        self.parse_error(tok, message, hint)

    # --- Expression parsing (precedence climbing) ---

    proc parse_expression():
        self.depth = self.depth + 1
        if self.depth > MAX_DEPTH:
            let tok = self.peek()
            self.parse_error(tok, "Maximum nesting depth exceeded", "reduce the depth of nested expressions")
        let result = self.parse_assignment()
        self.depth = self.depth - 1
        return result

    # Parse expression for RHS of let statements (no assignment handling)
    proc parse_expression_rhs():
        self.depth = self.depth + 1
        if self.depth > MAX_DEPTH:
            let tok = self.peek()
            self.parse_error(tok, "Maximum nesting depth exceeded", "reduce the depth of nested expressions")
        let result = self.parse_or()
        self.depth = self.depth - 1
        return result


    # Parse expression for RHS of let statements (no assignment handling)
    proc parse_expression_rhs():
        self.depth = self.depth + 1
        if self.depth > MAX_DEPTH:
            let tok = self.peek()
            self.parse_error(tok, "Maximum nesting depth exceeded", "reduce the depth of nested expressions")
        let result = self.parse_or()
        self.depth = self.depth - 1
        return result

    proc parse_assignment():
        let expr = self.parse_or()

        # Property assignment: obj.prop = value
        if expr.type == EXPR_GET and self.match_tok(token.TOKEN_ASSIGN):
            let obj = expr.object
            let prop = expr.property
            let value = self.parse_assignment()
            return set_expr(obj, prop, value)

        # Index assignment: arr[i] = value
        if expr.type == EXPR_INDEX and self.match_tok(token.TOKEN_ASSIGN):
            let obj = expr.object
            let idx = expr.index
            let value = self.parse_assignment()
            return index_set_expr(obj, idx, value)

        # Variable assignment: x = value
        if expr.type == EXPR_VARIABLE and self.match_tok(token.TOKEN_ASSIGN):
            let name = expr.name
            let value = self.parse_assignment()
            return set_expr(nil, name, value)

        return expr

    proc parse_or():
        let expr = self.parse_and()
        while self.match_tok(token.TOKEN_OR):
            let op = self.previous()
            let right = self.parse_and()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_and():
        let expr = self.parse_bitwise_or()
        while self.match_tok(token.TOKEN_AND):
            let op = self.previous()
            let right = self.parse_bitwise_or()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_bitwise_or():
        let expr = self.parse_bitwise_xor()
        while self.match_tok(token.TOKEN_PIPE):
            let op = self.previous()
            let right = self.parse_bitwise_xor()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_bitwise_xor():
        let expr = self.parse_bitwise_and()
        while self.match_tok(token.TOKEN_CARET):
            let op = self.previous()
            let right = self.parse_bitwise_and()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_bitwise_and():
        let expr = self.parse_equality()
        while self.match_tok(token.TOKEN_AMP):
            let op = self.previous()
            let right = self.parse_equality()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_equality():
        let expr = self.parse_comparison()
        while self.match_tok(token.TOKEN_EQ) or self.match_tok(token.TOKEN_NEQ):
            let op = self.previous()
            let right = self.parse_comparison()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_comparison():
        let expr = self.parse_shift()
        while self.match_tok(token.TOKEN_GT) or self.match_tok(token.TOKEN_LT) or self.match_tok(token.TOKEN_GTE) or self.match_tok(token.TOKEN_LTE):
            let op = self.previous()
            let right = self.parse_shift()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_shift():
        let expr = self.parse_addition()
        while self.match_tok(token.TOKEN_LSHIFT) or self.match_tok(token.TOKEN_RSHIFT):
            let op = self.previous()
            let right = self.parse_addition()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_addition():
        let expr = self.parse_term()
        while self.match_tok(token.TOKEN_PLUS) or self.match_tok(token.TOKEN_MINUS):
            let op = self.previous()
            let right = self.parse_term()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_term():
        let expr = self.parse_unary()
        while self.match_tok(token.TOKEN_STAR) or self.match_tok(token.TOKEN_SLASH) or self.match_tok(token.TOKEN_PERCENT):
            let op = self.previous()
            let right = self.parse_unary()
            expr = binary_expr(expr, op, right)
        return expr

    proc parse_unary():
        # Unary minus: -x is represented as (0 - x)
        if self.match_tok(token.TOKEN_MINUS):
            let op = self.previous()
            let right = self.parse_unary()
            return binary_expr(number_expr(0), op, right)
        # Logical not: not x
        if self.match_tok(token.TOKEN_NOT):
            let op = self.previous()
            let right = self.parse_unary()
            return binary_expr(right, op, nil)
        # Bitwise not: ~x
        if self.match_tok(token.TOKEN_TILDE):
            let op = self.previous()
            let right = self.parse_unary()
            return binary_expr(right, op, nil)
        # Await expression
        if self.match_tok(token.TOKEN_AWAIT):
            let right = self.parse_unary()
            return await_expr(right)
        return self.parse_postfix()

    proc parse_postfix():
        let expr = self.parse_primary()
        while true:
            if self.match_tok(token.TOKEN_LPAREN):
                # Function call
                let args = []
                if not self.check(token.TOKEN_RPAREN):
                    push(args, self.parse_expression())
                    while self.match_tok(token.TOKEN_COMMA):
                        push(args, self.parse_expression())
                self.consume(token.TOKEN_RPAREN, "Expect ')' after arguments.")
                expr = call_expr(expr, args)
            elif self.match_tok(token.TOKEN_LBRACKET):
                # Index or slice
                let start_or_index = nil
                if not self.check(token.TOKEN_COLON):
                    start_or_index = self.parse_expression()
                if self.match_tok(token.TOKEN_COLON):
                    # Slice: obj[start:end]
                    let start_val = start_or_index
                    let end_val = nil
                    if not self.check(token.TOKEN_RBRACKET):
                        end_val = self.parse_expression()
                    self.consume(token.TOKEN_RBRACKET, "Expect ']' after slice.")
                    expr = slice_expr(expr, start_val, end_val)
                else:
                    self.consume(token.TOKEN_RBRACKET, "Expect ']' after index.")
                    expr = index_expr(expr, start_or_index)
            elif self.match_tok(token.TOKEN_DOT) or self.match_tok(token.TOKEN_ARROW):
                # Property access (allow identifiers, 'end', and 'print' keywords)
                if self.check(token.TOKEN_IDENTIFIER) or self.check(token.TOKEN_END) or self.check(token.TOKEN_PRINT):
                    let prop = self.advance()
                    expr = get_expr(expr, prop)
                else:
                    self.consume(token.TOKEN_IDENTIFIER, "Expect property name after '.'.")
            else:
                break
        return expr

    proc parse_primary():
        # Boolean literals
        if self.match_tok(token.TOKEN_FALSE):
            return bool_expr(false)
        if self.match_tok(token.TOKEN_TRUE):
            return bool_expr(true)

        # Nil literal
        if self.match_tok(token.TOKEN_NIL):
            return nil_expr()

        # Self keyword (treated as variable)
        if self.match_tok(token.TOKEN_SELF):
            return variable_expr(self.previous())

        # Super keyword: super.method(args) calls parent class method
        if self.match_tok(token.TOKEN_SUPER):
            if self.match_tok(token.TOKEN_DOT) or self.match_tok(token.TOKEN_ARROW):
                if self.check(token.TOKEN_IDENTIFIER) or self.check(token.TOKEN_INIT):
                    let method = self.advance()
                    return super_expr(method)
                let tok = self.peek()
                self.parse_error(tok, "expect method name after 'super.'", "use 'super.init(args)' or 'super.method(args)'")
            let tok = self.peek()
            self.parse_error(tok, "expect '.' or '->' after 'super'", "use 'super.init(args)' to call parent method")

        # comptime expression: comptime(expr) evaluates at compile time
        if self.match_tok(token.TOKEN_COMPTIME):
            self.consume(token.TOKEN_LPAREN, "Expect '(' after 'comptime' in expression context.")
            let inner = self.parse_expression()
            self.consume(token.TOKEN_RPAREN, "Expect ')' after comptime expression.")
            return comptime_expr(inner)

        # Parenthesized expression or tuple
        if self.match_tok(token.TOKEN_LPAREN):
            # Empty tuple: ()
            if self.match_tok(token.TOKEN_RPAREN):
                return tuple_expr([])
            let first = self.parse_expression()
            # Tuple: (a, b, ...)
            if self.match_tok(token.TOKEN_COMMA):
                let elements = []
                push(elements, first)
                if not self.check(token.TOKEN_RPAREN):
                    push(elements, self.parse_expression())
                    while self.match_tok(token.TOKEN_COMMA):
                        if self.check(token.TOKEN_RPAREN):
                            break
                        push(elements, self.parse_expression())
                self.consume(token.TOKEN_RPAREN, "Expect ')' after tuple elements.")
                return tuple_expr(elements)
            # Grouping: (expr)
            self.consume(token.TOKEN_RPAREN, "Expect ')' after expression.")
            return first

        # Dictionary literal: {key: value, ...}
        if self.match_tok(token.TOKEN_LBRACE):
            let keys = []
            let values = []
            if not self.check(token.TOKEN_RBRACE):
                self.consume(token.TOKEN_STRING, "Expect string key in dictionary.")
                let key_tok = self.previous()
                let key_text = unescape_string(slice(key_tok.text, 1, len(key_tok.text) - 1))
                self.consume(token.TOKEN_COLON, "Expect ':' after dictionary key.")
                let val = self.parse_expression()
                push(keys, key_text)
                push(values, val)
                while self.match_tok(token.TOKEN_COMMA):
                    if self.check(token.TOKEN_RBRACE):
                        break
                    self.consume(token.TOKEN_STRING, "Expect string key in dictionary.")
                    let key_tok2 = self.previous()
                    let key_text2 = unescape_string(slice(key_tok2.text, 1, len(key_tok2.text) - 1))
                    self.consume(token.TOKEN_COLON, "Expect ':' after dictionary key.")
                    let val2 = self.parse_expression()
                    push(keys, key_text2)
                    push(values, val2)
            self.consume(token.TOKEN_RBRACE, "Expect '}' after dictionary elements.")
            return dict_expr(keys, values)

        # Array literal: [elem, ...]
        if self.match_tok(token.TOKEN_LBRACKET):
            let elements = []
            if not self.check(token.TOKEN_RBRACKET):
                push(elements, self.parse_expression())
                while self.match_tok(token.TOKEN_COMMA):
                    push(elements, self.parse_expression())
            self.consume(token.TOKEN_RBRACKET, "Expect ']' after array elements.")
            return array_expr(elements)

        # Number literal
        if self.match_tok(token.TOKEN_NUMBER):
            let tok = self.previous()
            let expr = number_expr(parse_number_literal(tok.text))
            expr.text = tok.text
            return expr

        # String literal
        if self.match_tok(token.TOKEN_STRING):
            let tok = self.previous()
            let val = unescape_string(slice(tok.text, 1, len(tok.text) - 1))
            return string_expr(val)

        # Identifier
        if self.match_tok(token.TOKEN_IDENTIFIER):
            return variable_expr(self.previous())

        # Anonymous proc expression (proc literal)
        if self.match_tok(token.TOKEN_PROC):
            return self.parse_proc_expr()

        let tok = self.peek()
        let got_name = token.token_type_name(tok.type)
        let hint = nil
        if got_name == "NEWLINE":
            hint = "unexpected end of line -- expected a value or expression"
        if got_name == "COLON":
            hint = "unexpected ':' -- did you forget the condition?"
        if got_name == "RPAREN":
            hint = "unexpected ')' -- mismatched parentheses?"
        if hint == nil:
            hint = "got " + got_name + " which cannot start an expression"
        self.parse_error(tok, "Expected expression", hint)

    # --- Anonymous proc expression: proc(params): body [end] ---
    proc parse_proc_expr():
        let params = []
        let param_defaults = []
        self.consume(token.TOKEN_LPAREN, "Expect '(' after 'proc' in expression context.")
        if not self.check(token.TOKEN_RPAREN):
            while true:
                if self.check(token.TOKEN_RPAREN):
                    break
                if self.check(token.TOKEN_SELF) or self.check(token.TOKEN_IDENTIFIER):
                    push(params, self.advance())
                    let param_default = nil
                    if self.match_tok(token.TOKEN_ASSIGN):
                        param_default = self.parse_expression()
                    push(param_defaults, param_default)
                else:
                    let tok = self.peek()
                    self.parse_error(tok, "expected parameter name", "parameters must be identifiers")
                if not self.match_tok(token.TOKEN_COMMA):
                    break
        self.consume(token.TOKEN_RPAREN, "Expect ')' after parameters.")
        self.consume(token.TOKEN_COLON, "Expect ':' after procedure signature.")
        let body = nil
        if self.match_tok(token.TOKEN_NEWLINE):
            body = self.parse_block()
        else:
            body = self.parse_declaration()
        self.match_tok(token.TOKEN_END)
        return proc_expr(params, body, param_defaults)

    # --- Statement parsing ---

    proc parse_print():
        let value = self.parse_expression()
        return print_stmt(value)

    proc parse_block():
        self.depth = self.depth + 1
        if self.depth > MAX_DEPTH:
            let tok = self.peek()
            self.parse_error(tok, "Maximum nesting depth exceeded", "reduce the depth of nested blocks")
        while self.match_tok(token.TOKEN_NEWLINE):
            pass
        if self.check(token.TOKEN_END):
            self.advance()
            return block_stmt(nil)
        self.consume(token.TOKEN_INDENT, "Expect indentation after block start.")
        let head = nil
        let current = nil
        while not self.check(token.TOKEN_DEDENT) and not self.check(token.TOKEN_EOF):
            if self.match_tok(token.TOKEN_NEWLINE):
                continue
            let s = self.parse_declaration()
            if s == nil:
                continue
            if head == nil:
                head = s
                current = head
            else:
                current.next = s
                current = s
        self.consume(token.TOKEN_DEDENT, "Expect dedent at end of block.")
        self.depth = self.depth - 1
        return block_stmt(head)

    proc parse_if():
        let condition = self.parse_expression()
        self.consume(token.TOKEN_COLON, "Expect ':' after if condition.")
        let then_branch = nil
        if self.match_tok(token.TOKEN_NEWLINE):
            then_branch = self.parse_block()
        else:
            then_branch = self.parse_declaration()
        let else_branch = nil
        # elif handling: the lexers emit 'elif' as TOKEN_IF. When such a
        # token directly follows this if's block, chain it as the else
        # branch (mirrors if_statement() in the C parser).
        let prev_tok = self.previous()
        if self.check(token.TOKEN_IF) and (prev_tok.type == token.TOKEN_NEWLINE or prev_tok.type == token.TOKEN_DEDENT):
            let cur_tok = self.peek()
            if cur_tok.text == "elif":
                self.advance()
                else_branch = self.parse_if()
        if else_branch == nil and self.match_tok(token.TOKEN_ELSE):
            self.consume(token.TOKEN_COLON, "Expect ':' after else.")
            if self.match_tok(token.TOKEN_NEWLINE):
                else_branch = self.parse_block()
            else:
                else_branch = self.parse_declaration()
        return if_stmt(condition, then_branch, else_branch)

    proc parse_while():
        let condition = self.parse_expression()
        self.consume(token.TOKEN_COLON, "Expect ':' after while condition.")
        let body = nil
        if self.match_tok(token.TOKEN_NEWLINE):
            body = self.parse_block()
        else:
            body = self.parse_declaration()
        return while_stmt(condition, body)

    proc parse_for():
        if not self.check(token.TOKEN_IDENTIFIER):
            let tok = self.peek()
            self.parse_error(tok, "Expected loop variable after 'for'", "for loops require a variable name: for x in ...")
        let var_tok = self.advance()
        self.consume(token.TOKEN_IN, "Expect 'in' after loop variable.")
        let iterable = self.parse_expression()
        self.consume(token.TOKEN_COLON, "Expect ':' after for clause.")
        let body = nil
        if self.match_tok(token.TOKEN_NEWLINE):
            body = self.parse_block()
        else:
            body = self.parse_declaration()
        return for_stmt(var_tok, iterable, body)

    proc parse_proc():
        let name_type = self.peek_type()
        if name_type != token.TOKEN_IDENTIFIER and name_type != token.TOKEN_INIT and name_type != token.TOKEN_PRINT:
            let tok = self.peek()
            self.parse_error(tok, "Expected procedure name", "proc must be followed by a name: proc my_function():")
        let name = self.advance()
        self.consume(token.TOKEN_LPAREN, "Expect '(' after procedure name.")
        let params = []
        let param_type_anns = []
        let param_defaults = []
        if not self.check(token.TOKEN_RPAREN):
            let pt = self.peek_type()
            if pt == token.TOKEN_SELF or pt == token.TOKEN_IDENTIFIER:
                let param_name = self.advance()
                # Check for parameter type annotation: x: Type
                let param_type_ann = nil
                if self.check(token.TOKEN_COLON):
                    self.consume(token.TOKEN_COLON, "Expect parameter type name")
                    let result = parse_type_name(self)
                    let t_text = result[0]
                    let t_kind = result[1]
                    if t_kind != TYPE_UNKNOWN:
                        param_type_ann = t_text
                # Check for default parameter value: x = expr
                let param_default = nil
                if self.match_tok(token.TOKEN_ASSIGN):
                    param_default = self.parse_expression()
                push(params, param_name)
                push(param_type_anns, param_type_ann)
                push(param_defaults, param_default)
            else:
                let tok = self.peek()
                self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
            while self.match_tok(token.TOKEN_COMMA):
                let pt2 = self.peek_type()
                if pt2 == token.TOKEN_SELF or pt2 == token.TOKEN_IDENTIFIER:
                    let param_name = self.advance()
                    let param_type_ann = nil
                    if self.check(token.TOKEN_COLON):
                        self.consume(token.TOKEN_COLON, "Expect parameter type name")
                        let result = parse_type_name(self)
                        let t_text = result[0]
                        let t_kind = result[1]
                        if t_kind != TYPE_UNKNOWN:
                            param_type_ann = t_text
                    let param_default = nil
                    if self.match_tok(token.TOKEN_ASSIGN):
                        param_default = self.parse_expression()
                    push(params, param_name)
                    push(param_type_anns, param_type_ann)
                    push(param_defaults, param_default)
                else:
                    let tok = self.peek()
                    self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
        self.consume(token.TOKEN_RPAREN, "Expect ')' after parameters.")
        
        # Parse return type annotation: proc f() : Int  or  proc f() -> Int
        let ret_type_ann_text = nil
        let ret_type_ann_kind = TYPE_UNKNOWN
        if self.check(token.TOKEN_COLON):
            let saved_pos = self.pos
            self.consume(token.TOKEN_COLON, "Expect return type name")
            if self.check(token.TOKEN_IDENTIFIER):
                let result = parse_type_name(self)
                let t_text = result[0]
                let t_kind = result[1]
                if t_kind != TYPE_UNKNOWN:
                    ret_type_ann_text = t_text
                    ret_type_ann_kind = t_kind
            else:
                # Not a return type annotation, restore position
                self.pos = saved_pos
        if ret_type_ann_text == nil and self.match_tok(token.TOKEN_ARROW):
            let result = parse_type_name(self)
            let t_text = result[0]
            let t_kind = result[1]
            if t_kind != TYPE_UNKNOWN:
                ret_type_ann_text = t_text
                ret_type_ann_kind = t_kind
        
        self.consume(token.TOKEN_COLON, "Expect \":\" after procedure signature.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline before procedure body.")
        let body = self.parse_block()
        return proc_stmt(name, params, body, ret_type_ann_text, param_type_anns, param_defaults)

    proc parse_async_proc():
        self.consume(token.TOKEN_PROC, "Expect 'proc' after 'async'.")
        if not self.check(token.TOKEN_IDENTIFIER):
            let tok = self.peek()
            self.parse_error(tok, "Expected procedure name after 'async proc'", "async proc must be followed by a name")
        let name = self.advance()
        self.consume(token.TOKEN_LPAREN, "Expect '(' after procedure name.")
        let params = []
        let param_defaults = []
        if not self.check(token.TOKEN_RPAREN):
            let pt = self.peek_type()
            if pt == token.TOKEN_SELF or pt == token.TOKEN_IDENTIFIER:
                push(params, self.advance())
                let param_default = nil
                if self.match_tok(token.TOKEN_ASSIGN):
                    param_default = self.parse_expression()
                push(param_defaults, param_default)
            else:
                let tok = self.peek()
                self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
            while self.match_tok(token.TOKEN_COMMA):
                let pt2 = self.peek_type()
                if pt2 == token.TOKEN_SELF or pt2 == token.TOKEN_IDENTIFIER:
                    push(params, self.advance())
                    let param_default = nil
                    if self.match_tok(token.TOKEN_ASSIGN):
                        param_default = self.parse_expression()
                    push(param_defaults, param_default)
                else:
                    let tok = self.peek()
                    self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
        self.consume(token.TOKEN_RPAREN, "Expect ')' after parameters.")
        self.consume(token.TOKEN_COLON, "Expect \":\" after procedure signature.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline before procedure body.")
        let body = self.parse_block()
        return async_proc_stmt(name, params, body, nil, nil, param_defaults)

    proc parse_struct():
        self.consume(token.TOKEN_IDENTIFIER, "Expect struct name.")
        let name = self.previous()
        self.consume(token.TOKEN_COLON, "Expect ':' after struct name.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after struct name.")
        self.consume(token.TOKEN_INDENT, "Expect indentation in struct body.")
        let field_names = []
        let field_types = []
        while not self.check(token.TOKEN_DEDENT) and not self.check(token.TOKEN_EOF):
            if self.match_tok(token.TOKEN_NEWLINE):
                continue
            if self.check(token.TOKEN_DOC_COMMENT):
                self.advance()
                self.match_tok(token.TOKEN_NEWLINE)
                continue
            self.consume(token.TOKEN_IDENTIFIER, "Expect field name.")
            push(field_names, self.previous())
            self.consume(token.TOKEN_COLON, "Expect ':' after field name.")
            # Simple type parsing (identifier for now)
            self.consume(token.TOKEN_IDENTIFIER, "Expect field type.")
            push(field_types, self.previous())
            self.consume(token.TOKEN_NEWLINE, "Expect newline after field.")
        self.consume(token.TOKEN_DEDENT, "Expect dedent after struct body.")
        return struct_stmt(name, field_names, field_types, len(field_names))

    proc parse_enum():
        self.consume(token.TOKEN_IDENTIFIER, "Expect enum name.")
        let name = self.previous()
        self.consume(token.TOKEN_COLON, "Expect ':' after enum name.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after enum header.")
        self.consume(token.TOKEN_INDENT, "Expect indentation in enum body.")
        let variants = []
        while not self.check(token.TOKEN_DEDENT) and not self.check(token.TOKEN_EOF):
            if self.match_tok(token.TOKEN_NEWLINE):
                continue
            if self.check(token.TOKEN_DOC_COMMENT):
                self.advance()
                self.match_tok(token.TOKEN_NEWLINE)
                continue
            self.consume(token.TOKEN_IDENTIFIER, "Expect variant name in enum.")
            push(variants, self.previous())
            self.match_tok(token.TOKEN_NEWLINE)
        self.consume(token.TOKEN_DEDENT, "Expect dedent after enum body.")
        return enum_stmt(name, variants, len(variants))

    proc parse_trait():
        self.consume(token.TOKEN_IDENTIFIER, "Expect trait name.")
        let name = self.previous()
        self.consume(token.TOKEN_COLON, "Expect ':' after trait name.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after trait header.")
        self.consume(token.TOKEN_INDENT, "Expect indentation in trait body.")
        let method_head = nil
        let method_current = nil
        while not self.check(token.TOKEN_DEDENT) and not self.check(token.TOKEN_EOF):
            if self.match_tok(token.TOKEN_NEWLINE):
                continue
            if self.check(token.TOKEN_DOC_COMMENT):
                self.advance()
                self.match_tok(token.TOKEN_NEWLINE)
                continue
            if self.match_tok(token.TOKEN_PROC):
                let method = self.parse_proc()
                if method_head == nil:
                    method_head = method
                    method_current = method
                else:
                    method_current.next = method
                    method_current = method
            else:
                let tok = self.peek()
                self.parse_error(tok, "Only method signatures allowed in trait body", "use 'proc' to define method signatures")
        self.consume(token.TOKEN_DEDENT, "Expect dedent after trait body.")
        return trait_stmt(name, method_head)

    proc parse_macro():
        self.consume(token.TOKEN_IDENTIFIER, "Expect macro name.")
        let name = self.previous()
        self.consume(token.TOKEN_LPAREN, "Expect '(' after macro name.")
        let params = []
        if not self.check(token.TOKEN_RPAREN):
            self.consume(token.TOKEN_IDENTIFIER, "Expect parameter name.")
            push(params, self.previous())
            while self.match_tok(token.TOKEN_COMMA):
                if self.check(token.TOKEN_RPAREN):
                    break
                self.consume(token.TOKEN_IDENTIFIER, "Expect parameter name.")
                push(params, self.previous())
        self.consume(token.TOKEN_RPAREN, "Expect ')' after macro parameters.")
        self.consume(token.TOKEN_COLON, "Expect ':' after macro signature.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline before macro body.")
        let body = self.parse_block()
        return macro_def_stmt(name, params, body)

    proc parse_comptime():
        self.consume(token.TOKEN_COLON, "Expect ':' after 'comptime'.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after 'comptime:'.")
        let body = self.parse_block()
        return comptime_stmt(body)

    proc parse_unsafe():
        self.consume(token.TOKEN_COLON, "Expect ':' after 'unsafe'.")
        if self.match_tok(token.TOKEN_NEWLINE):
            return self.parse_block()
        return self.parse_declaration()

    proc parse_class():
        self.consume(token.TOKEN_IDENTIFIER, "Expect class name.")
        let name = self.previous()
        let parent = nil
        let has_parent = false
        if self.match_tok(token.TOKEN_LPAREN):
            self.consume(token.TOKEN_IDENTIFIER, "Expect parent class name.")
            parent = self.previous()
            self.consume(token.TOKEN_RPAREN, "Expect ')' after parent class.")
            has_parent = true
        self.consume(token.TOKEN_COLON, "Expect ':' after class header.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after class header.")
        self.consume(token.TOKEN_INDENT, "Expect indentation in class body.")
        let method_head = nil
        let method_current = nil
        while not self.check(token.TOKEN_DEDENT) and not self.check(token.TOKEN_EOF):
            if self.match_tok(token.TOKEN_NEWLINE):
                continue
            if self.check(token.TOKEN_DOC_COMMENT):
                self.advance()
                self.match_tok(token.TOKEN_NEWLINE)
                continue
            if self.match_tok(token.TOKEN_PROC):
                let method = self.parse_proc()
                if method_head == nil:
                    method_head = method
                    method_current = method
                else:
                    method_current.next = method
                    method_current = method
            else:
                let tok = self.peek()
                self.parse_error(tok, "Only methods allowed in class body", "use 'proc' to define methods inside a class")
        self.consume(token.TOKEN_DEDENT, "Expect dedent after class body.")
        return class_stmt(name, parent, has_parent, method_head)

    proc parse_try():
        self.consume(token.TOKEN_COLON, "Expect ':' after 'try'.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after try.")
        let try_block = self.parse_block()
        let catches = []
        while self.match_tok(token.TOKEN_CATCH):
            self.consume(token.TOKEN_IDENTIFIER, "Expect exception variable after 'catch'.")
            let exception_var = self.previous()
            self.consume(token.TOKEN_COLON, "Expect ':' after catch variable.")
            self.consume(token.TOKEN_NEWLINE, "Expect newline after catch clause.")
            let catch_body = self.parse_block()
            let clause = CatchClause(exception_var, catch_body)
            push(catches, clause)
        let finally_block = nil
        if self.match_tok(token.TOKEN_FINALLY):
            self.consume(token.TOKEN_COLON, "Expect ':' after 'finally'.")
            self.consume(token.TOKEN_NEWLINE, "Expect newline after finally.")
            finally_block = self.parse_block()
        return try_stmt(try_block, catches, finally_block)

    proc parse_raise():
        let exception = self.parse_expression()
        return raise_stmt(exception)

    proc parse_yield():
        let value = nil
        if not self.check(token.TOKEN_NEWLINE) and not self.check(token.TOKEN_EOF) and not self.check(token.TOKEN_DEDENT):
            value = self.parse_expression()
        return yield_stmt(value)

    proc parse_defer():
        if self.match_tok(token.TOKEN_COLON):
            self.consume(token.TOKEN_NEWLINE, "Expect newline after 'defer:'.")
            let body = self.parse_block()
            return defer_stmt(body)
        let body = self.parse_declaration()
        return defer_stmt(body)

    proc parse_match():
        let value = self.parse_expression()
        self.consume(token.TOKEN_COLON, "Expect ':' after match expression.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after 'match:'.")
        self.consume(token.TOKEN_INDENT, "Expect indented block after 'match:'.")
        let cases = []
        let default_case = nil
        while not self.check(token.TOKEN_DEDENT) and not self.check(token.TOKEN_EOF):
            while self.match_tok(token.TOKEN_NEWLINE):
                pass
            if self.check(token.TOKEN_DEDENT) or self.check(token.TOKEN_EOF):
                break
            if self.match_tok(token.TOKEN_DEFAULT):
                self.consume(token.TOKEN_COLON, "Expect ':' after 'default'.")
                self.consume(token.TOKEN_NEWLINE, "Expect newline after 'default:'.")
                default_case = self.parse_block()
                continue
            if self.match_tok(token.TOKEN_CASE):
                let pattern = self.parse_expression()
                # Optional guard: case PATTERN if CONDITION:
                let guard = nil
                if self.match_tok(token.TOKEN_IF):
                    guard = self.parse_expression()
                self.consume(token.TOKEN_COLON, "Expect ':' after case pattern.")
                self.consume(token.TOKEN_NEWLINE, "Expect newline after case clause.")
                let body = self.parse_block()
                let clause = {}
                clause["pattern"] = pattern
                clause["guard"] = guard
                clause["body"] = body
                push(cases, clause)
                continue
            raise "Expect 'case' or 'default' inside match block"
        if self.check(token.TOKEN_DEDENT):
            self.advance()
        return match_stmt(value, cases, len(cases), default_case)

    proc parse_import():
        # Handle "from module import x, y" form
        if self.match_tok(token.TOKEN_FROM):
            self.consume(token.TOKEN_IDENTIFIER, "Expect module name after 'from'.")
            let module_tok = self.previous()
            let module_name = module_tok.text
            while self.match_tok(token.TOKEN_DOT):
                self.consume(token.TOKEN_IDENTIFIER, "Expect submodule name after '.'.")
                module_name = module_name + "/" + self.previous().text
            self.consume(token.TOKEN_IMPORT, "Expect 'import' after module name.")
            let items = []
            let item_aliases = []
            # Parse first item
            self.consume(token.TOKEN_IDENTIFIER, "Expect identifier in import list.")
            let item_tok = self.previous()
            push(items, item_tok.text)
            if self.match_tok(token.TOKEN_AS):
                self.consume(token.TOKEN_IDENTIFIER, "Expect alias name after 'as'.")
                push(item_aliases, self.previous().text)
            else:
                push(item_aliases, nil)
            # Parse remaining items
            while self.match_tok(token.TOKEN_COMMA):
                self.consume(token.TOKEN_IDENTIFIER, "Expect identifier in import list.")
                let item_tok2 = self.previous()
                push(items, item_tok2.text)
                if self.match_tok(token.TOKEN_AS):
                    self.consume(token.TOKEN_IDENTIFIER, "Expect alias name after 'as'.")
                    push(item_aliases, self.previous().text)
                else:
                    push(item_aliases, nil)
            return import_stmt(module_name, items, item_aliases, nil, 0)

        # Handle "import module [as alias]" form
        self.consume(token.TOKEN_IDENTIFIER, "Expect module name after 'import'.")
        let module_tok = self.previous()
        let module_name = module_tok.text
        while self.match_tok(token.TOKEN_DOT):
            self.consume(token.TOKEN_IDENTIFIER, "Expect submodule name after '.'.")
            module_name = module_name + "/" + self.previous().text
        let alias = nil
        if self.match_tok(token.TOKEN_AS):
            self.consume(token.TOKEN_IDENTIFIER, "Expect alias after 'as'.")
            alias = self.previous().text
        return import_stmt(module_name, [], [], alias, 1)

    proc parse_statement():
        if self.match_tok(token.TOKEN_PRINT):
            return self.parse_print()
        if self.match_tok(token.TOKEN_IF):
            return self.parse_if()
        if self.match_tok(token.TOKEN_WHILE):
            return self.parse_while()
        if self.match_tok(token.TOKEN_FOR):
            return self.parse_for()
        if self.match_tok(token.TOKEN_TRY):
            return self.parse_try()
        if self.match_tok(token.TOKEN_RAISE):
            return self.parse_raise()
        if self.match_tok(token.TOKEN_YIELD):
            return self.parse_yield()
        if self.match_tok(token.TOKEN_DEFER):
            return self.parse_defer()
        if self.match_tok(token.TOKEN_MATCH):
            return self.parse_match()
        if self.match_tok(token.TOKEN_COMPTIME):
            return self.parse_comptime()
        if self.match_tok(token.TOKEN_UNSAFE):
            return self.parse_unsafe()
        if self.match_tok(token.TOKEN_BREAK):
            return break_stmt()
        if self.match_tok(token.TOKEN_CONTINUE):
            return continue_stmt()
        if self.match_tok(token.TOKEN_END):
            return expr_stmt(nil_expr())
        let expr = self.parse_expression()
        return expr_stmt(expr)

    proc attach_pragmas(stmt, pragmas):
        if stmt != nil and pragmas != nil:
            stmt.pragmas = pragmas

    proc collect_pragmas():
        var pragma_list = nil
        while self.check(token.TOKEN_AT):
            self.advance()  # consume '@'
            let tok = self.consume(token.TOKEN_IDENTIFIER, "Expect pragma name after '@'.")
            let p = {"name": tok.text, "args": [], "next": pragma_list}
            pragma_list = p
            # Skip optional newlines between pragmas
            self.match_tok(token.TOKEN_NEWLINE)
            while self.match_tok(token.TOKEN_NEWLINE):
                pass
        return pragma_list

    proc parse_declaration():
        # Skip newlines
        while self.match_tok(token.TOKEN_NEWLINE):
            pass

        if self.check(token.TOKEN_DEDENT) or self.check(token.TOKEN_EOF):
            return nil

        # Collect doc comments before declarations
        if self.check(token.TOKEN_DOC_COMMENT):
            self.collect_doc_comment()
            while self.match_tok(token.TOKEN_NEWLINE):
                pass

        # Collect @pragma decorators
        let pragmas = self.collect_pragmas()

        # Class declaration
        if self.match_tok(token.TOKEN_CLASS):
            let s = self.parse_class()
            s.doc = self.take_pending_doc()
            self.attach_pragmas(s, pragmas)
            return s

        # Struct declaration
        if self.match_tok(token.TOKEN_STRUCT):
            let s = self.parse_struct()
            s.doc = self.take_pending_doc()
            self.attach_pragmas(s, pragmas)
            return s

        # Enum declaration
        if self.match_tok(token.TOKEN_ENUM):
            let s = self.parse_enum()
            s.doc = self.take_pending_doc()
            self.attach_pragmas(s, pragmas)
            return s

        # Trait declaration
        if self.match_tok(token.TOKEN_TRAIT):
            let s = self.parse_trait()
            s.doc = self.take_pending_doc()
            self.attach_pragmas(s, pragmas)
            return s

        # Macro definition
        if self.match_tok(token.TOKEN_MACRO):
            let s = self.parse_macro()
            s.doc = self.take_pending_doc()
            self.attach_pragmas(s, pragmas)
            return s

        # Async proc declaration
        if self.match_tok(token.TOKEN_ASYNC):
            let s = self.parse_async_proc()
            s.doc = self.take_pending_doc()
            self.attach_pragmas(s, pragmas)
            return s

        # Proc declaration
        if self.match_tok(token.TOKEN_PROC):
            let s = self.parse_proc()
            s.doc = self.take_pending_doc()
            self.attach_pragmas(s, pragmas)
            return s

        # Import statements
        if self.match_tok(token.TOKEN_IMPORT) or self.check(token.TOKEN_FROM):
            let s = self.parse_import()
            self.match_tok(token.TOKEN_NEWLINE)
            self.attach_pragmas(s, pragmas)
            return s

        # Return statement
        if self.match_tok(token.TOKEN_RETURN):
            let value = nil
            if not self.check(token.TOKEN_NEWLINE) and not self.check(token.TOKEN_EOF) and not self.check(token.TOKEN_DEDENT):
                value = self.parse_expression()
            self.match_tok(token.TOKEN_NEWLINE)
            let s = return_stmt(value)
            self.attach_pragmas(s, pragmas)
            return s

        # Let/var declaration
        if self.match_tok(token.TOKEN_LET) or self.match_tok(token.TOKEN_VAR):
            let name = nil
            if self.check(token.TOKEN_IDENTIFIER) or self.check(token.TOKEN_PRINT):
                name = self.advance()
            else:
                self.consume(token.TOKEN_IDENTIFIER, "Expect variable name.")
            let type_ann_text = nil
            let type_ann_kind = TYPE_UNKNOWN
            if self.check(token.TOKEN_COLON):
                self.consume(token.TOKEN_COLON, "Expect type name after \":\"")
                let result = parse_type_name(self)
                let t_text = result[0]
                let t_kind = result[1]
                if t_kind != TYPE_UNKNOWN:
                    type_ann_text = t_text
                    type_ann_kind = t_kind
            let initializer = nil
            if self.match_tok(token.TOKEN_ASSIGN):
                initializer = self.parse_expression_rhs()
            let s = let_stmt(name, initializer, type_ann_text)
            self.attach_pragmas(s, pragmas)
            return s

        # General statement
        let s = self.parse_statement()
        self.attach_pragmas(s, pragmas)
        self.match_tok(token.TOKEN_NEWLINE)
        return s

    # --- Top-level parse function ---

    proc parse_program():
        let stmts = []
        while not self.check(token.TOKEN_EOF):
            if self.match_tok(token.TOKEN_NEWLINE):
                continue
            let s = self.parse_declaration()
            if s != nil:
                push(stmts, s)
        return stmts

# -----------------------------------------
# Public API: parse source code into AST
# -----------------------------------------

proc parse_source(source):
    return parse_source_file(source, "<input>")

proc parse_source_file(source, filename):
    let tokens = tokenize(source)
    let p = Parser(tokens, source, filename)
    return p.parse_program()
