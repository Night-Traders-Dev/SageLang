#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "tokenizer.h"

void tokenize(const char *source_code, TokenList *token_list) {
    token_list->count = 0;
    const char *ptr = source_code;
    char token[MAX_TOKEN_LENGTH];
    int token_length = 0;

    while (*ptr) {
        // Skip whitespace
        if (isspace(*ptr)) {
            if (token_length > 0) {
                token[token_length] = '\0';  // Null-terminate the token
                strncpy(token_list->tokens[token_list->count++], token, MAX_TOKEN_LENGTH);
                token_length = 0;           // Reset token length
            }
        } else if (strchr("(){}=+-*/;,", *ptr)) {
            // Handle special characters as individual tokens
            if (token_length > 0) {
                token[token_length] = '\0';
                strncpy(token_list->tokens[token_list->count++], token, MAX_TOKEN_LENGTH);
                token_length = 0;
            }
            token_list->tokens[token_list->count][0] = *ptr;
            token_list->tokens[token_list->count++][1] = '\0';
        } else if (*ptr == '"') {
            // Handle strings inside quotes
            if (token_length > 0) {
                token[token_length] = '\0';
                strncpy(token_list->tokens[token_list->count++], token, MAX_TOKEN_LENGTH);
                token_length = 0;
            }
            token[token_length++] = *ptr++;  // Add opening quote
            while (*ptr && *ptr != '"') {
                if (token_length >= MAX_TOKEN_LENGTH - 1) {
                    fprintf(stderr, "Error: String token too long.\n");
                    exit(EXIT_FAILURE);
                }
                token[token_length++] = *ptr++;
            }
            if (*ptr == '"') {
                token[token_length++] = *ptr++;  // Add closing quote
            } else {
                fprintf(stderr, "Error: Unterminated string.\n");
                exit(EXIT_FAILURE);
            }
            token[token_length] = '\0';
            strncpy(token_list->tokens[token_list->count++], token, MAX_TOKEN_LENGTH);
            token_length = 0;
        } else {
            // Handle regular characters as part of a token
            if (token_length >= MAX_TOKEN_LENGTH - 1) {
                fprintf(stderr, "Error: Token too long.\n");
                exit(EXIT_FAILURE);
            }
            token[token_length++] = *ptr;
        }
        ptr++;
    }

    // Add the last token if there's any remaining
    if (token_length > 0) {
        token[token_length] = '\0';
        strncpy(token_list->tokens[token_list->count++], token, MAX_TOKEN_LENGTH);
    }

    // Debug: Print all tokens
    #ifdef DEBUG
    for (int i = 0; i < token_list->count; i++) {
        fprintf(stderr, "Token[%d]: %s\n", i, token_list->tokens[i]);
    }
    #endif
}
