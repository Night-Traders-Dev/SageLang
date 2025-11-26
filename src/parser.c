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
    fprintf(stderr, "[Line %d] Error: %s (Got type %d)", current_token.line, message, current_token.type);
    exit(1);
}

// Forward declarations
static Expr* expression();
static Expr* postfix();
static Stmt* declaration();
static Stmt* statement();
static Stmt* block();

static Stmt* for_statement() {
    consume(TOKEN_IDENTIFIER, "Expect loop variable.");
    Token var = previous_token;

    consume(TOKEN_IN, "Expect 'in' after loop variable.");

    Expr* iterable = expression();
    consume(TOKEN_NEWLINE, "Expect newline after for clause.");

    Stmt* body = block();

    return new_for_stmt(var, iterable, body);
}



// primary -> NUMBER | STRING | BOOLEAN | NIL | ( expression ) | [ elements ] | IDENTIFIER | CALL
static Expr* primary() {
    // 1. Literals
    if (match(TOKEN_FALSE)) return new_bool_expr(0);
    if (match(TOKEN_TRUE))  return new_bool_expr(1);
    if (match(TOKEN_NIL))   return new_nil_expr();

    // 2. Grouping Expressions: ( expr )
    if (match(TOKEN_LPAREN)) {
        Expr* expr = expression();
        consume(TOKEN_RPAREN, "Expect ')' after expression.");
        return expr;
    }

    // 3. Array Literals: [ expr, expr, ... ]
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

    // 4. Numbers
    if (match(TOKEN_NUMBER)) {
        double val = strtod(previous_token.start, NULL);
        return new_number_expr(val);
    }

    // 5. Strings
    if (match(TOKEN_STRING)) {
        Token t = previous_token;
        int len = t.length - 2;
        char* str = malloc(len + 1);
        memcpy(str, t.start + 1, len);
        str[len] = '\0';
        return new_string_expr(str);
    }

    // 6. Identifiers (Variables) & Function Calls
    if (match(TOKEN_IDENTIFIER)) {
        Token name = previous_token;

        // Check for function call: Identifier + '('
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

        // Just a variable access
        return new_variable_expr(name);
    }

    fprintf(stderr, "[Line %d] Expect expression.\n", current_token.line);
    exit(1);
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

static Expr* postfix() {
    Expr* expr = primary();

    while (match(TOKEN_LBRACKET)) {
        Expr* index = expression();
        consume(TOKEN_RBRACKET, "Expect ']' after index.");
        expr = new_index_expr(expr, index);
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
        // Skip blank lines inside blocks
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
    consume(TOKEN_NEWLINE, "Expect newline after if condition.");
    Stmt* then_branch = block();

    Stmt* else_branch = NULL;
    if (match(TOKEN_ELSE)) {
        consume(TOKEN_NEWLINE, "Expect newline after else.");
        else_branch = block();
    }
    
    return new_if_stmt(condition, then_branch, else_branch);
}

static Stmt* while_statement() {
    Expr* condition = expression();
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

    Expr* expr = expression();
    return new_expr_stmt(expr);
}

static Stmt* declaration() {
    // Skip leading newlines/comments
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
