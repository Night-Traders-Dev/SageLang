#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "lexer.h"
#include "utils.h"


TokenList lex(const char *source) {
    TokenList tokens = {.count = 0};
    const char *ptr = source;

    while (*ptr) {
        if (tokens.count >= MAX_TOKENS) {
            fprintf(stderr, "Error: Too many tokens\n");
            exit(EXIT_FAILURE);
        }


        // Skip whitespace
        if (isspace(*ptr)) {
            ptr++;
            continue;
        }

        // Recognize keywords: "print", "let"
        if (strncmp(ptr, "print", 5) == 0 && isspace(ptr[5])) {
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_PRINT, .value = strdup("print")};
            ptr += 5;
            continue;
        }
        if (strncmp(ptr, "let", 3) == 0 && isspace(ptr[3])) {
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_IDENTIFIER, .value = strdup("let")};
            ptr += 3;
            continue;
        }

        // Recognize string literals
        if (*ptr == '"') {
            const char *start = ++ptr;
            while (*ptr && *ptr != '"') ptr++;
            if (*ptr != '"') {
                fprintf(stderr, "Error: Unterminated string literal\n");
                exit(EXIT_FAILURE);
            }
            size_t length = ptr - start;
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_STRING, .value = strndup(start, length)};
            ptr++; // Skip closing quote
            continue;
        }

        // Recognize identifiers (variable names)
        if (isalpha(*ptr)) {
            const char *start = ptr;
            while (isalnum(*ptr) || *ptr == '_') ptr++;
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_IDENTIFIER, .value = strndup(start, ptr - start)};
            continue;
        }

        // Recognize numbers
        if (isdigit(*ptr)) {
            const char *start = ptr;
            while (isdigit(*ptr)) ptr++;
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_NUMBER, .value = strndup(start, ptr - start)};
            continue;
        }

        // Recognize operators (+, -, *, /, =)
        if (strchr("+-*/=", *ptr)) {
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_OPERATOR, .value = strndup(ptr, 1)};
            ptr++;
            continue;
        }

        fprintf(stderr, "Error: Unexpected character '%c'\n", *ptr);
        exit(EXIT_FAILURE);
    }

    return tokens;
}

void free_tokens(TokenList *tokens) {
    for (size_t i = 0; i < tokens->count; i++) {
        free(tokens->tokens[i].value);
    }
    tokens->count = 0;
}

