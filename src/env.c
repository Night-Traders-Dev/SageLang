#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "env.h"

// Helper function to duplicate a string with a max length (similar to strndup)
static char* my_strndup(const char* s, size_t n) {
    char* result;
    size_t len = 0;

    // Count length up to n or null terminator
    while (len < n && s[len] != '\0') {
        len++;
    }

    result = (char*)malloc(len + 1);
    if (!result) return NULL;

    memcpy(result, s, len);
    result[len] = '\0'; // Explicit null terminator
    return result;
}

Env* env_create(Env* parent) {
    Env* env = malloc(sizeof(Env));
    env->head = NULL;
    env->parent = parent;
    return env;
}


void env_define(Env* env, const char* name, int length, Value value) {
    // Search ONLY in current scope (head) to update
    EnvNode* current = env->head;
    while (current != NULL) {
        if (strncmp(current->name, name, length) == 0 && current->name[length] == '\0') {
            current->value = value;
            return;
        }
        current = current->next;
    }

    // Create new in current scope
    EnvNode* node = malloc(sizeof(EnvNode));
    node->name = my_strndup(name, length);
    node->value = value;
    node->next = env->head;
    env->head = node;
}


int env_get(Env* env, const char* name, int length, Value* out_value) {
    Env* current_env = env;

    // Search current scope, then parent, then parent's parent...
    while (current_env != NULL) {
        EnvNode* current = current_env->head;
        while (current != NULL) {
            if (strncmp(current->name, name, length) == 0 && current->name[length] == '\0') {
                *out_value = current->value;
                return 1;
            }
            current = current->next;
        }
        current_env = current_env->parent;
    }
    return 0;
}
