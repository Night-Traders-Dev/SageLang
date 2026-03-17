#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "diagnostic.h"
#include "lexer.h"
#include "parser.h"
#include "ast.h"
#include "token.h"
#include "gc.h"
#include "repl.h"

static Token current_token;
static Token previous_token;

// Parser recursion depth limit to prevent stack overflow on malicious input
#define MAX_PARSER_DEPTH 500
static int parser_depth = 0;

static int token_span(const Token* token) {
    return (token != NULL && token->length > 0) ? token->length : 1;
}

static void parser_report(Token token, int span, const char* message, const char* help) {
    sage_print_token_diagnosticf("error", &token, NULL, span > 0 ? span : 1,
                                 help, "%s", message);
    sage_error_exit();
}

static const char* parser_expected_help(TokenType expected, Token got) {
    switch (expected) {
        case TOKEN_COLON:
            if (got.type == TOKEN_NEWLINE || got.type == TOKEN_EOF) {
                return "add ':' before the end of the line to start the block";
            }
            return "blocks in Sage start with ':'";
        case TOKEN_NEWLINE:
            if (got.type == TOKEN_EOF) {
                return "add a newline to finish this statement";
            }
            return "put the block on the next line after ':'";
        case TOKEN_IDENTIFIER:
            return "identifiers start with a letter or '_'";
        case TOKEN_RPAREN:
            return "check for a missing ')' earlier in this expression";
        case TOKEN_RBRACKET:
            return "check for a missing ']'";
        case TOKEN_RBRACE:
            return "check for a missing '}'";
        default:
            break;
    }

    if (got.type == TOKEN_NEWLINE) {
        return "this line ended before the statement was complete";
    }
    if (got.type == TOKEN_EOF) {
        return "the file ended before the statement was complete";
    }
    return NULL;
}

static void parser_expected_error(Token token, TokenType expected, const char* message) {
    char formatted[512];
    const char* found = sage_token_display_name(token.type);
    size_t message_len = strlen(message);
    if (message_len > 0 && message[message_len - 1] == '.') {
        message_len--;
    }

    if (strncmp(message, "Expect ", 7) == 0 && message_len > 7) {
        snprintf(formatted, sizeof(formatted), "expected %.*s, found %s",
                 (int)(message_len - 7), message + 7, found);
    } else {
        snprintf(formatted, sizeof(formatted), "%.*s (found %s)",
                 (int)message_len, message, found);
    }

    parser_report(token, token_span(&token), formatted,
                  parser_expected_help(expected, token));
}

static const char* parser_expression_help(Token token) {
    switch (token.type) {
        case TOKEN_NEWLINE:
            return "the line ended where Sage expected a value or expression";
        case TOKEN_COLON:
            return "did you forget the condition or value before ':'?";
        case TOKEN_RPAREN:
            return "there may be an extra ')'";
        case TOKEN_RBRACKET:
            return "there may be an extra ']'";
        case TOKEN_RBRACE:
            return "there may be an extra '}'";
        case TOKEN_EOF:
            return "the file ended before the expression was complete";
        default:
            return "expressions can start with names, literals, '(', '[', or '{'";
    }
}

static void advance_parser(void) {
    previous_token = current_token;
    current_token = scan_token();
    if (current_token.type == TOKEN_ERROR) {
        parser_report(current_token, 1, current_token.start, NULL);
    }
}

void parser_init(void) {
    advance_parser();
}

ParserState parser_get_state(void) {
    ParserState state;
    state.current_token = current_token;
    state.previous_token = previous_token;
    return state;
}

void parser_set_state(ParserState state) {
    current_token = state.current_token;
    previous_token = state.previous_token;
}

static int check(TokenType type) {
    return current_token.type == type;
}

static int match(TokenType type) {
    if (current_token.type == type) {
        advance_parser();
        return 1;
    }
    return 0;
}

static void consume(TokenType type, const char* message) {
    if (current_token.type == type) {
        advance_parser();
        return;
    }
    parser_expected_error(current_token, type, message);
}

static double parse_number_literal(Token token) {
    if (token.length >= 2 && token.start[0] == '0' &&
        (token.start[1] == 'b' || token.start[1] == 'B')) {
        double value = 0;
        for (int i = 2; i < token.length; i++) {
            value = (value * 2) + (token.start[i] - '0');
        }
        return value;
    }

    char inline_buffer[128];
    char* heap_buffer = NULL;
    char* parse_buffer = inline_buffer;

    if (token.length >= (int)sizeof(inline_buffer)) {
        heap_buffer = SAGE_ALLOC((size_t)token.length + 1);
        parse_buffer = heap_buffer;
    }

    memcpy(parse_buffer, token.start, (size_t)token.length);
    parse_buffer[token.length] = '\0';

    double value = strtod(parse_buffer, NULL);
    free(heap_buffer);
    return value;
}

// Forward declarations
static Expr* expression(void);
static Expr* unary(void);
static Expr* postfix(void);
static Stmt* declaration(void);
static Stmt* statement(void);
static Stmt* block(void);

static Stmt* for_statement() {
    if (!check(TOKEN_IDENTIFIER)) {
        parser_report(current_token, token_span(&current_token),
                      "expected loop variable after 'for'",
                      "for loops need a variable name: for item in values:");
    }
    
    Token var = current_token;
    advance_parser();

    consume(TOKEN_IN, "Expect 'in' after loop variable.");

    Expr* iterable = expression();
    consume(TOKEN_COLON, "Expect ':' after for clause.");
    consume(TOKEN_NEWLINE, "Expect newline after for clause.");

    Stmt* body = block();

    return new_for_stmt(var, iterable, body);
}

// PHASE 7: Try/catch/finally statement
static Stmt* try_statement() {
    // try:
    consume(TOKEN_COLON, "Expect ':' after 'try'.");
    consume(TOKEN_NEWLINE, "Expect newline after try.");
    Stmt* try_block = block();
    
    // Parse catch clauses
    CatchClause** catches = NULL;
    int catch_count = 0;
    int catch_capacity = 0;
    
    while (match(TOKEN_CATCH)) {
        // catch e:
        consume(TOKEN_IDENTIFIER, "Expect exception variable after 'catch'.");
        Token exception_var = previous_token;
        
        consume(TOKEN_COLON, "Expect ':' after catch variable.");
        consume(TOKEN_NEWLINE, "Expect newline after catch clause.");
        Stmt* catch_body = block();
        
        CatchClause* clause = new_catch_clause(exception_var, catch_body);
        
        if (catch_count >= catch_capacity) {
            catch_capacity = catch_capacity == 0 ? 2 : catch_capacity * 2;
            catches = SAGE_REALLOC(catches, sizeof(CatchClause*) * catch_capacity);
        }
        catches[catch_count++] = clause;
    }
    
    // Optional finally:
    Stmt* finally_block = NULL;
    if (match(TOKEN_FINALLY)) {
        consume(TOKEN_COLON, "Expect ':' after 'finally'.");
        consume(TOKEN_NEWLINE, "Expect newline after finally.");
        finally_block = block();
    }
    
    return new_try_stmt(try_block, catches, catch_count, finally_block);
}

// PHASE 7: Raise statement  
static Stmt* raise_statement() {
    // raise expression
    Expr* exception = expression();
    return new_raise_stmt(exception);
}

// PHASE 7: Yield statement
static Stmt* yield_statement() {
    // yield <expression>
    // yield can also be used without a value: yield (yields nil)
    Expr* value = NULL;
    
    if (!check(TOKEN_NEWLINE) && !check(TOKEN_EOF) && !check(TOKEN_DEDENT)) {
        value = expression();
    }
    
    return new_yield_stmt(value);
}

// PHASE 8: Import statement - WITH ALIASING SUPPORT
static Stmt* import_statement() {
    // Three forms:
    // 1. import module_name
    // 2. import module_name as alias
    // 3. from module_name import item1, item2, ...
    // 4. from module_name import item1 as alias1, item2 as alias2
    
    if (match(TOKEN_FROM)) {
        // from module_name import item1 [as alias1], item2 [as alias2], ...
        consume(TOKEN_IDENTIFIER, "Expect module name after 'from'.");
        Token module_token = previous_token;
        
        // Copy module name
        char* module_name = SAGE_ALLOC(module_token.length + 1);
        memcpy(module_name, module_token.start, module_token.length);
        module_name[module_token.length] = '\0';
        
        consume(TOKEN_IMPORT, "Expect 'import' after module name.");
        
        // Parse imported items and their aliases
        char** items = NULL;
        char** item_aliases = NULL;  // ✅ NEW: Store aliases
        int item_count = 0;
        int capacity = 0;
        
        do {
            consume(TOKEN_IDENTIFIER, "Expect identifier in import list.");
            Token item_token = previous_token;
            
            if (item_count >= capacity) {
                capacity = capacity == 0 ? 4 : capacity * 2;
                items = SAGE_REALLOC(items, sizeof(char*) * capacity);
                item_aliases = SAGE_REALLOC(item_aliases, sizeof(char*) * capacity);  // ✅ NEW
            }
            
            // Store the original item name
            items[item_count] = SAGE_ALLOC(item_token.length + 1);
            memcpy(items[item_count], item_token.start, item_token.length);
            items[item_count][item_token.length] = '\0';
            
            // ✅ NEW: Check for 'as alias'
            if (match(TOKEN_AS)) {
                consume(TOKEN_IDENTIFIER, "Expect alias name after 'as'.");
                Token alias_token = previous_token;
                
                item_aliases[item_count] = SAGE_ALLOC(alias_token.length + 1);
                memcpy(item_aliases[item_count], alias_token.start, alias_token.length);
                item_aliases[item_count][alias_token.length] = '\0';
            } else {
                item_aliases[item_count] = NULL;  // No alias for this item
            }
            
            item_count++;
            
        } while (match(TOKEN_COMMA));
        
        return new_import_stmt(module_name, items, item_aliases, item_count, NULL, 0);
    }
    
    // import module_name [as alias]
    consume(TOKEN_IDENTIFIER, "Expect module name after 'import'.");
    Token module_token = previous_token;
    
    char* module_name = SAGE_ALLOC(module_token.length + 1);
    memcpy(module_name, module_token.start, module_token.length);
    module_name[module_token.length] = '\0';
    
    char* alias = NULL;
    if (match(TOKEN_AS)) {
        consume(TOKEN_IDENTIFIER, "Expect alias after 'as'.");
        Token alias_token = previous_token;
        
        alias = SAGE_ALLOC(alias_token.length + 1);
        memcpy(alias, alias_token.start, alias_token.length);
        alias[alias_token.length] = '\0';
    }
    
    // import_all = 1 (importing entire module)
    // item_aliases = NULL (not used for module-level imports)
    return new_import_stmt(module_name, NULL, NULL, 0, alias, 1);
}

// primary -> NUMBER | STRING | BOOLEAN | NIL | SELF | ( expr/tuple ) | [ array ] | { dict } | IDENTIFIER | CALL
static Expr* primary() {
    // Literals
    if (match(TOKEN_FALSE)) return new_bool_expr(0);
    if (match(TOKEN_TRUE))  return new_bool_expr(1);
    if (match(TOKEN_NIL))   return new_nil_expr();
    
    // Self keyword (treated as variable)
    if (match(TOKEN_SELF)) {
        Token self_token = previous_token;
        return new_variable_expr(self_token);
    }

    // Parentheses: ( expr ) or tuple (a, b, c)
    if (match(TOKEN_LPAREN)) {
        if (match(TOKEN_RPAREN)) {
            return new_tuple_expr(NULL, 0);
        }

        Expr* first = expression();
        
        if (match(TOKEN_COMMA)) {
            Expr** elements = NULL;
            int count = 0;
            int capacity = 4;
            elements = SAGE_ALLOC(sizeof(Expr*) * capacity);
            elements[count++] = first;
            
            if (!check(TOKEN_RPAREN)) {
                do {
                    if (count >= capacity) {
                        capacity *= 2;
                        elements = SAGE_REALLOC(elements, sizeof(Expr*) * capacity);
                    }
                    elements[count++] = expression();
                } while (match(TOKEN_COMMA) && !check(TOKEN_RPAREN));
            }
            
            consume(TOKEN_RPAREN, "Expect ')' after tuple elements.");
            return new_tuple_expr(elements, count);
        }
        
        consume(TOKEN_RPAREN, "Expect ')' after expression.");
        return first;
    }

    // Dictionary Literals
    if (match(TOKEN_LBRACE)) {
        char** keys = NULL;
        Expr** values = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RBRACE)) {
            do {
                consume(TOKEN_STRING, "Expect string key in dictionary.");
                Token key_token = previous_token;
                
                int len = key_token.length - 2;
                char* key = SAGE_ALLOC(len + 1);
                memcpy(key, key_token.start + 1, len);
                key[len] = '\0';
                
                consume(TOKEN_COLON, "Expect ':' after dictionary key.");
                Expr* value = expression();
                
                if (count >= capacity) {
                    capacity = capacity == 0 ? 4 : capacity * 2;
                    keys = SAGE_REALLOC(keys, sizeof(char*) * capacity);
                    values = SAGE_REALLOC(values, sizeof(Expr*) * capacity);
                }
                keys[count] = key;
                values[count] = value;
                count++;
            } while (match(TOKEN_COMMA) && !check(TOKEN_RBRACE));
        }
        
        consume(TOKEN_RBRACE, "Expect '}' after dictionary elements.");
        return new_dict_expr(keys, values, count);
    }

    // Array Literals
    if (match(TOKEN_LBRACKET)) {
        Expr** elements = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RBRACKET)) {
            do {
                Expr* elem = expression();
                if (count >= capacity) {
                    capacity = capacity == 0 ? 4 : capacity * 2;
                    elements = SAGE_REALLOC(elements, sizeof(Expr*) * capacity);
                }
                elements[count++] = elem;
            } while (match(TOKEN_COMMA));
        }
        consume(TOKEN_RBRACKET, "Expect ']' after array elements.");
        return new_array_expr(elements, count);
    }

    // Numbers
    if (match(TOKEN_NUMBER)) {
        double val = parse_number_literal(previous_token);
        return new_number_expr(val);
    }

    // Strings
    if (match(TOKEN_STRING)) {
        Token t = previous_token;
        int len = t.length - 2;
        char* str = SAGE_ALLOC(len + 1);
        memcpy(str, t.start + 1, len);
        str[len] = '\0';
        return new_string_expr(str);
    }

    // Identifiers
    if (match(TOKEN_IDENTIFIER)) {
        Token name = previous_token;
        return new_variable_expr(name);
    }

    {
        char message[256];
        snprintf(message, sizeof(message), "expected expression, found %s",
                 sage_token_display_name(current_token.type));
        parser_report(current_token, token_span(&current_token), message,
                      parser_expression_help(current_token));
    }
    return NULL;
}

// Unary expressions (handle negative numbers and bitwise NOT)
static Expr* unary() {
    // Handle unary minus: -5, -x
    if (match(TOKEN_MINUS)) {
        Token op = previous_token;
        Expr* right = unary();  // Right associative
        // Represent -x as (0 - x)
        return new_binary_expr(new_number_expr(0), op, right);
    }
    if (match(TOKEN_NOT)) {
        Token op = previous_token;
        Expr* right = unary();
        return new_binary_expr(right, op, NULL);
    }
    // Phase 9: Bitwise NOT (~x)
    if (match(TOKEN_TILDE)) {
        Token op = previous_token;
        Expr* right = unary();
        return new_binary_expr(right, op, NULL);
    }
    // Phase 11: await expression
    if (match(TOKEN_AWAIT)) {
        Expr* right = unary();
        return new_await_expr(right);
    }

    return postfix();
}

static Expr* postfix() {
    Expr* expr = primary();

    while (1) {
        if (match(TOKEN_LPAREN)) {
            Expr** args = NULL;
            int count = 0;
            int capacity = 0;

            if (!check(TOKEN_RPAREN)) {
                do {
                    Expr* arg = expression();
                    if (count >= capacity) {
                        capacity = capacity == 0 ? 4 : capacity * 2;
                        args = SAGE_REALLOC(args, sizeof(Expr*) * capacity);
                    }
                    args[count++] = arg;
                } while (match(TOKEN_COMMA));
            }
            consume(TOKEN_RPAREN, "Expect ')' after arguments.");
            expr = new_call_expr(expr, args, count);
        } else if (match(TOKEN_LBRACKET)) {
            Expr* start_or_index = NULL;
            Expr* end = NULL;
            
            if (!check(TOKEN_COLON)) {
                start_or_index = expression();
            }
            
            if (match(TOKEN_COLON)) {
                Expr* start = start_or_index;
                
                if (!check(TOKEN_RBRACKET)) {
                    end = expression();
                }
                
                consume(TOKEN_RBRACKET, "Expect ']' after slice.");
                expr = new_slice_expr(expr, start, end);
            } else {
                consume(TOKEN_RBRACKET, "Expect ']' after index.");
                expr = new_index_expr(expr, start_or_index);
            }
        } else if (match(TOKEN_DOT)) {
            consume(TOKEN_IDENTIFIER, "Expect property name after '.'.");
            Token property = previous_token;
            expr = new_get_expr(expr, property);
        } else {
            break;
        }
    }

    return expr;
}

static Expr* term() {
    Expr* expr = unary();
    while (match(TOKEN_STAR) || match(TOKEN_SLASH) || match(TOKEN_PERCENT)) {
        Token op = previous_token;
        Expr* right = unary();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* addition() {
    Expr* expr = term();
    while (match(TOKEN_PLUS) || match(TOKEN_MINUS)) {
        Token op = previous_token;
        Expr* right = term();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

// Phase 9: Shift operators (<< >>), between addition and comparison
static Expr* shift() {
    Expr* expr = addition();
    while (match(TOKEN_LSHIFT) || match(TOKEN_RSHIFT)) {
        Token op = previous_token;
        Expr* right = addition();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* comparison() {
    Expr* expr = shift();
    while (match(TOKEN_GT) || match(TOKEN_LT) || match(TOKEN_GTE) || match(TOKEN_LTE)) {
        Token op = previous_token;
        Expr* right = shift();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* equality() {
    Expr* expr = comparison();
    while (match(TOKEN_EQ) || match(TOKEN_NEQ)) {
        Token op = previous_token;
        Expr* right = comparison();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

// Phase 9: Bitwise AND (&), between equality and bitwise XOR
static Expr* bitwise_and() {
    Expr* expr = equality();
    while (match(TOKEN_AMP)) {
        Token op = previous_token;
        Expr* right = equality();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

// Phase 9: Bitwise XOR (^), between bitwise AND and bitwise OR
static Expr* bitwise_xor() {
    Expr* expr = bitwise_and();
    while (match(TOKEN_CARET)) {
        Token op = previous_token;
        Expr* right = bitwise_and();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

// Phase 9: Bitwise OR (|), between bitwise XOR and logical AND
static Expr* bitwise_or() {
    Expr* expr = bitwise_xor();
    while (match(TOKEN_PIPE)) {
        Token op = previous_token;
        Expr* right = bitwise_xor();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* logical_and() {
    Expr* expr = bitwise_or();
    while (match(TOKEN_AND)) {
        Token op = previous_token;
        Expr* right = bitwise_or();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* logical_or() {
    Expr* expr = logical_and();
    while (match(TOKEN_OR)) {
        Token op = previous_token;
        Expr* right = logical_and();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

static Expr* assignment() {
    Expr* expr = logical_or();
    
    if (expr->type == EXPR_GET && match(TOKEN_ASSIGN)) {
        Expr* object = expr->as.get.object;
        Token property = expr->as.get.property;
        free(expr);
        Expr* value = assignment();
        return new_set_expr(object, property, value);
    }
    
    // Handle index assignment: arr[i] = value, dict[key] = value
    if (expr->type == EXPR_INDEX && match(TOKEN_ASSIGN)) {
        Expr* array = expr->as.index.array;
        Expr* index = expr->as.index.index;
        free(expr);
        Expr* value = assignment();
        return new_index_set_expr(array, index, value);
    }

    // Handle regular variable assignment: x = value
    if (expr->type == EXPR_VARIABLE && match(TOKEN_ASSIGN)) {
        Token name = expr->as.variable.name;
        free(expr);
        Expr* value = assignment();
        return new_set_expr(NULL, name, value);
    }

    return expr;
}

static Expr* expression() {
    if (++parser_depth > MAX_PARSER_DEPTH) {
        char message[128];
        snprintf(message, sizeof(message),
                 "maximum nesting depth exceeded (%d)", MAX_PARSER_DEPTH);
        parser_report(current_token, 1, message,
                      "reduce the depth of nested expressions");
        parser_depth--;
        return NULL;
    }
    Expr* result = assignment();
    parser_depth--;
    return result;
}

static Stmt* print_statement() {
    Expr* value = expression();
    return new_print_stmt(value);
}

static Stmt* block() {
    if (++parser_depth > MAX_PARSER_DEPTH) {
        char message[128];
        snprintf(message, sizeof(message),
                 "maximum nesting depth exceeded (%d)", MAX_PARSER_DEPTH);
        parser_report(current_token, 1, message,
                      "reduce the depth of nested blocks");
    }
    consume(TOKEN_INDENT, "Expect indentation after block start.");
    
    Stmt* head = NULL;
    Stmt* current = NULL;

    while (!check(TOKEN_DEDENT) && !check(TOKEN_EOF)) {
        if (match(TOKEN_NEWLINE)) {
            continue;
        }

        Stmt* stmt = declaration();
        
        if (head == NULL) {
            head = stmt;
            current = head;
        } else {
            current->next = stmt;
            current = stmt;
        }
    }

    consume(TOKEN_DEDENT, "Expect dedent at end of block.");
    parser_depth--;
    return new_block_stmt(head);
}

static Stmt* if_statement() {
    Expr* condition = expression();
    consume(TOKEN_COLON, "Expect ':' after if condition.");
    consume(TOKEN_NEWLINE, "Expect newline after if condition.");
    Stmt* then_branch = block();

    Stmt* else_branch = NULL;
    if (match(TOKEN_ELSE)) {
        consume(TOKEN_COLON, "Expect ':' after else.");
        consume(TOKEN_NEWLINE, "Expect newline after else.");
        else_branch = block();
    }
    
    return new_if_stmt(condition, then_branch, else_branch);
}

static Stmt* while_statement() {
    Expr* condition = expression();
    consume(TOKEN_COLON, "Expect ':' after while condition.");
    consume(TOKEN_NEWLINE, "Expect newline after while condition.");
    Stmt* body = block();
    return new_while_stmt(condition, body);
}

static Stmt* proc_declaration() {
    if (current_token.type == TOKEN_IDENTIFIER || current_token.type == TOKEN_INIT) {
        Token name = current_token;
        advance_parser();
        
        consume(TOKEN_LPAREN, "Expect '(' after procedure name.");

        Token* params = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RPAREN)) {
            do {
                if (current_token.type == TOKEN_SELF || current_token.type == TOKEN_IDENTIFIER) {
                    if (count >= capacity) {
                        capacity = capacity == 0 ? 4 : capacity * 2;
                        params = SAGE_REALLOC(params, sizeof(Token) * capacity);
                    }
                    params[count++] = current_token;
                    advance_parser();
                } else {
                    parser_report(current_token, token_span(&current_token),
                                  "expected parameter name",
                                  "parameters must be identifiers");
                }
            } while (match(TOKEN_COMMA));
        }
        consume(TOKEN_RPAREN, "Expect ')' after parameters.");
        consume(TOKEN_COLON, "Expect ':' after procedure signature.");
        consume(TOKEN_NEWLINE, "Expect newline before procedure body.");
        Stmt* body = block();

        return new_proc_stmt(name, params, count, body);
    }
    
    parser_report(current_token, token_span(&current_token),
                  "expected procedure name",
                  "write a name after 'proc', for example: proc greet(name):");
    return NULL;
}

static Stmt* async_proc_declaration() {
    consume(TOKEN_PROC, "Expect 'proc' after 'async'.");
    if (current_token.type == TOKEN_IDENTIFIER) {
        Token name = current_token;
        advance_parser();

        consume(TOKEN_LPAREN, "Expect '(' after procedure name.");

        Token* params = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RPAREN)) {
            do {
                if (current_token.type == TOKEN_SELF || current_token.type == TOKEN_IDENTIFIER) {
                    if (count >= capacity) {
                        capacity = capacity == 0 ? 4 : capacity * 2;
                        params = SAGE_REALLOC(params, sizeof(Token) * capacity);
                    }
                    params[count++] = current_token;
                    advance_parser();
                } else {
                    parser_report(current_token, token_span(&current_token),
                                  "expected parameter name",
                                  "parameters must be identifiers");
                }
            } while (match(TOKEN_COMMA));
        }
        consume(TOKEN_RPAREN, "Expect ')' after parameters.");
        consume(TOKEN_COLON, "Expect ':' after procedure signature.");
        consume(TOKEN_NEWLINE, "Expect newline before procedure body.");
        Stmt* body = block();

        return new_async_proc_stmt(name, params, count, body);
    }

    parser_report(current_token, token_span(&current_token),
                  "expected procedure name after 'async proc'",
                  "write a name after 'async proc', for example: async proc fetch():");
    return NULL;
}

static Stmt* class_declaration() {
    consume(TOKEN_IDENTIFIER, "Expect class name.");
    Token name = previous_token;
    
    Token parent;
    int has_parent = 0;
    if (match(TOKEN_LPAREN)) {
        consume(TOKEN_IDENTIFIER, "Expect parent class name.");
        parent = previous_token;
        consume(TOKEN_RPAREN, "Expect ')' after parent class.");
        has_parent = 1;
    }
    
    consume(TOKEN_COLON, "Expect ':' after class header.");
    consume(TOKEN_NEWLINE, "Expect newline after class header.");
    consume(TOKEN_INDENT, "Expect indentation in class body.");
    
    Stmt* method_head = NULL;
    Stmt* method_current = NULL;
    
    while (!check(TOKEN_DEDENT) && !check(TOKEN_EOF)) {
        if (match(TOKEN_NEWLINE)) {
            continue;
        }
        
        if (match(TOKEN_PROC)) {
            Stmt* method = proc_declaration();
            
            if (method_head == NULL) {
                method_head = method;
                method_current = method;
            } else {
                method_current->next = method;
                method_current = method;
            }
        } else {
            parser_report(current_token, token_span(&current_token),
                          "only methods are allowed in a class body",
                          "use 'proc' to define methods inside a class");
        }
    }
    
    consume(TOKEN_DEDENT, "Expect dedent after class body.");
    
    return new_class_stmt(name, parent, has_parent, method_head);
}

static Stmt* statement() {
    if (match(TOKEN_PRINT)) return print_statement();
    if (match(TOKEN_IF)) return if_statement();
    if (match(TOKEN_WHILE)) return while_statement();
    if (match(TOKEN_FOR)) return for_statement();
    if (match(TOKEN_TRY)) return try_statement();
    if (match(TOKEN_RAISE)) return raise_statement();
    if (match(TOKEN_YIELD)) return yield_statement();
    if (match(TOKEN_BREAK)) return new_break_stmt();
    if (match(TOKEN_CONTINUE)) return new_continue_stmt();

    Expr* expr = expression();
    
    // Handle assignment statements (x = value) where expr is a SET expression with NULL object
    if (expr->type == EXPR_SET && expr->as.set.object == NULL) {
        // This is a variable assignment, treat it as a statement
        return new_expr_stmt(expr);
    }
    
    return new_expr_stmt(expr);
}

static Stmt* declaration() {
    while (match(TOKEN_NEWLINE));

    if (check(TOKEN_DEDENT) || check(TOKEN_EOF)) {
        return NULL;
    }

    if (match(TOKEN_CLASS)) return class_declaration();
    if (match(TOKEN_ASYNC)) return async_proc_declaration();
    if (match(TOKEN_PROC)) return proc_declaration();
    
    // PHASE 8: Import statements
    if (match(TOKEN_IMPORT) || check(TOKEN_FROM)) {
        Stmt* stmt = import_statement();
        match(TOKEN_NEWLINE);
        return stmt;
    }

    if (match(TOKEN_RETURN)) {
        Expr* value = NULL;
        if (!check(TOKEN_NEWLINE)) {
            value = expression();
        }
        match(TOKEN_NEWLINE);
        return new_return_stmt(value);
    }

    if (match(TOKEN_LET) || match(TOKEN_VAR)) {
        consume(TOKEN_IDENTIFIER, "Expect variable name.");
        Token name = previous_token;

        Expr* initializer = NULL;
        if (match(TOKEN_ASSIGN)) {
            initializer = expression();
        }

        Stmt* stmt = new_let_stmt(name, initializer);
        match(TOKEN_NEWLINE);
        return stmt;
    }

    Stmt* stmt = statement();
    match(TOKEN_NEWLINE);
    return stmt;
}

Stmt* parse(void) {
    while (current_token.type == TOKEN_NEWLINE) {
        advance_parser();
    }

    if (current_token.type == TOKEN_EOF) return NULL;
    return declaration();
}
