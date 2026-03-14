#include "diagnostic.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int digit_count(int value) {
    int digits = 1;
    while (value >= 10) {
        value /= 10;
        digits++;
    }
    return digits;
}

static void print_repeated(FILE* out, char ch, int count) {
    for (int i = 0; i < count; i++) {
        fputc(ch, out);
    }
}

const char* sage_token_type_name(TokenType type) {
    switch (type) {
        case TOKEN_LET: return "LET";
        case TOKEN_VAR: return "VAR";
        case TOKEN_PROC: return "PROC";
        case TOKEN_IF: return "IF";
        case TOKEN_ELSE: return "ELSE";
        case TOKEN_WHILE: return "WHILE";
        case TOKEN_FOR: return "FOR";
        case TOKEN_RETURN: return "RETURN";
        case TOKEN_PRINT: return "PRINT";
        case TOKEN_AND: return "AND";
        case TOKEN_OR: return "OR";
        case TOKEN_NOT: return "NOT";
        case TOKEN_IN: return "IN";
        case TOKEN_BREAK: return "BREAK";
        case TOKEN_CONTINUE: return "CONTINUE";
        case TOKEN_CLASS: return "CLASS";
        case TOKEN_SELF: return "SELF";
        case TOKEN_INIT: return "INIT";
        case TOKEN_MATCH: return "MATCH";
        case TOKEN_CASE: return "CASE";
        case TOKEN_DEFAULT: return "DEFAULT";
        case TOKEN_TRY: return "TRY";
        case TOKEN_CATCH: return "CATCH";
        case TOKEN_FINALLY: return "FINALLY";
        case TOKEN_RAISE: return "RAISE";
        case TOKEN_DEFER: return "DEFER";
        case TOKEN_YIELD: return "YIELD";
        case TOKEN_ASYNC: return "ASYNC";
        case TOKEN_AWAIT: return "AWAIT";
        case TOKEN_IMPORT: return "IMPORT";
        case TOKEN_FROM: return "FROM";
        case TOKEN_AS: return "AS";
        case TOKEN_LPAREN: return "LPAREN";
        case TOKEN_RPAREN: return "RPAREN";
        case TOKEN_PLUS: return "PLUS";
        case TOKEN_MINUS: return "MINUS";
        case TOKEN_STAR: return "STAR";
        case TOKEN_SLASH: return "SLASH";
        case TOKEN_PERCENT: return "PERCENT";
        case TOKEN_ASSIGN: return "ASSIGN";
        case TOKEN_EQ: return "EQ";
        case TOKEN_NEQ: return "NEQ";
        case TOKEN_LT: return "LT";
        case TOKEN_GT: return "GT";
        case TOKEN_LTE: return "LTE";
        case TOKEN_GTE: return "GTE";
        case TOKEN_COLON: return "COLON";
        case TOKEN_COMMA: return "COMMA";
        case TOKEN_LBRACKET: return "LBRACKET";
        case TOKEN_RBRACKET: return "RBRACKET";
        case TOKEN_LBRACE: return "LBRACE";
        case TOKEN_RBRACE: return "RBRACE";
        case TOKEN_DOT: return "DOT";
        case TOKEN_AMP: return "AMP";
        case TOKEN_PIPE: return "PIPE";
        case TOKEN_CARET: return "CARET";
        case TOKEN_TILDE: return "TILDE";
        case TOKEN_LSHIFT: return "LSHIFT";
        case TOKEN_RSHIFT: return "RSHIFT";
        case TOKEN_IDENTIFIER: return "IDENTIFIER";
        case TOKEN_NUMBER: return "NUMBER";
        case TOKEN_STRING: return "STRING";
        case TOKEN_TRUE: return "TRUE";
        case TOKEN_FALSE: return "FALSE";
        case TOKEN_NIL: return "NIL";
        case TOKEN_INDENT: return "INDENT";
        case TOKEN_DEDENT: return "DEDENT";
        case TOKEN_NEWLINE: return "NEWLINE";
        case TOKEN_EOF: return "EOF";
        case TOKEN_ERROR: return "ERROR";
    }
    return "UNKNOWN";
}

const char* sage_token_display_name(TokenType type) {
    switch (type) {
        case TOKEN_IDENTIFIER: return "identifier";
        case TOKEN_NUMBER: return "number";
        case TOKEN_STRING: return "string";
        case TOKEN_NEWLINE: return "end of line";
        case TOKEN_EOF: return "end of file";
        case TOKEN_INDENT: return "indentation";
        case TOKEN_DEDENT: return "dedent";
        case TOKEN_LPAREN: return "'('";
        case TOKEN_RPAREN: return "')'";
        case TOKEN_LBRACKET: return "'['";
        case TOKEN_RBRACKET: return "']'";
        case TOKEN_LBRACE: return "'{'";
        case TOKEN_RBRACE: return "'}'";
        case TOKEN_PLUS: return "'+'";
        case TOKEN_MINUS: return "'-'";
        case TOKEN_STAR: return "'*'";
        case TOKEN_SLASH: return "'/'";
        case TOKEN_PERCENT: return "'%'";
        case TOKEN_ASSIGN: return "'='";
        case TOKEN_EQ: return "'=='";
        case TOKEN_NEQ: return "'!='";
        case TOKEN_LT: return "'<'";
        case TOKEN_GT: return "'>'";
        case TOKEN_LTE: return "'<='";
        case TOKEN_GTE: return "'>='";
        case TOKEN_COLON: return "':'";
        case TOKEN_COMMA: return "','";
        case TOKEN_DOT: return "'.'";
        case TOKEN_AMP: return "'&'";
        case TOKEN_PIPE: return "'|'";
        case TOKEN_CARET: return "'^'";
        case TOKEN_TILDE: return "'~'";
        case TOKEN_LSHIFT: return "'<<'";
        case TOKEN_RSHIFT: return "'>>'";
        default: {
            static char lowered[32];
            const char* raw = sage_token_type_name(type);
            size_t len = strlen(raw);
            if (len >= sizeof(lowered)) len = sizeof(lowered) - 1;
            for (size_t i = 0; i < len; i++) {
                lowered[i] = (char)tolower((unsigned char)raw[i]);
            }
            lowered[len] = '\0';
            return lowered;
        }
    }
}

void sage_vprint_token_diagnosticf(const char* severity, const Token* token,
                                   const char* fallback_filename, int span,
                                   const char* help, const char* fmt,
                                   va_list args) {
    const char* filename = fallback_filename != NULL ? fallback_filename : "<input>";
    int line = 0;
    int column = 0;
    const char* line_start = NULL;
    int line_len = 0;

    if (token != NULL) {
        if (token->filename != NULL && token->filename[0] != '\0') {
            filename = token->filename;
        }
        line = token->line;
        column = token->column;
        line_start = token->line_start;
    }

    fprintf(stderr, "%s: ", severity);
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);

    if (line > 0) {
        fprintf(stderr, "  --> %s:%d:%d\n", filename, line, column + 1);
    } else {
        fprintf(stderr, "  --> %s\n", filename);
    }

    if (line_start != NULL && line > 0) {
        while (line_start[line_len] != '\0' &&
               line_start[line_len] != '\n' &&
               line_start[line_len] != '\r') {
            line_len++;
        }

        int gutter = digit_count(line);
        fprintf(stderr, "%*s |\n", gutter, "");
        fprintf(stderr, "%*d | %.*s\n", gutter, line, line_len, line_start);
        fprintf(stderr, "%*s | ", gutter, "");
        if (column > 0) {
            print_repeated(stderr, ' ', column);
        }
        if (span <= 1) {
            fputc('^', stderr);
        } else {
            print_repeated(stderr, '~', span);
        }
        fputc('\n', stderr);
    }

    if (help != NULL && help[0] != '\0') {
        fprintf(stderr, "  = help: %s\n", help);
    }
}

void sage_print_token_diagnosticf(const char* severity, const Token* token,
                                  const char* fallback_filename, int span,
                                  const char* help, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    sage_vprint_token_diagnosticf(severity, token, fallback_filename, span,
                                  help, fmt, args);
    va_end(args);
}
