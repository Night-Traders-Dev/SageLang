#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "lexer.h"
#include "ast.h"
#include "token.h"

static Token current_token;
static Token previous_token;

static void advance_parser() {
    previous_token = current_token;
    current_token = scan_token();
}

void parser_init() {
    advance_parser();
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
    fprintf(stderr, "[Line %d] Error: %s (Got type %d)\n", current_token.line, message, current_token.type);
    exit(1);
}

// Forward declarations
static Expr* expression();
static Expr* postfix();
static Stmt* declaration();
static Stmt* statement();
static Stmt* block();

static Stmt* for_statement() {
    if (!check(TOKEN_IDENTIFIER)) {
        fprintf(stderr, "[Line %d] Error: Expect loop variable after 'for'.\n", current_token.line);
        exit(1);
    }
    
    Token var = current_token;
    advance_parser();

    consume(TOKEN_IN, "Expect 'in' after loop variable.");

    Expr* iterable = expression();
    match(TOKEN_COLON);
    consume(TOKEN_NEWLINE, "Expect newline after for clause.");

    Stmt* body = block();

    return new_for_stmt(var, iterable, body);
}

// primary -> NUMBER | STRING | BOOLEAN | NIL | ( expr/tuple ) | [ array ] | { dict } | IDENTIFIER | CALL
static Expr* primary() {
    // Literals
    if (match(TOKEN_FALSE)) return new_bool_expr(0);
    if (match(TOKEN_TRUE))  return new_bool_expr(1);
    if (match(TOKEN_NIL))   return new_nil_expr();

    // Parentheses: ( expr ) or tuple (a, b, c)
    if (match(TOKEN_LPAREN)) {
        // Empty tuple ()
        if (match(TOKEN_RPAREN)) {
            return new_tuple_expr(NULL, 0);
        }

        Expr* first = expression();
        
        // Check if it's a tuple: (expr, ...)
        if (match(TOKEN_COMMA)) {
            Expr** elements = NULL;
            int count = 0;
            int capacity = 4;
            elements = malloc(sizeof(Expr*) * capacity);
            elements[count++] = first;
            
            // Could be trailing comma (val,) or more elements
            if (!check(TOKEN_RPAREN)) {
                do {
                    if (count >= capacity) {
                        capacity *= 2;
                        elements = realloc(elements, sizeof(Expr*) * capacity);
                    }
                    elements[count++] = expression();
                } while (match(TOKEN_COMMA) && !check(TOKEN_RPAREN));
            }
            
            consume(TOKEN_RPAREN, "Expect ')' after tuple elements.");
            return new_tuple_expr(elements, count);
        }
        
        // Just a grouping expression
        consume(TOKEN_RPAREN, "Expect ')' after expression.");
        return first;
    }

    // Dictionary Literals: {"key": val, ...}
    if (match(TOKEN_LBRACE)) {
        char** keys = NULL;
        Expr** values = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RBRACE)) {
            do {
                // Expect string key
                consume(TOKEN_STRING, "Expect string key in dictionary.");
                Token key_token = previous_token;
                
                // Extract key string (without quotes)
                int len = key_token.length - 2;
                char* key = malloc(len + 1);
                memcpy(key, key_token.start + 1, len);
                key[len] = '\0';
                
                consume(TOKEN_COLON, "Expect ':' after dictionary key.");
                Expr* value = expression();
                
                if (count >= capacity) {
                    capacity = capacity == 0 ? 4 : capacity * 2;
                    keys = realloc(keys, sizeof(char*) * capacity);
                    values = realloc(values, sizeof(Expr*) * capacity);
                }
                keys[count] = key;
                values[count] = value;
                count++;
            } while (match(TOKEN_COMMA) && !check(TOKEN_RBRACE));
        }
        
        consume(TOKEN_RBRACE, "Expect '}' after dictionary elements.");
        return new_dict_expr(keys, values, count);
    }

    // Array Literals: [expr, expr, ...]
    if (match(TOKEN_LBRACKET)) {
        Expr** elements = NULL;
        int count = 0;
        int capacity = 0;

        if (!check(TOKEN_RBRACKET)) {
            do {
                Expr* elem = expression();
                if (count >= capacity) {
                    capacity = capacity == 0 ? 4 : capacity * 2;
                    elements = realloc(elements, sizeof(Expr*) * capacity);
                }
                elements[count++] = elem;
            } while (match(TOKEN_COMMA));
        }
        consume(TOKEN_RBRACKET, "Expect ']' after array elements.");
        return new_array_expr(elements, count);
    }

    // Numbers
    if (match(TOKEN_NUMBER)) {
        double val = strtod(previous_token.start, NULL);
        return new_number_expr(val);
    }

    // Strings
    if (match(TOKEN_STRING)) {
        Token t = previous_token;
        int len = t.length - 2;
        char* str = malloc(len + 1);
        memcpy(str, t.start + 1, len);
        str[len] = '\0';
        return new_string_expr(str);
    }

    // Identifiers (Variables) & Function Calls
    if (match(TOKEN_IDENTIFIER)) {
        Token name = previous_token;

        // Function call: Identifier(args)
        if (match(TOKEN_LPAREN)) {
            Expr** args = NULL;
            int count = 0;
            int capacity = 0;

            if (!check(TOKEN_RPAREN)) {
                do {
                    Expr* arg = expression();
                    if (count >= capacity) {
                        capacity = capacity == 0 ? 4 : capacity * 2;
                        args = realloc(args, sizeof(Expr*) * capacity);
                    }
                    args[count++] = arg;
                } while (match(TOKEN_COMMA));
            }
            consume(TOKEN_RPAREN, "Expect ')' after arguments.");
            return new_call_expr(name, args, count);
        }

        return new_variable_expr(name);
    }

    fprintf(stderr, "[Line %d] Expect expression.\n", current_token.line);
    exit(1);
}

static Expr* postfix() {
    Expr* expr = primary();

    while (1) {
        if (match(TOKEN_LBRACKET)) {
            // Check for slice: arr[start:end]
            Expr* start_or_index = NULL;
            Expr* end = NULL;
            
            // Handle arr[:end]
            if (!check(TOKEN_COLON)) {
                start_or_index = expression();
            }
            
            // Check for colon (slice syntax)
            if (match(TOKEN_COLON)) {
                // It's a slice
                Expr* start = start_or_index;  // Could be NULL for [:end]
                
                // Handle arr[start:]
                if (!check(TOKEN_RBRACKET)) {
                    end = expression();
                }
                
                consume(TOKEN_RBRACKET, "Expect ']' after slice.");
                expr = new_slice_expr(expr, start, end);
            } else {
                // Regular index access
                consume(TOKEN_RBRACKET, "Expect ']' after index.");
                expr = new_index_expr(expr, start_or_index);
            }
        } else {
            break;
        }
    }

    return expr;
}

static Expr* term() {
    Expr* expr = postfix();
    while (match(TOKEN_STAR) || match(TOKEN_SLASH)) {
        Token op = previous_token;
        Expr* right = postfix();
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

static Expr* comparison() {
    Expr* expr = addition();
    while (match(TOKEN_GT) || match(TOKEN_LT)) {
        Token op = previous_token;
        Expr* right = addition();
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

static Expr* logical_and() {
    Expr* expr = equality();
    while (match(TOKEN_AND)) {
        Token op = previous_token;
        Expr* right = equality();
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

static Expr* expression() {
    return logical_or();
}

static Stmt* print_statement() {
    Expr* value = expression();
    return new_print_stmt(value);
}

static Stmt* block() {
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
    return new_block_stmt(head);
}

static Stmt* if_statement() {
    Expr* condition = expression();
    match(TOKEN_COLON);
    consume(TOKEN_NEWLINE, "Expect newline after if condition.");
    Stmt* then_branch = block();

    Stmt* else_branch = NULL;
    if (match(TOKEN_ELSE)) {
        match(TOKEN_COLON);
        consume(TOKEN_NEWLINE, "Expect newline after else.");
        else_branch = block();
    }
    
    return new_if_stmt(condition, then_branch, else_branch);
}

static Stmt* while_statement() {
    Expr* condition = expression();
    match(TOKEN_COLON);
    consume(TOKEN_NEWLINE, "Expect newline after while condition.");
    Stmt* body = block();
    return new_while_stmt(condition, body);
}

static Stmt* proc_declaration() {
    consume(TOKEN_IDENTIFIER, "Expect procedure name.");
    Token name = previous_token;

    consume(TOKEN_LPAREN, "Expect '(' after procedure name.");

    Token* params = NULL;
    int count = 0;
    int capacity = 0;

    if (!check(TOKEN_RPAREN)) {
        do {
            consume(TOKEN_IDENTIFIER, "Expect parameter name.");
            if (count >= capacity) {
                capacity = capacity == 0 ? 4 : capacity * 2;
                params = realloc(params, sizeof(Token) * capacity);
            }
            params[count++] = previous_token;
        } while (match(TOKEN_COMMA));
    }
    consume(TOKEN_RPAREN, "Expect ')' after parameters.");
    match(TOKEN_COLON);
    consume(TOKEN_NEWLINE, "Expect newline before procedure body.");
    Stmt* body = block();

    return new_proc_stmt(name, params, count, body);
}

static Stmt* statement() {
    if (match(TOKEN_PRINT)) return print_statement();
    if (match(TOKEN_IF)) return if_statement();
    if (match(TOKEN_WHILE)) return while_statement();
    if (match(TOKEN_FOR)) return for_statement();
    if (match(TOKEN_BREAK)) return new_break_stmt();
    if (match(TOKEN_CONTINUE)) return new_continue_stmt();

    Expr* expr = expression();
    return new_expr_stmt(expr);
}

static Stmt* declaration() {
    while (match(TOKEN_NEWLINE));

    if (check(TOKEN_DEDENT) || check(TOKEN_EOF)) {
        return NULL;
    }

    if (match(TOKEN_PROC)) return proc_declaration();

    if (match(TOKEN_RETURN)) {
        Expr* value = NULL;
        if (!check(TOKEN_NEWLINE)) {
            value = expression();
        }
        match(TOKEN_NEWLINE);
        return new_return_stmt(value);
    }

    if (match(TOKEN_LET)) {
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

Stmt* parse() {
    while (current_token.type == TOKEN_NEWLINE) {
        advance_parser();
    }

    if (current_token.type == TOKEN_EOF) return NULL;
    return declaration();
}