#ifndef SAGE_TYPECHECK_H
#define SAGE_TYPECHECK_H

#include "ast.h"
#include "pass.h"

// ============================================================================
// Type Representation
// ============================================================================

typedef enum {
    SAGE_TYPE_UNKNOWN,
    SAGE_TYPE_NIL,
    SAGE_TYPE_NUMBER,
    SAGE_TYPE_BOOL,
    SAGE_TYPE_STRING,
    SAGE_TYPE_ARRAY,
    SAGE_TYPE_DICT,
    SAGE_TYPE_TUPLE,
    SAGE_TYPE_PROC,
} SageTypeKind;

typedef struct SageType {
    SageTypeKind kind;
} SageType;

// ============================================================================
// Type Map - associates Expr* pointers with inferred types
// ============================================================================

typedef struct TypeEntry {
    const Expr* expr;
    SageType type;
    struct TypeEntry* next;
} TypeEntry;

typedef struct TypeEnv {
    char* name;
    SageType type;
    struct TypeEnv* next;
} TypeEnv;

typedef struct {
    TypeEntry* entries;
    TypeEnv* env;
} TypeMap;

void typemap_init(TypeMap* map);
void typemap_free(TypeMap* map);
void typemap_set(TypeMap* map, const Expr* expr, SageType type);
SageType typemap_get(TypeMap* map, const Expr* expr);
void typeenv_set(TypeMap* map, const char* name, SageType type);
SageType typeenv_get(TypeMap* map, const char* name);

// Type checking pass
Stmt* pass_typecheck(Stmt* program, PassContext* ctx);

#endif
