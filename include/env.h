#ifndef SAGE_ENV_H
#define SAGE_ENV_H

#include "value.h"

typedef struct EnvNode {
    char* name;
    int name_length;        // Cached name length — avoids strlen in hot lookup path
    Value value;
    struct EnvNode* next;
} EnvNode;

typedef struct Env {
    EnvNode* head;      // Variables in this scope
    struct Env* parent; // Enclosing scope
    struct Env* alloc_next; // Internal registry for shutdown cleanup
    int marked;         // GC mark flag (0 = unmarked, 1 = reachable)
} Env;

Env* env_create(Env* parent);
void env_define(Env* env, const char* name, int length, Value value);
int env_get(Env* env, const char* name, int length, Value* value);
int env_assign(Env* env, const char* name, int length, Value value);
void env_cleanup_all(void);
void env_sweep_unmarked(void);
void env_clear_marks(void);

#endif
