#include <stdlib.h>
#include <stdio.h>
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
    fprintf(stderr, "[Line %d] Error: %s (Got type %d)\n",
            current_token.line, message, current_token.type);
    exit(1);
}

static int check(TokenType type) {
    return current_token.type == type;
}


// Forward declarations
static Expr* expression();
static Stmt* declaration();
static Stmt* block();
static Stmt* statement();

// primary -> NUMBER | IDENTIFIER
static Expr* primary() {
    if (match(TOKEN_NUMBER)) {
        double val = strtod(previous_token.start, NULL);
        return new_number_expr(val);
    }
    if (match(TOKEN_IDENTIFIER)) {
        return new_variable_expr(previous_token);
    }

    fprintf(stderr, "[Line %d] Expect expression.\n", current_token.line);
    exit(1);
}

// term -> primary (('*' | '/') primary)*
static Expr* term() {
    Expr* expr = primary();
    while (match(TOKEN_STAR) || match(TOKEN_SLASH)) {
        Token op = previous_token;
        Expr* right = primary();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

// addition -> term (('+' | '-') term)*
static Expr* addition() {
    Expr* expr = term();
    while (match(TOKEN_PLUS) || match(TOKEN_MINUS)) {
        Token op = previous_token;
        Expr* right = term();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

// comparison -> addition (('>' | '<') addition)*
static Expr* comparison() {
    Expr* expr = addition();
    while (match(TOKEN_GT) || match(TOKEN_LT)) {
        Token op = previous_token;
        Expr* right = addition();
        expr = new_binary_expr(expr, op, right);
    }
    return expr;
}

// expression -> comparison
static Expr* expression() {
    return comparison();
}

static Stmt* print_statement() {
    Expr* value = expression();
    return new_print_stmt(value);
}

static Stmt* if_statement() {
    Expr* condition = expression();

    consume(TOKEN_NEWLINE, "Expect newline after if condition.");

    // The 'then' branch MUST be an indented block
    Stmt* then_branch = block();

    Stmt* else_branch = NULL;
    if (match(TOKEN_ELSE)) {
        consume(TOKEN_NEWLINE, "Expect newline after else.");
        else_branch = block();
    }

    return new_if_stmt(condition, then_branch, else_branch);
}

static Stmt* while_statement() {
    // 'while' token already consumed
    Expr* condition = expression();

    consume(TOKEN_NEWLINE, "Expect newline after while condition.");
    Stmt* body = block();

    return new_while_stmt(condition, body);
}


static Stmt* block() {
    consume(TOKEN_INDENT, "Expect indentation after block start.");

    Stmt* head = NULL;
    Stmt* current = NULL;

    // Keep parsing declarations until we hit DEDENT or EOF
    while (!check(TOKEN_DEDENT) && !check(TOKEN_EOF)) {
        Stmt* stmt = declaration();

        // Build linked list
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


static Stmt* statement() {
    if (match(TOKEN_PRINT)) {
        return print_statement();
    }
    if (match(TOKEN_IF)) {
        return if_statement();
    }
    if (match(TOKEN_WHILE)) {
        return while_statement();
    }

    // Expression statement
    Expr* expr = expression();
    return new_expr_stmt(expr);
}

static Stmt* declaration() {
    Stmt* stmt;

    if (match(TOKEN_LET)) {
        consume(TOKEN_IDENTIFIER, "Expect variable name.");
        Token name = previous_token;

        Expr* initializer = NULL;
        if (match(TOKEN_ASSIGN)) {
            initializer = expression();
        }

        stmt = new_let_stmt(name, initializer);
    } else {
        stmt = statement();
    }

    // Optionally consume a trailing newline
    match(TOKEN_NEWLINE);

    return stmt;
}

// Parse entry: returns one statement at a time
Stmt* parse() {
    if (current_token.type == TOKEN_EOF) return NULL;
    return declaration();
}
