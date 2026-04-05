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
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC, STMT_DEFER
from ast import number_expr, string_expr, bool_expr, nil_expr
from ast import binary_expr, variable_expr, call_expr, array_expr
from ast import index_expr, index_set_expr, dict_expr, tuple_expr
from ast import slice_expr, get_expr, set_expr, await_expr
from ast import print_stmt, expr_stmt, let_stmt, if_stmt
from ast import block_stmt, while_stmt, proc_stmt, for_stmt
from ast import return_stmt, break_stmt, continue_stmt, class_stmt
from ast import try_stmt, raise_stmt, yield_stmt, import_stmt
from ast import async_proc_stmt, defer_stmt

# Maximum parser recursion depth
let MAX_DEPTH = 500

proc parse_number_literal(text):
    if len(text) >= 2 and text[0] == "0" and (text[1] == "b" or text[1] == "B"):
        let value = 0
        let i = 2
        while i < len(text):
            value = value * 2
            if text[i] == "1":
                value = value + 1
            i = i + 1
        return value
    return tonumber(text)

class Parser:
    proc init(tokens, source, filename):
        self.tokens = tokens
        self.pos = 0
        self.depth = 0
        self.source = source
        self.filename = filename
        self.error_ctx = nil

    proc get_error_ctx():
        if self.error_ctx == nil:
            self.error_ctx = errors.make_error_context(self.source, self.filename)
        return self.error_ctx

    proc parse_error(tok, message, hint):
        let ctx = self.get_error_ctx()
        let col = -1
        let formatted = errors.format_error(ctx, tok.line, col, "Error", message, hint)
        raise formatted

    # --- Token access ---

    proc peek():
        return self.tokens[self.pos]

    proc peek_type():
        return self.tokens[self.pos].type

    proc advance():
        let tok = self.tokens[self.pos]
        self.pos = self.pos + 1
        return tok

    proc previous():
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
            elif self.match_tok(token.TOKEN_DOT):
                # Property access
                self.consume(token.TOKEN_IDENTIFIER, "Expect property name after '.'.")
                let prop = self.previous()
                expr = get_expr(expr, prop)
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
                let key_text = slice(key_tok.text, 1, len(key_tok.text) - 1)
                self.consume(token.TOKEN_COLON, "Expect ':' after dictionary key.")
                let val = self.parse_expression()
                push(keys, key_text)
                push(values, val)
                while self.match_tok(token.TOKEN_COMMA):
                    if self.check(token.TOKEN_RBRACE):
                        break
                    self.consume(token.TOKEN_STRING, "Expect string key in dictionary.")
                    let key_tok2 = self.previous()
                    let key_text2 = slice(key_tok2.text, 1, len(key_tok2.text) - 1)
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
            let val = slice(tok.text, 1, len(tok.text) - 1)
            return string_expr(val)

        # Identifier
        if self.match_tok(token.TOKEN_IDENTIFIER):
            return variable_expr(self.previous())

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

    # --- Statement parsing ---

    proc parse_print():
        let value = self.parse_expression()
        return print_stmt(value)

    proc parse_block():
        self.depth = self.depth + 1
        if self.depth > MAX_DEPTH:
            let tok = self.peek()
            self.parse_error(tok, "Maximum nesting depth exceeded", "reduce the depth of nested blocks")
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
        self.consume(token.TOKEN_NEWLINE, "Expect newline after if condition.")
        let then_branch = self.parse_block()
        let else_branch = nil
        if self.match_tok(token.TOKEN_ELSE):
            self.consume(token.TOKEN_COLON, "Expect ':' after else.")
            self.consume(token.TOKEN_NEWLINE, "Expect newline after else.")
            else_branch = self.parse_block()
        return if_stmt(condition, then_branch, else_branch)

    proc parse_while():
        let condition = self.parse_expression()
        self.consume(token.TOKEN_COLON, "Expect ':' after while condition.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after while condition.")
        let body = self.parse_block()
        return while_stmt(condition, body)

    proc parse_for():
        if not self.check(token.TOKEN_IDENTIFIER):
            let tok = self.peek()
            self.parse_error(tok, "Expected loop variable after 'for'", "for loops require a variable name: for x in ...")
        let var_tok = self.advance()
        self.consume(token.TOKEN_IN, "Expect 'in' after loop variable.")
        let iterable = self.parse_expression()
        self.consume(token.TOKEN_COLON, "Expect ':' after for clause.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline after for clause.")
        let body = self.parse_block()
        return for_stmt(var_tok, iterable, body)

    proc parse_proc():
        let name_type = self.peek_type()
        if name_type != token.TOKEN_IDENTIFIER and name_type != token.TOKEN_INIT:
            let tok = self.peek()
            self.parse_error(tok, "Expected procedure name", "proc must be followed by a name: proc my_function():")
        let name = self.advance()
        self.consume(token.TOKEN_LPAREN, "Expect '(' after procedure name.")
        let params = []
        if not self.check(token.TOKEN_RPAREN):
            let pt = self.peek_type()
            if pt == token.TOKEN_SELF or pt == token.TOKEN_IDENTIFIER:
                push(params, self.advance())
            else:
                let tok = self.peek()
                self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
            while self.match_tok(token.TOKEN_COMMA):
                let pt2 = self.peek_type()
                if pt2 == token.TOKEN_SELF or pt2 == token.TOKEN_IDENTIFIER:
                    push(params, self.advance())
                else:
                    let tok = self.peek()
                    self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
        self.consume(token.TOKEN_RPAREN, "Expect ')' after parameters.")
        self.consume(token.TOKEN_COLON, "Expect ':' after procedure signature.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline before procedure body.")
        let body = self.parse_block()
        return proc_stmt(name, params, body)

    proc parse_async_proc():
        self.consume(token.TOKEN_PROC, "Expect 'proc' after 'async'.")
        if not self.check(token.TOKEN_IDENTIFIER):
            let tok = self.peek()
            self.parse_error(tok, "Expected procedure name after 'async proc'", "async proc must be followed by a name")
        let name = self.advance()
        self.consume(token.TOKEN_LPAREN, "Expect '(' after procedure name.")
        let params = []
        if not self.check(token.TOKEN_RPAREN):
            let pt = self.peek_type()
            if pt == token.TOKEN_SELF or pt == token.TOKEN_IDENTIFIER:
                push(params, self.advance())
            else:
                let tok = self.peek()
                self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
            while self.match_tok(token.TOKEN_COMMA):
                let pt2 = self.peek_type()
                if pt2 == token.TOKEN_SELF or pt2 == token.TOKEN_IDENTIFIER:
                    push(params, self.advance())
                else:
                    let tok = self.peek()
                    self.parse_error(tok, "Expected parameter name", "parameters must be identifiers")
        self.consume(token.TOKEN_RPAREN, "Expect ')' after parameters.")
        self.consume(token.TOKEN_COLON, "Expect ':' after procedure signature.")
        self.consume(token.TOKEN_NEWLINE, "Expect newline before procedure body.")
        let body = self.parse_block()
        return async_proc_stmt(name, params, body)

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
        let body = self.parse_statement()
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
                self.consume(token.TOKEN_COLON, "Expect ':' after case pattern.")
                self.consume(token.TOKEN_NEWLINE, "Expect newline after case clause.")
                let body = self.parse_block()
                let clause = {}
                clause["pattern"] = pattern
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
        if self.match_tok(token.TOKEN_BREAK):
            return break_stmt()
        if self.match_tok(token.TOKEN_CONTINUE):
            return continue_stmt()
        # 'end' keyword: optional block terminator (blocks use INDENT/DEDENT)
        if self.match_tok(token.TOKEN_END):
            return expr_stmt(literal_expr(0))
        let expr = self.parse_expression()
        return expr_stmt(expr)

    proc parse_declaration():
        # Skip newlines
        while self.match_tok(token.TOKEN_NEWLINE):
            pass

        if self.check(token.TOKEN_DEDENT) or self.check(token.TOKEN_EOF):
            return nil

        # Class declaration
        if self.match_tok(token.TOKEN_CLASS):
            return self.parse_class()

        # Async proc declaration
        if self.match_tok(token.TOKEN_ASYNC):
            return self.parse_async_proc()

        # Proc declaration
        if self.match_tok(token.TOKEN_PROC):
            return self.parse_proc()

        # Import statements
        if self.match_tok(token.TOKEN_IMPORT) or self.check(token.TOKEN_FROM):
            let s = self.parse_import()
            self.match_tok(token.TOKEN_NEWLINE)
            return s

        # Return statement
        if self.match_tok(token.TOKEN_RETURN):
            let value = nil
            if not self.check(token.TOKEN_NEWLINE) and not self.check(token.TOKEN_EOF) and not self.check(token.TOKEN_DEDENT):
                value = self.parse_expression()
            self.match_tok(token.TOKEN_NEWLINE)
            return return_stmt(value)

        # Let/var declaration
        if self.match_tok(token.TOKEN_LET) or self.match_tok(token.TOKEN_VAR):
            self.consume(token.TOKEN_IDENTIFIER, "Expect variable name.")
            let name = self.previous()
            let initializer = nil
            if self.match_tok(token.TOKEN_ASSIGN):
                initializer = self.parse_expression()
            let s = let_stmt(name, initializer)
            self.match_tok(token.TOKEN_NEWLINE)
            return s

        # General statement
        let s = self.parse_statement()
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
