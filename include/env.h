#ifndef SAGE_ENV_H
#define SAGE_ENV_H

#include "value.h"

typedef struct EnvNode {
    char* name;
    int name_length;        // Cached name length — avoids strlen in hot lookup path
    int owns_name;          // Whether this node owns (and must free) its name string
    Value value;
    struct EnvNode* next;
} EnvNode;

typedef struct Env {
    EnvNode* head;      // Variables in this scope
    struct Env* parent; // Enclosing scope
    struct Env* alloc_next; // Internal registry for shutdown cleanup
    unsigned long long id;  // Unique ID for inline caching
    int marked;         // GC mark flag (0 = unmarked, 1 = reachable)
} Env;

typedef struct EnvRootNode {
    Env* env;
    struct EnvRootNode* next;
} EnvRootNode;

extern __thread EnvRootNode* g_gc_root_stack;

Env* env_create(Env* parent);
void env_define(Env* env, const char* name, int length, Value value);
void env_define_const(Env* env, const char* name, int length, Value value);
int env_get(Env* env, const char* name, int length, Value* value);
int env_get_node(Env* env, const char* name, int length, Env** out_env, EnvNode** out_node);
int env_assign(Env* env, const char* name, int length, Value value);
void env_cleanup_all(void);
void env_sweep_unmarked(void);
void env_clear_marks(void);

#endif
