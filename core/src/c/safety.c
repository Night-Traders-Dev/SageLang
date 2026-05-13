// src/c/safety.c - Compile-time safety analysis for SageLang
// Ownership tracking, borrow checking, lifetime analysis,
// Option type enforcement, concurrency safety, unsafe barriers.
//
// This is a DECOUPLED static analysis pass. It walks the AST after
// parsing and before code generation. Backends never see this pass;
// by the time code reaches the backend it has already been proven safe.

#include "../include/safety.h"
#include "../include/gc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ============================================================================
// Internal helpers
// ============================================================================

static char* safety_strdup(const char* s, int len) {
    if (!s) return NULL;
    char* d = SAGE_ALLOC(len + 1);
    memcpy(d, s, len);
    d[len] = '\0';
    return d;
}

static int name_eq(const char* a, int alen, const char* b, int blen) {
    if (alen != blen) return 0;
    return memcmp(a, b, alen) == 0;
}

// ============================================================================
// Safety Context
// ============================================================================

SafetyContext* safety_context_new(SafetyMode mode, const char* filename) {
    SafetyContext* ctx = SAGE_ALLOC(sizeof(SafetyContext));
    ctx->mode = mode;
    ctx->current_scope = NULL;
    ctx->diagnostics = NULL;
    ctx->diag_tail = NULL;
    ctx->error_count = 0;
    ctx->warning_count = 0;
    ctx->filename = filename;
    ctx->in_proc = 0;
    ctx->current_proc = NULL;
    // Push global scope
    safety_push_scope(ctx, 0, mode == SAFETY_MODE_STRICT ? 1 : 0);
    return ctx;
}

void safety_context_free(SafetyContext* ctx) {
    if (!ctx) return;
    // Free scopes
    while (ctx->current_scope) {
        safety_pop_scope(ctx);
    }
    // Free diagnostics
    SafetyDiag* d = ctx->diagnostics;
    while (d) {
        SafetyDiag* next = d->next;
        free(d);
        d = next;
    }
    free(ctx);
}

// ============================================================================
// Scope Management
// ============================================================================

SafetyScope* safety_push_scope(SafetyContext* ctx, int is_unsafe, int is_safe) {
    SafetyScope* scope = SAGE_ALLOC(sizeof(SafetyScope));
    scope->vars = NULL;
    scope->borrows = NULL;
    scope->lifetimes = NULL;
    scope->depth = ctx->current_scope ? ctx->current_scope->depth + 1 : 0;
    scope->is_unsafe = is_unsafe || (ctx->current_scope && ctx->current_scope->is_unsafe);
    scope->is_safe = is_safe || (ctx->current_scope && ctx->current_scope->is_safe);
    scope->next_lifetime_id = ctx->current_scope ? ctx->current_scope->next_lifetime_id : 1;
    scope->parent = ctx->current_scope;
    ctx->current_scope = scope;
    return scope;
}

void safety_pop_scope(SafetyContext* ctx) {
    SafetyScope* scope = ctx->current_scope;
    if (!scope) return;

    // Check for borrows that outlive their source (dangling references)
    Borrow* b = scope->borrows;
    while (b) {
        // The borrow was created in this scope; if the source is from an
        // outer scope, the reference is fine. If the source is local to
        // this scope, the reference will dangle.
        SafetyVar* src = safety_lookup(ctx, b->source, (int)strlen(b->source));
        if (src && src->scope_depth >= scope->depth) {
            // Source is local — reference escapes
            safety_emit(ctx, SAFETY_ERROR, SAFETY_DANGLING_REFERENCE,
                        "reference outlives the data it borrows",
                        "the borrowed value is destroyed at end of this scope",
                        b->line);
        }
        Borrow* next = b->next;
        free(b);
        b = next;
    }

    // Expire lifetimes
    Lifetime* lt = scope->lifetimes;
    while (lt) {
        Lifetime* next = lt->next;
        free(lt);
        lt = next;
    }

    // Release borrows on variables going out of scope
    SafetyVar* v = scope->vars;
    while (v) {
        SafetyVar* next = v->next;
        // Release any borrows this variable held
        if (v->state == OWN_BORROWED || v->state == OWN_MUT_BORROW) {
            // Find the source and decrement borrow count
            // (borrows are already cleaned up above)
        }
        free(v);
        v = next;
    }

    ctx->current_scope = scope->parent;
    free(scope);
}

// ============================================================================
// Variable Tracking
// ============================================================================

SafetyVar* safety_declare(SafetyContext* ctx, const char* name, int name_len, int line) {
    SafetyScope* scope = ctx->current_scope;
    if (!scope) return NULL;

    SafetyVar* var = SAGE_ALLOC(sizeof(SafetyVar));
    var->name = safety_strdup(name, name_len);
    var->name_len = name_len;
    var->state = OWN_UNINITIALIZED;
    var->is_option = 0;
    var->is_send = 1;  // Default: all types are Send
    var->is_sync = 0;  // Default: not Sync unless marked
    var->is_copy = 0;  // Default: move semantics
    var->decl_line = line;
    var->moved_line = 0;
    var->moved_to = NULL;
    var->borrow_count = 0;
    var->mut_borrow_count = 0;
    var->scope_depth = scope->depth;
    var->lifetime_id = scope->next_lifetime_id++;
    var->next = scope->vars;
    scope->vars = var;
    return var;
}

SafetyVar* safety_lookup(SafetyContext* ctx, const char* name, int name_len) {
    SafetyScope* scope = ctx->current_scope;
    while (scope) {
        SafetyVar* v = scope->vars;
        while (v) {
            if (name_eq(v->name, v->name_len, name, name_len)) {
                return v;
            }
            v = v->next;
        }
        scope = scope->parent;
    }
    return NULL;
}

void safety_mark_moved(SafetyContext* ctx, SafetyVar* var, int line, const char* dest) {
    if (!var) return;
    var->state = OWN_MOVED;
    var->moved_line = line;
    var->moved_to = dest;
}

void safety_mark_borrowed(SafetyContext* ctx, SafetyVar* var,
                           const char* borrower, int line, int is_mutable) {
    if (!var) return;
    (void)ctx; // used via current_scope
    SafetyScope* scope = ctx->current_scope;

    Borrow* b = SAGE_ALLOC(sizeof(Borrow));
    b->borrower = borrower;
    b->source = var->name;
    b->is_mutable = is_mutable;
    b->line = line;
    b->lifetime_id = var->lifetime_id;
    b->next = scope->borrows;
    scope->borrows = b;

    if (is_mutable) {
        var->mut_borrow_count++;
        var->state = OWN_MUT_BORROW;
    } else {
        var->borrow_count++;
        if (var->state == OWN_OWNED) var->state = OWN_BORROWED;
    }
}

// ============================================================================
// Ownership Checks
// ============================================================================

int safety_check_use(SafetyContext* ctx, const char* name, int name_len, int line) {
    SafetyVar* var = safety_lookup(ctx, name, name_len);
    if (!var) return 1; // Unknown variable — let the interpreter handle it

    if (var->state == OWN_MOVED) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "use of moved value '%s' (moved to '%s' at line %d)",
                 var->name, var->moved_to ? var->moved_to : "?", var->moved_line);
        safety_emit(ctx, SAFETY_ERROR, SAFETY_USE_AFTER_MOVE, msg,
                    "value was moved because it does not implement Copy",
                    line);
        return 0;
    }

    if (var->state == OWN_UNINITIALIZED) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "use of possibly uninitialized variable '%s'", var->name);
        safety_emit(ctx, SAFETY_ERROR, SAFETY_UNINITIALIZED_USE, msg,
                    "assign a value before using this variable",
                    line);
        return 0;
    }

    return 1;
}

int safety_check_move(SafetyContext* ctx, const char* name, int name_len,
                       int line, const char* dest) {
    SafetyVar* var = safety_lookup(ctx, name, name_len);
    if (!var) return 1;

    // Copy types don't move
    if (var->is_copy) return 1;

    if (var->state == OWN_MOVED) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "cannot move '%s': already moved at line %d",
                 var->name, var->moved_line);
        safety_emit(ctx, SAFETY_ERROR, SAFETY_DOUBLE_MOVE, msg,
                    "each value can only be moved once",
                    line);
        return 0;
    }

    if (var->borrow_count > 0 || var->mut_borrow_count > 0) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "cannot move '%s': it is currently borrowed", var->name);
        safety_emit(ctx, SAFETY_ERROR, SAFETY_BORROW_WHILE_MUTABLY_BORROWED, msg,
                    "wait until all borrows have ended before moving",
                    line);
        return 0;
    }

    safety_mark_moved(ctx, var, line, dest);
    return 1;
}

int safety_check_borrow(SafetyContext* ctx, const char* name, int name_len,
                         int line, int is_mutable) {
    SafetyVar* var = safety_lookup(ctx, name, name_len);
    if (!var) return 1;

    if (var->state == OWN_MOVED) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "cannot borrow '%s': value has been moved", var->name);
        safety_emit(ctx, SAFETY_ERROR, SAFETY_USE_AFTER_MOVE, msg,
                    "the value was moved and is no longer available",
                    line);
        return 0;
    }

    if (is_mutable) {
        // Mutable borrow: no other borrows allowed
        if (var->borrow_count > 0) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "cannot borrow '%s' as mutable: already borrowed as immutable",
                     var->name);
            safety_emit(ctx, SAFETY_ERROR, SAFETY_MUT_BORROW_WHILE_BORROWED, msg,
                        "an immutable reference exists; cannot create mutable reference",
                        line);
            return 0;
        }
        if (var->mut_borrow_count > 0) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "cannot borrow '%s' as mutable: already mutably borrowed",
                     var->name);
            safety_emit(ctx, SAFETY_ERROR, SAFETY_MULTIPLE_MUT_BORROWS, msg,
                        "only one mutable reference is allowed at a time",
                        line);
            return 0;
        }
    } else {
        // Immutable borrow: no mutable borrows allowed
        if (var->mut_borrow_count > 0) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "cannot borrow '%s' as immutable: already mutably borrowed",
                     var->name);
            safety_emit(ctx, SAFETY_ERROR, SAFETY_BORROW_WHILE_MUTABLY_BORROWED, msg,
                        "a mutable reference exists; cannot create immutable reference",
                        line);
            return 0;
        }
    }

    return 1;
}

// ============================================================================
// Option / Nil checks
// ============================================================================

int safety_check_nil_usage(SafetyContext* ctx, int line) {
    if (ctx->mode == SAFETY_MODE_STRICT ||
        (ctx->current_scope && ctx->current_scope->is_safe)) {
        safety_emit(ctx, SAFETY_ERROR, SAFETY_NIL_IN_SAFE_CONTEXT,
                    "nil is not allowed in safe context; use Option[T] instead",
                    "wrap the value in Some(value) or use None",
                    line);
        return 0;
    }
    return 1;
}

// ============================================================================
// Thread safety
// ============================================================================

int safety_check_send(SafetyContext* ctx, const char* name, int name_len, int line) {
    SafetyVar* var = safety_lookup(ctx, name, name_len);
    if (!var) return 1;
    if (!var->is_send) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "'%s' does not implement Send and cannot be transferred between threads",
                 var->name);
        safety_emit(ctx, SAFETY_ERROR, SAFETY_NOT_SEND, msg,
                    "mark the type as Send or use a thread-safe wrapper",
                    line);
        return 0;
    }
    return 1;
}

int safety_check_sync(SafetyContext* ctx, const char* name, int name_len, int line) {
    SafetyVar* var = safety_lookup(ctx, name, name_len);
    if (!var) return 1;
    if (!var->is_sync) {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "'%s' does not implement Sync and cannot be shared between threads",
                 var->name);
        safety_emit(ctx, SAFETY_ERROR, SAFETY_NOT_SYNC, msg,
                    "mark the type as Sync or use a Mutex wrapper",
                    line);
        return 0;
    }
    return 1;
}

// ============================================================================
// Unsafe context
// ============================================================================

int safety_in_unsafe(SafetyContext* ctx) {
    return ctx->current_scope && ctx->current_scope->is_unsafe;
}

// ============================================================================
// Diagnostics
// ============================================================================

void safety_emit(SafetyContext* ctx, SafetyLevel level, SafetyDiagKind kind,
                 const char* message, const char* hint, int line) {
    SafetyDiag* d = SAGE_ALLOC(sizeof(SafetyDiag));
    d->level = level;
    d->kind = kind;
    d->message = message;
    d->hint = hint;
    d->filename = ctx->filename;
    d->line = line;
    d->column = 0;
    d->next = NULL;

    if (ctx->diag_tail) {
        ctx->diag_tail->next = d;
    } else {
        ctx->diagnostics = d;
    }
    ctx->diag_tail = d;

    if (level == SAFETY_ERROR) ctx->error_count++;
    else ctx->warning_count++;
}

void safety_print_diagnostics(SafetyContext* ctx) {
    SafetyDiag* d = ctx->diagnostics;
    while (d) {
        const char* level_str = d->level == SAFETY_ERROR ? "error" : "warning";
        const char* kind_str = "";
        switch (d->kind) {
            case SAFETY_USE_AFTER_MOVE:     kind_str = "use-after-move"; break;
            case SAFETY_DOUBLE_MOVE:        kind_str = "double-move"; break;
            case SAFETY_BORROW_WHILE_MUTABLY_BORROWED: kind_str = "borrow-conflict"; break;
            case SAFETY_MUT_BORROW_WHILE_BORROWED:     kind_str = "borrow-conflict"; break;
            case SAFETY_MULTIPLE_MUT_BORROWS:          kind_str = "multiple-mut-borrow"; break;
            case SAFETY_DANGLING_REFERENCE: kind_str = "dangling-ref"; break;
            case SAFETY_LIFETIME_EXPIRED:   kind_str = "lifetime"; break;
            case SAFETY_NIL_IN_SAFE_CONTEXT: kind_str = "no-nil"; break;
            case SAFETY_UNWRAP_WITHOUT_CHECK: kind_str = "unwrap"; break;
            case SAFETY_UNSAFE_IN_SAFE_CONTEXT: kind_str = "unsafe-in-safe"; break;
            case SAFETY_NOT_SEND:           kind_str = "not-send"; break;
            case SAFETY_NOT_SYNC:           kind_str = "not-sync"; break;
            case SAFETY_UNINITIALIZED_USE:  kind_str = "uninitialized"; break;
            case SAFETY_PARTIAL_MOVE:       kind_str = "partial-move"; break;
        }
        fprintf(stderr, "%s[%s]: %s\n", level_str, kind_str, d->message);
        if (d->filename) {
            fprintf(stderr, "  --> %s:%d\n", d->filename, d->line);
        }
        if (d->hint) {
            fprintf(stderr, "  = help: %s\n", d->hint);
        }
        fprintf(stderr, "\n");
        d = d->next;
    }
}

int safety_has_errors(SafetyContext* ctx) {
    return ctx->error_count > 0;
}

// ============================================================================
// AST Walker - Expression Analysis
// ============================================================================

static void analyze_expr(SafetyContext* ctx, Expr* expr);
static void analyze_stmt(SafetyContext* ctx, Stmt* stmt);
static void analyze_stmt_list(SafetyContext* ctx, Stmt* head);

static void analyze_expr(SafetyContext* ctx, Expr* expr) {
    if (!expr) return;

    switch (expr->type) {
    case EXPR_VARIABLE: {
        const char* name = expr->as.variable.name.start;
        int len = expr->as.variable.name.length;
        int line = expr->as.variable.name.line;
        safety_check_use(ctx, name, len, line);
        break;
    }

    case EXPR_NIL:
        // nil usage checked at statement level, not here
        // (bare nil from 'end' keyword is a no-op, not an error)
        break;

    case EXPR_BINARY:
        analyze_expr(ctx, expr->as.binary.left);
        analyze_expr(ctx, expr->as.binary.right);
        break;

    case EXPR_CALL: {
        analyze_expr(ctx, expr->as.call.callee);
        // Each argument passed to a function is a potential move
        for (int i = 0; i < expr->as.call.arg_count; i++) {
            Expr* arg = expr->as.call.args[i];
            analyze_expr(ctx, arg);
            // If the argument is a variable, it may be moved into the function
            if (arg && arg->type == EXPR_VARIABLE) {
                const char* name = arg->as.variable.name.start;
                int len = arg->as.variable.name.length;
                int line = arg->as.variable.name.line;
                SafetyVar* var = safety_lookup(ctx, name, len);
                if (var && !var->is_copy && ctx->current_scope &&
                    ctx->current_scope->is_safe) {
                    // In safe mode, passing a variable moves it
                    safety_check_move(ctx, name, len, line, "(function argument)");
                }
            }
        }

        // Check for thread_spawn — enforces Send trait
        if (expr->as.call.callee && expr->as.call.callee->type == EXPR_VARIABLE) {
            const char* fn = expr->as.call.callee->as.variable.name.start;
            int flen = expr->as.call.callee->as.variable.name.length;
            if (name_eq(fn, flen, "thread_spawn", 12) ||
                name_eq(fn, flen, "async", 5)) {
                for (int i = 0; i < expr->as.call.arg_count; i++) {
                    Expr* arg = expr->as.call.args[i];
                    if (arg && arg->type == EXPR_VARIABLE) {
                        safety_check_send(ctx,
                            arg->as.variable.name.start,
                            arg->as.variable.name.length,
                            arg->as.variable.name.line);
                    }
                }
            }
        }
        break;
    }

    case EXPR_INDEX:
        analyze_expr(ctx, expr->as.index.array);
        analyze_expr(ctx, expr->as.index.index);
        break;

    case EXPR_INDEX_SET:
        analyze_expr(ctx, expr->as.index_set.array);
        analyze_expr(ctx, expr->as.index_set.index);
        analyze_expr(ctx, expr->as.index_set.value);
        break;

    case EXPR_GET:
        analyze_expr(ctx, expr->as.get.object);
        break;

    case EXPR_SET:
        analyze_expr(ctx, expr->as.set.object);
        analyze_expr(ctx, expr->as.set.value);
        // Assignment to property is a potential move of the value
        if (expr->as.set.value && expr->as.set.value->type == EXPR_VARIABLE) {
            Expr* val = expr->as.set.value;
            SafetyVar* var = safety_lookup(ctx,
                val->as.variable.name.start,
                val->as.variable.name.length);
            if (var && !var->is_copy && ctx->current_scope &&
                ctx->current_scope->is_safe) {
                safety_check_move(ctx,
                    val->as.variable.name.start,
                    val->as.variable.name.length,
                    val->as.variable.name.line,
                    "(property assignment)");
            }
        }
        break;

    case EXPR_ARRAY:
        for (int i = 0; i < expr->as.array.count; i++) {
            analyze_expr(ctx, expr->as.array.elements[i]);
        }
        break;

    case EXPR_DICT:
        for (int i = 0; i < expr->as.dict.count; i++) {
            analyze_expr(ctx, expr->as.dict.values[i]);
        }
        break;

    case EXPR_TUPLE:
        for (int i = 0; i < expr->as.tuple.count; i++) {
            analyze_expr(ctx, expr->as.tuple.elements[i]);
        }
        break;

    case EXPR_SLICE:
        analyze_expr(ctx, expr->as.slice.array);
        analyze_expr(ctx, expr->as.slice.start);
        analyze_expr(ctx, expr->as.slice.end);
        break;

    case EXPR_AWAIT:
        analyze_expr(ctx, expr->as.await.expression);
        break;

    case EXPR_NUMBER:
    case EXPR_STRING:
    case EXPR_BOOL:
    case EXPR_SUPER:
        break;
    }
}

// ============================================================================
// AST Walker - Statement Analysis
// ============================================================================

static void analyze_stmt(SafetyContext* ctx, Stmt* stmt) {
    if (!stmt) return;

    switch (stmt->type) {
    case STMT_LET: {
        Token name = stmt->as.let.name;
        SafetyVar* var = safety_declare(ctx, name.start, name.length, name.line);

        // Check type annotation for Option, Send, Sync, Copy
        TypeAnnotation* ann = stmt->as.let.type_ann;
        if (ann) {
            if (ann->is_optional) {
                var->is_option = 1;
            }
            // Check for Copy types: numbers, booleans, strings are Copy
            if (ann->name.length == 3 && memcmp(ann->name.start, "Int", 3) == 0) {
                var->is_copy = 1;
            }
            if (ann->name.length == 5 && memcmp(ann->name.start, "Float", 5) == 0) {
                var->is_copy = 1;
            }
            if (ann->name.length == 4 && memcmp(ann->name.start, "Bool", 4) == 0) {
                var->is_copy = 1;
            }
            if (ann->name.length == 6 && memcmp(ann->name.start, "String", 6) == 0) {
                var->is_copy = 1;
            }
            if (ann->name.length == 3 && memcmp(ann->name.start, "Num", 3) == 0) {
                var->is_copy = 1;
            }
        }

        // Analyze initializer
        if (stmt->as.let.initializer) {
            // Flag nil in safe context (Option enforcement)
            if (stmt->as.let.initializer->type == EXPR_NIL &&
                ctx->current_scope && ctx->current_scope->is_safe) {
                safety_check_nil_usage(ctx, name.line);
            }
            analyze_expr(ctx, stmt->as.let.initializer);
            var->state = OWN_OWNED;

            // If initializer is a variable, move from that variable
            Expr* init = stmt->as.let.initializer;
            if (init->type == EXPR_VARIABLE && !var->is_copy) {
                if (ctx->current_scope && ctx->current_scope->is_safe) {
                    safety_check_move(ctx,
                        init->as.variable.name.start,
                        init->as.variable.name.length,
                        name.line,
                        var->name);
                }
            }

            // Numbers, booleans, strings assigned from literals are Copy
            if (init->type == EXPR_NUMBER || init->type == EXPR_BOOL ||
                init->type == EXPR_STRING) {
                var->is_copy = 1;
            }
        }
        break;
    }

    case STMT_EXPRESSION:
        analyze_expr(ctx, stmt->as.expression);
        break;

    case STMT_PRINT:
        analyze_expr(ctx, stmt->as.print.expression);
        break;

    case STMT_IF:
        analyze_expr(ctx, stmt->as.if_stmt.condition);
        if (stmt->as.if_stmt.then_branch) {
            safety_push_scope(ctx, 0, 0);
            analyze_stmt(ctx, stmt->as.if_stmt.then_branch);
            safety_pop_scope(ctx);
        }
        if (stmt->as.if_stmt.else_branch) {
            safety_push_scope(ctx, 0, 0);
            analyze_stmt(ctx, stmt->as.if_stmt.else_branch);
            safety_pop_scope(ctx);
        }
        break;

    case STMT_WHILE:
        analyze_expr(ctx, stmt->as.while_stmt.condition);
        safety_push_scope(ctx, 0, 0);
        analyze_stmt(ctx, stmt->as.while_stmt.body);
        safety_pop_scope(ctx);
        break;

    case STMT_FOR:
        analyze_expr(ctx, stmt->as.for_stmt.iterable);
        safety_push_scope(ctx, 0, 0);
        // Declare loop variable
        safety_declare(ctx, stmt->as.for_stmt.variable.start,
                       stmt->as.for_stmt.variable.length,
                       stmt->as.for_stmt.variable.line);
        SafetyVar* loop_var = safety_lookup(ctx,
            stmt->as.for_stmt.variable.start,
            stmt->as.for_stmt.variable.length);
        if (loop_var) {
            loop_var->state = OWN_OWNED;
            loop_var->is_copy = 1; // Loop variables are rebound each iteration
        }
        analyze_stmt(ctx, stmt->as.for_stmt.body);
        safety_pop_scope(ctx);
        break;

    case STMT_BLOCK:
        safety_push_scope(ctx, 0, 0);
        analyze_stmt_list(ctx, stmt->as.block.statements);
        safety_pop_scope(ctx);
        break;

    case STMT_PROC:
    case STMT_ASYNC_PROC: {
        ProcStmt* proc = &stmt->as.proc;
        int was_in_proc = ctx->in_proc;
        const char* was_proc = ctx->current_proc;
        ctx->in_proc = 1;

        // Build proc name string
        char pname[256];
        int plen = proc->name.length < 255 ? proc->name.length : 255;
        memcpy(pname, proc->name.start, plen);
        pname[plen] = '\0';
        ctx->current_proc = pname;

        // Check for @safe annotation via doc comment
        int proc_safe = 0;
        if (proc->doc && strstr(proc->doc, "@safe")) {
            proc_safe = 1;
        }

        safety_push_scope(ctx, 0, proc_safe);

        // Declare parameters
        for (int i = 0; i < proc->param_count; i++) {
            SafetyVar* pvar = safety_declare(ctx,
                proc->params[i].start,
                proc->params[i].length,
                proc->params[i].line);
            if (pvar) {
                pvar->state = OWN_OWNED;
                // Check param type annotations for modifiers
                if (proc->param_types && proc->param_types[i]) {
                    TypeAnnotation* pt = proc->param_types[i];
                    // "ref" type prefix means immutable borrow
                    if (pt->name.length == 3 &&
                        memcmp(pt->name.start, "ref", 3) == 0) {
                        pvar->state = OWN_BORROWED;
                        pvar->is_copy = 1; // refs don't move
                    }
                    // "own" type prefix means explicit ownership transfer
                    if (pt->name.length == 3 &&
                        memcmp(pt->name.start, "own", 3) == 0) {
                        pvar->state = OWN_OWNED;
                    }
                    // Primitive types are Copy
                    if (pt->name.length == 3 && memcmp(pt->name.start, "Int", 3) == 0) pvar->is_copy = 1;
                    if (pt->name.length == 4 && memcmp(pt->name.start, "Bool", 4) == 0) pvar->is_copy = 1;
                    if (pt->name.length == 6 && memcmp(pt->name.start, "String", 6) == 0) pvar->is_copy = 1;
                    if (pt->name.length == 5 && memcmp(pt->name.start, "Float", 5) == 0) pvar->is_copy = 1;
                    if (pt->name.length == 3 && memcmp(pt->name.start, "Num", 3) == 0) pvar->is_copy = 1;
                }
            }
        }

        analyze_stmt(ctx, proc->body);
        safety_pop_scope(ctx);

        ctx->in_proc = was_in_proc;
        ctx->current_proc = was_proc;
        break;
    }

    case STMT_CLASS: {
        // Analyze methods
        Stmt* method = stmt->as.class_stmt.methods;
        while (method) {
            analyze_stmt(ctx, method);
            method = method->next;
        }
        break;
    }

    case STMT_RETURN:
        if (stmt->as.ret.value) {
            analyze_expr(ctx, stmt->as.ret.value);
        }
        break;

    case STMT_TRY:
        safety_push_scope(ctx, 0, 0);
        analyze_stmt(ctx, stmt->as.try_stmt.try_block);
        safety_pop_scope(ctx);
        for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
            safety_push_scope(ctx, 0, 0);
            CatchClause* cc = stmt->as.try_stmt.catches[i];
            safety_declare(ctx, cc->exception_var.start,
                          cc->exception_var.length, cc->exception_var.line);
            analyze_stmt(ctx, cc->body);
            safety_pop_scope(ctx);
        }
        if (stmt->as.try_stmt.finally_block) {
            safety_push_scope(ctx, 0, 0);
            analyze_stmt(ctx, stmt->as.try_stmt.finally_block);
            safety_pop_scope(ctx);
        }
        break;

    case STMT_RAISE:
        analyze_expr(ctx, stmt->as.raise.exception);
        break;

    case STMT_DEFER:
        analyze_stmt(ctx, stmt->as.defer.statement);
        break;

    case STMT_MATCH:
        analyze_expr(ctx, stmt->as.match_stmt.value);
        for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
            CaseClause* cc = stmt->as.match_stmt.cases[i];
            safety_push_scope(ctx, 0, 0);
            if (cc->guard) analyze_expr(ctx, cc->guard);
            analyze_stmt(ctx, cc->body);
            safety_pop_scope(ctx);
        }
        if (stmt->as.match_stmt.default_case) {
            safety_push_scope(ctx, 0, 0);
            analyze_stmt(ctx, stmt->as.match_stmt.default_case);
            safety_pop_scope(ctx);
        }
        break;

    case STMT_YIELD:
        if (stmt->as.yield_stmt.value) {
            analyze_expr(ctx, stmt->as.yield_stmt.value);
        }
        break;

    case STMT_IMPORT:
    case STMT_STRUCT:
    case STMT_ENUM:
    case STMT_TRAIT:
    case STMT_BREAK:
    case STMT_CONTINUE:
        break;
    }
}

static void analyze_stmt_list(SafetyContext* ctx, Stmt* head) {
    Stmt* current = head;
    while (current) {
        analyze_stmt(ctx, current);
        current = current->next;
    }
}

// ============================================================================
// Public Entry Points
// ============================================================================

int safety_analyze(Stmt* program, SafetyMode mode, const char* filename) {
    if (mode == SAFETY_MODE_OFF) return 1; // No checks

    SafetyContext* ctx = safety_context_new(mode, filename);
    analyze_stmt_list(ctx, program);

    if (ctx->error_count > 0 || ctx->warning_count > 0) {
        safety_print_diagnostics(ctx);
    }

    if (ctx->error_count > 0) {
        fprintf(stderr, "safety: %d error(s), %d warning(s)\n",
                ctx->error_count, ctx->warning_count);
    }

    int ok = !safety_has_errors(ctx);
    safety_context_free(ctx);
    return ok;
}

// Pass-compatible wrapper
Stmt* pass_safety(Stmt* program, PassContext* pctx) {
    // The safety pass runs in ANNOTATED mode when invoked as a pass
    // (--strict-safety uses direct safety_analyze call with STRICT mode)
    safety_analyze(program, SAFETY_MODE_ANNOTATED, pctx->input_path);
    return program; // Safety pass does not transform the AST
}
