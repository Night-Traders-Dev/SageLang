#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "env.h"
#include "gc.h"

static Env* allocated_envs = NULL;

// Helper function to duplicate a string with a max length (similar to strndup)
static char* my_strndup(const char* s, size_t n) {
    char* result;
    size_t len = 0;

    // Count length up to n or null terminator
    while (len < n && s[len] != '\0') {
        len++;
    }

    result = (char*)SAGE_ALLOC(len + 1);
    if (!result) return NULL;

    memcpy(result, s, len);
    result[len] = '\0'; // Explicit null terminator
    return result;
}

Env* env_create(Env* parent) {
    Env* env = SAGE_ALLOC(sizeof(Env));
    env->head = NULL;
    env->parent = parent;
    env->marked = 0;
    env->alloc_next = allocated_envs;
    allocated_envs = env;
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
    EnvNode* node = SAGE_ALLOC(sizeof(EnvNode));
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

// Assign to an existing variable (searches up the scope chain)
int env_assign(Env* env, const char* name, int length, Value value) {
    Env* current_env = env;

    // Search current scope, then parent, then parent's parent...
    while (current_env != NULL) {
        EnvNode* current = current_env->head;
        while (current != NULL) {
            if (strncmp(current->name, name, length) == 0 && current->name[length] == '\0') {
                current->value = value;
                return 1; // Found and updated
            }
            current = current->next;
        }
        current_env = current_env->parent;
    }
    return 0; // Not found
}

void env_cleanup_all(void) {
    while (allocated_envs != NULL) {
        Env* env = allocated_envs;
        allocated_envs = allocated_envs->alloc_next;

        EnvNode* current = env->head;
        while (current != NULL) {
            EnvNode* next = current->next;
            free(current->name);
            free(current);
            current = next;
        }

        free(env);
    }
}

// Free environments not marked as reachable during GC
void env_sweep_unmarked(void) {
    Env** ptr = &allocated_envs;
    while (*ptr != NULL) {
        Env* env = *ptr;
        if (!env->marked) {
            // Remove from list and free
            *ptr = env->alloc_next;

            EnvNode* node = env->head;
            while (node != NULL) {
                EnvNode* next = node->next;
                free(node->name);
                free(node);
                node = next;
            }
            free(env);
        } else {
            // Reachable — clear mark for next cycle and advance
            env->marked = 0;
            ptr = &env->alloc_next;
        }
    }
}

// Clear all env marks (used if sweep is skipped)
void env_clear_marks(void) {
    Env* env = allocated_envs;
    while (env != NULL) {
        env->marked = 0;
        env = env->alloc_next;
    }
}
