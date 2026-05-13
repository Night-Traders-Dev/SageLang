#include "typecheck.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gc.h"

// ============================================================================
// TypeMap Implementation
// ============================================================================

void typemap_init(TypeMap* map) {
    map->entries = NULL;
    map->env = NULL;
}

void typemap_free(TypeMap* map) {
    TypeEntry* e = map->entries;
    while (e != NULL) {
        TypeEntry* next = e->next;
        free(e);
        e = next;
    }
    TypeEnv* v = map->env;
    while (v != NULL) {
        TypeEnv* next = v->next;
        free(v->name);
        free(v);
        v = next;
    }
    map->entries = NULL;
    map->env = NULL;
}

void typemap_set(TypeMap* map, const Expr* expr, SageType type) {
    TypeEntry* e = malloc(sizeof(TypeEntry));
    e->expr = expr;
    e->type = type;
    e->next = map->entries;
    map->entries = e;
}

SageType typemap_get(TypeMap* map, const Expr* expr) {
    for (TypeEntry* e = map->entries; e != NULL; e = e->next) {
        if (e->expr == expr) return e->type;
    }
    SageType unknown = { SAGE_TYPE_UNKNOWN };
    return unknown;
}

void typeenv_set(TypeMap* map, const char* name, SageType type) {
    // Update existing entry if found
    for (TypeEnv* v = map->env; v != NULL; v = v->next) {
        if (strcmp(v->name, name) == 0) {
            v->type = type;
            return;
        }
    }
    TypeEnv* v = malloc(sizeof(TypeEnv));
    v->name = strdup(name);
    v->type = type;
    v->next = map->env;
    map->env = v;
}

SageType typeenv_get(TypeMap* map, const char* name) {
    for (TypeEnv* v = map->env; v != NULL; v = v->next) {
        if (strcmp(v->name, name) == 0) return v->type;
    }
    SageType unknown = { SAGE_TYPE_UNKNOWN };
    return unknown;
}

// ============================================================================
// Type Inference
// ============================================================================

static SageType make_type(SageTypeKind kind) {
    SageType t = { kind };
    return t;
}

static const char* type_kind_name(SageTypeKind kind) {
    switch (kind) {
        case SAGE_TYPE_NIL:     return "Nil";
        case SAGE_TYPE_NUMBER:  return "Number";
        case SAGE_TYPE_BOOL:    return "Bool";
        case SAGE_TYPE_STRING:  return "String";
        case SAGE_TYPE_ARRAY:   return "Array";
        case SAGE_TYPE_DICT:    return "Dict";
        case SAGE_TYPE_TUPLE:   return "Tuple";
        case SAGE_TYPE_PROC:    return "Function";
        default:                return "Unknown";
    }
}

static SageTypeKind annotation_to_kind(const TypeAnnotation* ann) {
    if (!ann) return SAGE_TYPE_UNKNOWN;
    const char* n = ann->name.start;
    int len = ann->name.length;
    if (len == 3 && strncmp(n, "Int", 3) == 0) return SAGE_TYPE_NUMBER;
    if (len == 5 && strncmp(n, "Float", 5) == 0) return SAGE_TYPE_NUMBER;
    if (len == 6 && strncmp(n, "Number", 6) == 0) return SAGE_TYPE_NUMBER;
    if (len == 4 && strncmp(n, "Bool", 4) == 0) return SAGE_TYPE_BOOL;
    if (len == 6 && strncmp(n, "String", 6) == 0) return SAGE_TYPE_STRING;
    if (len == 3 && strncmp(n, "Str", 3) == 0) return SAGE_TYPE_STRING;
    if (len == 5 && strncmp(n, "Array", 5) == 0) return SAGE_TYPE_ARRAY;
    if (len == 4 && strncmp(n, "Dict", 4) == 0) return SAGE_TYPE_DICT;
    if (len == 5 && strncmp(n, "Tuple", 5) == 0) return SAGE_TYPE_TUPLE;
    if (len == 3 && strncmp(n, "Nil", 3) == 0) return SAGE_TYPE_NIL;
    if (len == 8 && strncmp(n, "Function", 8) == 0) return SAGE_TYPE_PROC;
    if (len == 4 && strncmp(n, "Proc", 4) == 0) return SAGE_TYPE_PROC;
    return SAGE_TYPE_UNKNOWN;
}

static void type_warning(const char* msg, const Token* tok, const char* expected, const char* got) {
    if (tok && tok->start) {
        fprintf(stderr, "Type Warning [line %d]: %s (expected %s, got %s)\n",
                tok->line > 0 ? tok->line : 0, msg, expected, got);
    } else {
        fprintf(stderr, "Type Warning: %s (expected %s, got %s)\n", msg, expected, got);
    }
}

static SageType infer_expr(TypeMap* map, const Expr* expr) {
    if (expr == NULL) return make_type(SAGE_TYPE_UNKNOWN);

    SageType result;

    switch (expr->type) {
        case EXPR_NUMBER:
            result = make_type(SAGE_TYPE_NUMBER);
            break;
        case EXPR_STRING:
            result = make_type(SAGE_TYPE_STRING);
            break;
        case EXPR_BOOL:
            result = make_type(SAGE_TYPE_BOOL);
            break;
        case EXPR_NIL:
            result = make_type(SAGE_TYPE_NIL);
            break;
        case EXPR_ARRAY:
            result = make_type(SAGE_TYPE_ARRAY);
            break;
        case EXPR_DICT:
            result = make_type(SAGE_TYPE_DICT);
            break;
        case EXPR_TUPLE:
            result = make_type(SAGE_TYPE_TUPLE);
            break;
        case EXPR_VARIABLE: {
            int len = expr->as.variable.name.length;
            char* name = SAGE_ALLOC((size_t)len + 1);
            memcpy(name, expr->as.variable.name.start, (size_t)len);
            name[len] = '\0';
            result = typeenv_get(map, name);
            free(name);
            break;
        }
        case EXPR_BINARY: {
            SageType left = infer_expr(map, expr->as.binary.left);
            SageType right = infer_expr(map, expr->as.binary.right);

            // Arithmetic on numbers produces number
            if (left.kind == SAGE_TYPE_NUMBER && right.kind == SAGE_TYPE_NUMBER) {
                const char* op = expr->as.binary.op.start;
                int op_len = expr->as.binary.op.length;
                if (op_len == 1 && (*op == '+' || *op == '-' || *op == '*' || *op == '/' || *op == '%')) {
                    result = make_type(SAGE_TYPE_NUMBER);
                } else {
                    // comparison ops produce bool
                    result = make_type(SAGE_TYPE_BOOL);
                }
            }
            // String concatenation
            else if (left.kind == SAGE_TYPE_STRING && right.kind == SAGE_TYPE_STRING) {
                const char* op = expr->as.binary.op.start;
                if (expr->as.binary.op.length == 1 && *op == '+') {
                    result = make_type(SAGE_TYPE_STRING);
                } else {
                    result = make_type(SAGE_TYPE_BOOL);
                }
            }
            // Comparisons always produce bool
            else if (expr->as.binary.op.length == 2) {
                result = make_type(SAGE_TYPE_BOOL);
            } else {
                result = make_type(SAGE_TYPE_UNKNOWN);
            }
            break;
        }
        case EXPR_CALL:
            // We don't track function return types yet
            result = make_type(SAGE_TYPE_UNKNOWN);
            break;
        case EXPR_INDEX:
            result = make_type(SAGE_TYPE_UNKNOWN);
            break;
        case EXPR_INDEX_SET:
            infer_expr(map, expr->as.index_set.array);
            infer_expr(map, expr->as.index_set.index);
            infer_expr(map, expr->as.index_set.value);
            result = make_type(SAGE_TYPE_UNKNOWN);
            break;
        case EXPR_SLICE:
            result = make_type(SAGE_TYPE_UNKNOWN);
            break;
        case EXPR_GET:
            result = make_type(SAGE_TYPE_UNKNOWN);
            break;
        case EXPR_SET:
            result = make_type(SAGE_TYPE_UNKNOWN);
            break;
        case EXPR_AWAIT:
            break;
    }

    typemap_set(map, expr, result);
    return result;
}

static void infer_stmt(TypeMap* map, Stmt* stmt);

static void infer_stmt_list(TypeMap* map, Stmt* head) {
    for (Stmt* s = head; s != NULL; s = s->next) {
        infer_stmt(map, s);
    }
}

static void infer_stmt(TypeMap* map, Stmt* stmt) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_PRINT:
            infer_expr(map, stmt->as.print.expression);
            break;
        case STMT_EXPRESSION:
            infer_expr(map, stmt->as.expression);
            break;
        case STMT_LET: {
            SageType t = infer_expr(map, stmt->as.let.initializer);
            // If type annotation present, use it and validate
            if (stmt->as.let.type_ann) {
                SageTypeKind declared = annotation_to_kind(stmt->as.let.type_ann);
                if (declared != SAGE_TYPE_UNKNOWN && t.kind != SAGE_TYPE_UNKNOWN && t.kind != declared) {
                    type_warning("type mismatch in let binding",
                                 &stmt->as.let.name,
                                 type_kind_name(declared),
                                 type_kind_name(t.kind));
                }
                if (declared != SAGE_TYPE_UNKNOWN) {
                    t = make_type(declared);
                }
            }
            int len = stmt->as.let.name.length;
            char* name = SAGE_ALLOC((size_t)len + 1);
            memcpy(name, stmt->as.let.name.start, (size_t)len);
            name[len] = '\0';
            typeenv_set(map, name, t);
            free(name);
            break;
        }
        case STMT_IF:
            infer_expr(map, stmt->as.if_stmt.condition);
            infer_stmt_list(map, stmt->as.if_stmt.then_branch);
            infer_stmt_list(map, stmt->as.if_stmt.else_branch);
            break;
        case STMT_BLOCK:
            infer_stmt_list(map, stmt->as.block.statements);
            break;
        case STMT_WHILE:
            infer_expr(map, stmt->as.while_stmt.condition);
            infer_stmt_list(map, stmt->as.while_stmt.body);
            break;
        case STMT_PROC: {
            // Register parameter types in scope
            for (int i = 0; i < stmt->as.proc.param_count; i++) {
                Token param = stmt->as.proc.params[i];
                char* pname = SAGE_ALLOC((size_t)param.length + 1);
                memcpy(pname, param.start, (size_t)param.length);
                pname[param.length] = '\0';
                SageType pt = make_type(SAGE_TYPE_UNKNOWN);
                if (stmt->as.proc.param_types && stmt->as.proc.param_types[i]) {
                    SageTypeKind k = annotation_to_kind(stmt->as.proc.param_types[i]);
                    if (k != SAGE_TYPE_UNKNOWN) pt = make_type(k);
                }
                typeenv_set(map, pname, pt);
                free(pname);
            }
            // Register proc name as function type
            int nlen = stmt->as.proc.name.length;
            char* fname = SAGE_ALLOC((size_t)nlen + 1);
            memcpy(fname, stmt->as.proc.name.start, (size_t)nlen);
            fname[nlen] = '\0';
            typeenv_set(map, fname, make_type(SAGE_TYPE_PROC));
            free(fname);
            infer_stmt_list(map, stmt->as.proc.body);
            break;
        }
        case STMT_FOR:
            infer_expr(map, stmt->as.for_stmt.iterable);
            infer_stmt_list(map, stmt->as.for_stmt.body);
            break;
        case STMT_RETURN:
            infer_expr(map, stmt->as.ret.value);
            break;
        case STMT_CLASS:
            infer_stmt_list(map, stmt->as.class_stmt.methods);
            break;
        case STMT_MATCH:
            infer_expr(map, stmt->as.match_stmt.value);
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                infer_expr(map, stmt->as.match_stmt.cases[i]->pattern);
                infer_stmt_list(map, stmt->as.match_stmt.cases[i]->body);
            }
            infer_stmt_list(map, stmt->as.match_stmt.default_case);
            break;
        case STMT_DEFER:
            infer_stmt(map, stmt->as.defer.statement);
            break;
        case STMT_TRY:
            infer_stmt_list(map, stmt->as.try_stmt.try_block);
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                infer_stmt_list(map, stmt->as.try_stmt.catches[i]->body);
            }
            infer_stmt_list(map, stmt->as.try_stmt.finally_block);
            break;
        case STMT_RAISE:
            infer_expr(map, stmt->as.raise.exception);
            break;
        case STMT_YIELD:
            infer_expr(map, stmt->as.yield_stmt.value);
            break;
        case STMT_IMPORT:
        case STMT_BREAK:
        case STMT_CONTINUE:
        case STMT_ASYNC_PROC:
            break;
    }
}

// ============================================================================
// Type Check Pass Entry Point
// ============================================================================

Stmt* pass_typecheck(Stmt* program, PassContext* ctx) {
    (void)ctx;
    TypeMap map;
    typemap_init(&map);
    infer_stmt_list(&map, program);
    typemap_free(&map);
    // Type checking is informational for now; does not transform AST
    return program;
}
