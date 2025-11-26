#ifndef SAGE_ENV_H
#define SAGE_ENV_H

typedef struct EnvNode {
    char* name;
    double value;
    struct EnvNode* next;
} EnvNode;

typedef struct Env {
    EnvNode* head;      // Variables in this scope
    struct Env* parent; // Enclosing scope
} Env;

Env* env_create(Env* parent);
void env_define(Env* env, const char* name, int length, double value);
int env_get(Env* env, const char* name, int length, double* value);

#endif
