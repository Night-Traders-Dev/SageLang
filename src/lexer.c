#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "lexer.h"
#include "token.h"

// Lexer state
static const char* start;
static const char* current;
static int line;
static int at_beginning_of_line;

// Indentation Stack
#define MAX_INDENT_LEVELS 100
static int indent_stack[MAX_INDENT_LEVELS];
static int indent_stack_top = 0;
static int pending_dedents = 0;

void init_lexer(const char* source) {
    start = source;
    current = source;
    line = 1;
    at_beginning_of_line = 1;

    indent_stack_top = 0;
    indent_stack[0] = 0;
    pending_dedents = 0;
}

static int is_at_end() {
    return *current == '\0';
}

static char advance() {
    current++;
    return current[-1];
}

static char peek() {
    return *current;
}

static char peek_next() {
    if (is_at_end()) return '\0';
    return current[1];
}

static Token make_token(TokenType type) {
    Token token;
    token.type = type;
    token.start = start;
    token.length = (int)(current - start);
    token.line = line;
    return token;
}

static Token error_token(const char* message) {
    Token token;
    token.type = TOKEN_ERROR;
    token.start = message;
    token.length = (int)strlen(message);
    token.line = line;
    return token;
}

static TokenType check_keyword(int start_index, int length, const char* rest, TokenType type) {
    if (current - start == start_index + length &&
        memcmp(start + start_index, rest, length) == 0) {
        return type;
    }
    return TOKEN_IDENTIFIER;
}

static TokenType identifier_type() {
    switch (start[0]) {
        case 'e':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'l':
                        if (current - start > 2 && start[2] == 's') return check_keyword(3, 1, "e", TOKEN_ELSE);
                        if (current - start > 2 && start[2] == 'i') return check_keyword(3, 1, "f", TOKEN_IF);
                        break;
                }
            }
            break;
        case 'f': return check_keyword(1, 2, "or", TOKEN_FOR);
        case 'i': return check_keyword(1, 1, "f", TOKEN_IF);
        case 'l': return check_keyword(1, 2, "et", TOKEN_LET);
        case 'p':
            if (current - start > 1) {
                switch(start[1]) {
                    case 'r':
                        if (current - start > 2 && start[2] == 'i') return check_keyword(3, 2, "nt", TOKEN_PRINT); 
                        if (current - start > 2 && start[2] == 'o') return check_keyword(3, 1, "c", TOKEN_PROC);
                        break;
                }
            }
            break;
        case 'r': return check_keyword(1, 5, "eturn", TOKEN_RETURN);
        case 'v': return check_keyword(1, 2, "ar", TOKEN_VAR);
        case 'w': return check_keyword(1, 4, "hile", TOKEN_WHILE);
    }
    return TOKEN_IDENTIFIER;
}

static Token identifier() {
    while (isalnum(peek()) || peek() == '_') advance();
    return make_token(identifier_type());
}

static Token number() {
    while (isdigit(peek())) advance();
    if (peek() == '.' && isdigit(peek_next())) {
        advance();
        while (isdigit(peek())) advance();
    }
    return make_token(TOKEN_NUMBER);
}

Token scan_token() {
    if (pending_dedents > 0) {
        pending_dedents--;
        return make_token(TOKEN_DEDENT);
    }

    if (at_beginning_of_line) {
        at_beginning_of_line = 0;
        int spaces = 0;
        while (peek() == ' ') {
            advance();
            spaces++;
        }

        // Check for newline (empty line)
        if (peek() == '\n') {
            line++;
            advance();
            at_beginning_of_line = 1;
            start = current;
            return scan_token();
        }

        int current_indent = indent_stack[indent_stack_top];
        if (spaces > current_indent) {
            if (indent_stack_top >= MAX_INDENT_LEVELS - 1) return error_token("Too much nesting.");
            indent_stack[++indent_stack_top] = spaces;
            return make_token(TOKEN_INDENT);
        }
        else if (spaces < current_indent) {
            while (indent_stack_top > 0 && indent_stack[indent_stack_top] > spaces) {
                indent_stack_top--;
                pending_dedents++;
            }
            if (indent_stack[indent_stack_top] != spaces) {
                return error_token("Indentation error.");
            }
            pending_dedents--;
            return make_token(TOKEN_DEDENT);
        }
    }

    // Skip whitespace: space, carriage return, tab
    while (peek() == ' ' || peek() == '\r' || peek() == '\t') {
        advance();
    }

    start = current;

    if (is_at_end()) {
        if (indent_stack_top > 0) {
            indent_stack_top--;
            return make_token(TOKEN_DEDENT);
        }
        return make_token(TOKEN_EOF);
    }

    char c = advance();

    if (c == '\n') {
        line++;
        at_beginning_of_line = 1;
        return make_token(TOKEN_NEWLINE);
    }

    if (c == '#') {
        while (peek() != '\n' && !is_at_end()) advance();
        return scan_token();
    }

    if (isalpha(c) || c == '_') return identifier();
    if (isdigit(c)) return number();

    switch (c) {
        case '(': return make_token(TOKEN_LPAREN);
        case ')': return make_token(TOKEN_RPAREN);
        case '+': return make_token(TOKEN_PLUS);
        case '-': return make_token(TOKEN_MINUS);
        case '*': return make_token(TOKEN_STAR);
        case '/': return make_token(TOKEN_SLASH);
        case '<': return make_token(TOKEN_LT);
        case '>': return make_token(TOKEN_GT);
        case '=': return make_token(TOKEN_ASSIGN);
        case ',': return make_token(TOKEN_COMMA);
        case ':': return make_token(TOKEN_COLON);
    }

    return error_token("Unexpected character.");
}
