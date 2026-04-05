#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "lexer.h"
#include "token.h"

// Lexer state
static const char* start;
static const char* current;
static int line;
static int token_line;
static int at_beginning_of_line;
static const char* line_start;
static const char* token_line_start;
static const char* current_filename;

static int indent_stack[MAX_INDENT_LEVELS];
static int indent_stack_top = 0;
static int pending_dedents = 0;
static int bracket_depth = 0;

void init_lexer(const char* source, const char* filename) {
    start = source;
    current = source;
    line = 1;
    token_line = 1;
    at_beginning_of_line = 1;
    line_start = source;
    token_line_start = source;
    current_filename = filename;

    indent_stack_top = 0;
    indent_stack[0] = 0;
    pending_dedents = 0;
    bracket_depth = 0;
}

LexerState lexer_get_state(void) {
    LexerState state;
    state.start = start;
    state.current = current;
    state.line = line;
    state.token_line = token_line;
    state.at_beginning_of_line = at_beginning_of_line;
    state.line_start = line_start;
    state.token_line_start = token_line_start;
    state.filename = current_filename;
    memcpy(state.indent_stack, indent_stack, sizeof(indent_stack));
    state.indent_stack_top = indent_stack_top;
    state.pending_dedents = pending_dedents;
    state.bracket_depth = bracket_depth;
    return state;
}

void lexer_set_state(LexerState state) {
    start = state.start;
    current = state.current;
    line = state.line;
    token_line = state.token_line;
    at_beginning_of_line = state.at_beginning_of_line;
    line_start = state.line_start;
    token_line_start = state.token_line_start;
    current_filename = state.filename;
    memcpy(indent_stack, state.indent_stack, sizeof(indent_stack));
    indent_stack_top = state.indent_stack_top;
    pending_dedents = state.pending_dedents;
    bracket_depth = state.bracket_depth;
}

static int is_at_end(void) {
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
    token.line = token_line;
    token.column = (int)(start - token_line_start);
    token.line_start = token_line_start;
    token.filename = current_filename;
    return token;
}

static Token error_token(const char* message) {
    Token token;
    token.type = TOKEN_ERROR;
    token.start = message;
    token.length = (int)strlen(message);
    token.line = token_line;
    token.column = (int)(start - token_line_start);
    token.line_start = token_line_start;
    token.filename = current_filename;
    return token;
}

// --- Keywords ---
static TokenType check_keyword(int start_index, int length, const char* rest, TokenType type) {
    if (current - start == start_index + length && 
        memcmp(start + start_index, rest, length) == 0) {
        return type;
    }
    return TOKEN_IDENTIFIER;
}

static TokenType identifier_type(void) {
    switch (start[0]) {
        case 'a':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'n': return check_keyword(2, 1, "d", TOKEN_AND);
                    case 's':
                        if (current - start > 2 && start[2] == 'y') return check_keyword(3, 2, "nc", TOKEN_ASYNC);
                        return check_keyword(2, 0, "", TOKEN_AS);
                    case 'w': return check_keyword(2, 3, "ait", TOKEN_AWAIT);
                }
            }
            break;

        case 'b': return check_keyword(1, 4, "reak", TOKEN_BREAK);

        case 'c':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'a':
                        if (current - start > 2 && start[2] == 's') return check_keyword(3, 1, "e", TOKEN_CASE);
                        if (current - start > 2 && start[2] == 't') return check_keyword(3, 2, "ch", TOKEN_CATCH);
                        break;
                    case 'l': return check_keyword(2, 3, "ass", TOKEN_CLASS);
                    case 'o':
                        if (current - start > 2 && start[2] == 'n') return check_keyword(2, 6, "ntinue", TOKEN_CONTINUE);
                        if (current - start > 2 && start[2] == 'm') return check_keyword(2, 6, "mptime", TOKEN_COMPTIME);
                        break;
                }
            }
            break;

        case 'd':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'e':
                        if (current - start > 2 && start[2] == 'f') {
                            if (current - start > 3 && start[3] == 'a') return check_keyword(4, 3, "ult", TOKEN_DEFAULT);
                            if (current - start > 3 && start[3] == 'e') return check_keyword(4, 1, "r", TOKEN_DEFER);
                        }
                        break;
                }
            }
            break;

        case 'e':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'l':
                        if (current - start > 2 && start[2] == 's') return check_keyword(3, 1, "e", TOKEN_ELSE);
                        if (current - start > 2 && start[2] == 'i') return check_keyword(3, 1, "f", TOKEN_IF); // elif
                        break;
                    case 'n':
                        if (current - start > 2 && start[2] == 'd') return check_keyword(3, 0, "", TOKEN_END);
                        if (current - start > 2 && start[2] == 'u') return check_keyword(3, 1, "m", TOKEN_ENUM);
                        break;
                }
            }
            break;

        case 'f': 
            if (current - start > 1) {
                switch (start[1]) {
                    case 'a': return check_keyword(2, 3, "lse", TOKEN_FALSE);
                    case 'i': return check_keyword(2, 5, "nally", TOKEN_FINALLY);
                    case 'o': return check_keyword(2, 1, "r", TOKEN_FOR);
                    case 'r': return check_keyword(2, 2, "om", TOKEN_FROM);  // "from"
                }
            }
            break;

        case 'i':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'f': return check_keyword(2, 0, "", TOKEN_IF);    // "if"
                    case 'm': return check_keyword(2, 4, "port", TOKEN_IMPORT);  // "import"
                    case 'n':
                        if (current - start == 2) return check_keyword(2, 0, "", TOKEN_IN);  // "in"
                        if (current - start == 4) return check_keyword(2, 2, "it", TOKEN_INIT); // "init"
                        break;
                }
            }
            break;
            
        case 'l': return check_keyword(1, 2, "et", TOKEN_LET);
        
        case 'm':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'a':
                        if (current - start > 2 && start[2] == 't') return check_keyword(2, 3, "tch", TOKEN_MATCH);
                        if (current - start > 2 && start[2] == 'c') return check_keyword(2, 3, "cro", TOKEN_MACRO);
                        break;
                }
            }
            break;
        
        case 'n':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'i': return check_keyword(2, 1, "l", TOKEN_NIL);
                    case 'o': return check_keyword(2, 1, "t", TOKEN_NOT);
                }
            }
            break;

        case 'o': return check_keyword(1, 1, "r", TOKEN_OR);

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

        case 'q': return check_keyword(1, 4, "uote", TOKEN_QUOTE);

        case 'r':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'a': return check_keyword(2, 3, "ise", TOKEN_RAISE);
                    case 'e': return check_keyword(2, 4, "turn", TOKEN_RETURN);
                }
            }
            break;
        
        case 's':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'e': return check_keyword(2, 2, "lf", TOKEN_SELF);
                    case 'u': return check_keyword(2, 3, "per", TOKEN_SUPER);
                    case 't': return check_keyword(2, 4, "ruct", TOKEN_STRUCT);
                }
            }
            return TOKEN_IDENTIFIER;
        
        case 't':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'r':
                        if (current - start > 2 && start[2] == 'u') return check_keyword(3, 1, "e", TOKEN_TRUE);
                        if (current - start > 2 && start[2] == 'y') return check_keyword(3, 0, "", TOKEN_TRY);
                        if (current - start > 2 && start[2] == 'a') return check_keyword(3, 2, "it", TOKEN_TRAIT);
                        break;
                }
            }
            break;
            
        case 'u':
            if (current - start > 1) {
                switch (start[1]) {
                    case 'n':
                        if (current - start > 2 && start[2] == 's') return check_keyword(2, 4, "safe", TOKEN_UNSAFE);
                        if (current - start > 2 && start[2] == 'q') return check_keyword(2, 5, "quote", TOKEN_UNQUOTE);
                        break;
                }
            }
            break;

        case 'v': return check_keyword(1, 2, "ar", TOKEN_VAR);
        
        case 'w': return check_keyword(1, 4, "hile", TOKEN_WHILE);
        
        case 'y': return check_keyword(1, 4, "ield", TOKEN_YIELD);
    }
    return TOKEN_IDENTIFIER;
}

#define MAX_IDENTIFIER_LENGTH 1024

static Token identifier() {
    while (isalnum(peek()) || peek() == '_') {
        if (current - start > MAX_IDENTIFIER_LENGTH) {
            return error_token("Identifier exceeds maximum length (1024).");
        }
        advance();
    }
    return make_token(identifier_type());
}

static int is_binary_digit(char c) {
    return c == '0' || c == '1';
}

static int is_hex_digit(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static int is_octal_digit(char c) {
    return c >= '0' && c <= '7';
}

static Token number() {
    if (start[0] == '0' && (peek() == 'b' || peek() == 'B')) {
        advance();
        if (!is_binary_digit(peek())) {
            return error_token("Invalid binary literal: expected at least one binary digit after '0b'.");
        }
        while (is_binary_digit(peek())) advance();
        if (isalnum((unsigned char)peek()) || peek() == '_') {
            return error_token("Invalid binary literal: use only 0 or 1 after '0b'.");
        }
        return make_token(TOKEN_NUMBER);
    }

    if (start[0] == '0' && (peek() == 'x' || peek() == 'X')) {
        advance();
        if (!is_hex_digit(peek())) {
            return error_token("Invalid hex literal: expected at least one hex digit after '0x'.");
        }
        while (is_hex_digit(peek())) advance();
        if (isalnum((unsigned char)peek()) || peek() == '_') {
            return error_token("Invalid hex literal: use only 0-9, a-f after '0x'.");
        }
        return make_token(TOKEN_NUMBER);
    }

    if (start[0] == '0' && (peek() == 'o' || peek() == 'O')) {
        advance();
        if (!is_octal_digit(peek())) {
            return error_token("Invalid octal literal: expected at least one octal digit after '0o'.");
        }
        while (is_octal_digit(peek())) advance();
        if (isalnum((unsigned char)peek()) || peek() == '_') {
            return error_token("Invalid octal literal: use only 0-7 after '0o'.");
        }
        return make_token(TOKEN_NUMBER);
    }

    while (isdigit(peek())) advance();
    if (peek() == '.' && isdigit(peek_next())) {
        advance();
        while (isdigit(peek())) advance();
    }
    if ((peek() == 'e' || peek() == 'E')) {
        advance();
        if (peek() == '+' || peek() == '-') advance();
        if (!isdigit(peek())) {
            return error_token("Invalid float literal: expected digit after exponent.");
        }
        while (isdigit(peek())) advance();
    }
    return make_token(TOKEN_NUMBER);
}

#define MAX_STRING_LENGTH 4096

static Token string() {
    const char* string_start = current;
    while (peek() != '"' && !is_at_end()) {
        if (peek() == '\n') {
            line++;
        }
        if (peek() == '\\' && !is_at_end()) {
            advance();
            if (!is_at_end()) advance();
            if (current[-1] == '\n') {
                line++;
                line_start = current;
            }
        } else {
            advance();
        }
        if (current[-1] == '\n') {
            line_start = current;
        }
        if (current - string_start > MAX_STRING_LENGTH) {
            return error_token("String literal exceeds maximum length (4096).");
        }
    }

    if (is_at_end()) return error_token("Unterminated string.");

    // The closing ".
    advance();
    return make_token(TOKEN_STRING);
}

static int match_char(char expected) {
    if (is_at_end()) return 0;
    if (*current != expected) return 0;
    current++;
    return 1;
}

Token scan_token(void) {
    // Outer loop replaces recursive calls for blank lines and comments
    for (;;) {
    if (pending_dedents > 0 && bracket_depth == 0) {
        start = current;
        token_line = line;
        token_line_start = line_start;
        pending_dedents--;
        return make_token(TOKEN_DEDENT);
    }

    if (at_beginning_of_line) {
        at_beginning_of_line = 0;
        start = current;
        token_line = line;
        token_line_start = line_start;
        int spaces = 0;
        while (peek() == ' ') {
            advance();
            spaces++;
        }

        if (peek() == '\n') {
            start = current;
            token_line = line;
            token_line_start = line_start;
            advance();
            line++;
            line_start = current;
            at_beginning_of_line = 1;
            continue;  // Was: return scan_token();
        }

        // Inside brackets/parens/braces: skip indentation handling
        if (bracket_depth > 0) {
            // Don't emit INDENT/DEDENT inside brackets
        } else {
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
    }

    while (peek() == ' ' || peek() == '\r' || peek() == '\t') {
        advance();
    }

    start = current;
    token_line = line;
    token_line_start = line_start;

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
        line_start = current;
        at_beginning_of_line = 1;
        if (bracket_depth > 0) {
            continue; // Skip newlines inside brackets
        }
        return make_token(TOKEN_NEWLINE);
    }

    if (c == '#') {
        if (peek() == '#') {
            // Doc comment: ## text
            advance(); // skip second #
            while (peek() == ' ') advance(); // skip leading space
            const char* doc_start = current;
            while (peek() != '\n' && !is_at_end()) advance();
            // Store doc comment as a special token
            Token doc_token;
            doc_token.type = TOKEN_DOC_COMMENT;
            doc_token.start = doc_start;
            doc_token.length = (int)(current - doc_start);
            doc_token.line = line;
            doc_token.column = (int)(doc_start - line_start);
            doc_token.line_start = line_start;
            doc_token.filename = current_filename;
            return doc_token;
        }
        while (peek() != '\n' && !is_at_end()) advance();
        continue;
    }

    if (c == '"') return string();

    if (isalpha(c) || c == '_') return identifier();
    if (isdigit(c)) return number();

    switch (c) {
        case '(': bracket_depth++; return make_token(TOKEN_LPAREN);
        case ')': if (bracket_depth > 0) bracket_depth--; return make_token(TOKEN_RPAREN);
        case '[': bracket_depth++; return make_token(TOKEN_LBRACKET);
        case ']': if (bracket_depth > 0) bracket_depth--; return make_token(TOKEN_RBRACKET);
        case '{': bracket_depth++; return make_token(TOKEN_LBRACE);
        case '}': if (bracket_depth > 0) bracket_depth--; return make_token(TOKEN_RBRACE);
        case '+': return make_token(TOKEN_PLUS);
        case '-': return make_token(match_char('>') ? TOKEN_ARROW : TOKEN_MINUS);
        case '*': return make_token(TOKEN_STAR);
        case '/': return make_token(TOKEN_SLASH);
        case '%': return make_token(TOKEN_PERCENT);
        case ',': return make_token(TOKEN_COMMA);
        case ':': return make_token(TOKEN_COLON);
        case '.': return make_token(TOKEN_DOT);
        case '!': return match_char('=') ? make_token(TOKEN_NEQ) : error_token("Unexpected '!' (use 'not' for logical negation).");
        case '=': return make_token(match_char('=') ? TOKEN_EQ : TOKEN_ASSIGN);
        case '<': return make_token(match_char('<') ? TOKEN_LSHIFT : (match_char('=') ? TOKEN_LTE : TOKEN_LT));
        case '>': return make_token(match_char('>') ? TOKEN_RSHIFT : (match_char('=') ? TOKEN_GTE : TOKEN_GT));
        case '&': return make_token(TOKEN_AMP);
        case '|': return make_token(TOKEN_PIPE);
        case '^': return make_token(TOKEN_CARET);
        case '~': return make_token(TOKEN_TILDE);
        case '@': return make_token(TOKEN_AT);
    }

    return error_token("Unexpected character.");
    } // end for(;;)
}
