#ifndef TOKENIZER_H
#define TOKENIZER_H

#define MAX_TOKEN_COUNT 256      // Maximum number of tokens
#define MAX_TOKEN_LENGTH 64      // Maximum length of a single token

typedef struct {
    char tokens[MAX_TOKEN_COUNT][MAX_TOKEN_LENGTH];  // Array of tokens
    int count;                                       // Number of tokens
} TokenList;

// Function prototypes
void tokenize(const char *source_code, TokenList *token_list);

#endif // TOKENIZER_H
