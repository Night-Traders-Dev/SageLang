#ifndef SAGE_PASS_H
#define SAGE_PASS_H

#include "ast.h"

// ============================================================================
// Pass Context - shared state across optimization passes
// ============================================================================

typedef struct {
    int opt_level;          // 0-3
    int debug_info;         // emit debug info?
    int verbose;            // report pass activity?
    const char* input_path; // for diagnostics
} PassContext;

// ============================================================================
// Pass Interface
// ============================================================================

typedef Stmt* (*PassFn)(Stmt* program, PassContext* ctx);

typedef struct {
    const char* name;
    PassFn fn;
    int min_opt_level;  // minimum -O level to run this pass
} PassEntry;

// Run all enabled passes on program AST based on opt_level
Stmt* run_passes(Stmt* program, PassContext* ctx);

// ============================================================================
// AST Deep Clone (needed so passes can freely modify)
// ============================================================================

Expr* clone_expr(const Expr* expr);
Stmt* clone_stmt(const Stmt* stmt);
Stmt* clone_stmt_list(const Stmt* head);
Token clone_token(Token tok);

#endif
