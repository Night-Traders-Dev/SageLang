#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "lexer.h"

TokenList lex(const char *source) {
    TokenList tokens = {.count = 0};
    const char *ptr = source;

    while (*ptr) {
        if (isspace(*ptr)) {
            ptr++;
            continue;
        }
        if (strncmp(ptr, "print", 5) == 0 && isspace(ptr[5])) {
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_PRINT};
            ptr += 5;
        } else if (*ptr == '"') {
            const char *start = ++ptr;
            while (*ptr && *ptr != '"') ptr++;
            if (*ptr != '"') {
                fprintf(stderr, "Error: Unterminated string literal\n");
                exit(EXIT_FAILURE);
            }
            size_t length = ptr - start;
            char *value = malloc(length + 1);
            strncpy(value, start, length);
            value[length] = '\0';
            tokens.tokens[tokens.count++] = (Token){.type = TOKEN_STRING, .value = value};
            ptr++; // Skip closing quote
        } else {
            fprintf(stderr, "Error: Unexpected character '%c'\n", *ptr);
            exit(EXIT_FAILURE);
        }
    }
    return tokens;
}

void free_tokens(TokenList *tokens) {
    for (size_t i = 0; i < tokens->count; i++) {
        if (tokens->tokens[i].type == TOKEN_STRING) {
            free(tokens->tokens[i].value);
        }
    }
}
