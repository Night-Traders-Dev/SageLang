// include/safety.h - Compile-time safety analysis for SageLang
// Ownership, Borrow Checking, Lifetime Tracking, Option Types,
// Fearless Concurrency, Unsafe Barriers
#ifndef SAGE_SAFETY_H
#define SAGE_SAFETY_H

#include "ast.h"
#include "pass.h"

// ============================================================================
// Safety Modes
// ============================================================================

typedef enum {
    SAFETY_MODE_OFF,       // Classic SageLang: no safety checks
    SAFETY_MODE_ANNOTATED, // Only check @safe-annotated functions/blocks
    SAFETY_MODE_STRICT     // --strict-safety: enforce everything globally
} SafetyMode;

// ============================================================================
// Ownership State
// ============================================================================

typedef enum {
    OWN_OWNED,      // Variable owns its data
    OWN_MOVED,      // Ownership transferred; variable is dead
    OWN_BORROWED,   // Immutable borrow active
    OWN_MUT_BORROW, // Mutable borrow active
    OWN_PARTIAL,    // Partially moved (struct field moved)
    OWN_UNINITIALIZED // Declared but not assigned
} OwnershipState;

// ============================================================================
// Borrow Tracking
// ============================================================================

typedef struct Borrow {
    const char* borrower;    // Name of the variable holding the reference
    const char* source;      // Name of the variable being borrowed
    int is_mutable;          // 1 = &mut, 0 = & (immutable)
    int line;                // Line where borrow was created
    int lifetime_id;         // Lifetime region ID
    struct Borrow* next;     // Linked list
} Borrow;

// ============================================================================
// Lifetime Region
// ============================================================================

typedef struct Lifetime {
    int id;                  // Unique ID for this lifetime
    int scope_depth;         // Block nesting depth where this lifetime starts
    int start_line;          // Line where lifetime begins
    int end_line;            // Line where lifetime ends (0 = still alive)
    const char* label;       // Optional lifetime label (e.g., 'a)
    struct Lifetime* next;
} Lifetime;

// ============================================================================
// Variable Entry in Safety Analysis
// ============================================================================

typedef struct SafetyVar {
    const char* name;        // Variable name
    int name_len;            // Length of name
    OwnershipState state;    // Current ownership state
    int is_option;           // 1 = Option[T] type
    int is_send;             // 1 = Send trait (safe to transfer between threads)
    int is_sync;             // 1 = Sync trait (safe to share between threads)
    int is_copy;             // 1 = Copy trait (implicit copy, no move)
    int decl_line;           // Line where declared
    int moved_line;          // Line where moved (0 = not moved)
    const char* moved_to;    // Where ownership was moved to
    int borrow_count;        // Number of active immutable borrows
    int mut_borrow_count;    // Number of active mutable borrows (max 1)
    int scope_depth;         // Block nesting depth
    int lifetime_id;         // Lifetime region for this variable
    struct SafetyVar* next;  // Linked list in scope
} SafetyVar;

// ============================================================================
// Safety Scope (block-level tracking)
// ============================================================================

typedef struct SafetyScope {
    SafetyVar* vars;         // Variables in this scope
    Borrow* borrows;         // Active borrows in this scope
    Lifetime* lifetimes;     // Lifetime regions
    int depth;               // Nesting depth
    int is_unsafe;           // 1 = inside unsafe block
    int is_safe;             // 1 = inside @safe annotation
    int next_lifetime_id;    // Counter for lifetime IDs
    struct SafetyScope* parent;
} SafetyScope;

// ============================================================================
// Safety Diagnostic
// ============================================================================

typedef enum {
    SAFETY_ERROR,    // Hard error (compilation fails)
    SAFETY_WARNING   // Warning (compilation continues)
} SafetyLevel;

typedef enum {
    SAFETY_USE_AFTER_MOVE,
    SAFETY_DOUBLE_MOVE,
    SAFETY_BORROW_WHILE_MUTABLY_BORROWED,
    SAFETY_MUT_BORROW_WHILE_BORROWED,
    SAFETY_MULTIPLE_MUT_BORROWS,
    SAFETY_DANGLING_REFERENCE,
    SAFETY_LIFETIME_EXPIRED,
    SAFETY_NIL_IN_SAFE_CONTEXT,
    SAFETY_UNWRAP_WITHOUT_CHECK,
    SAFETY_UNSAFE_IN_SAFE_CONTEXT,
    SAFETY_NOT_SEND,
    SAFETY_NOT_SYNC,
    SAFETY_UNINITIALIZED_USE,
    SAFETY_PARTIAL_MOVE
} SafetyDiagKind;

typedef struct SafetyDiag {
    SafetyLevel level;
    SafetyDiagKind kind;
    const char* message;
    const char* hint;
    const char* filename;
    int line;
    int column;
    struct SafetyDiag* next;
} SafetyDiag;

// ============================================================================
// Safety Context (top-level analysis state)
// ============================================================================

typedef struct {
    SafetyMode mode;
    SafetyScope* current_scope;
    SafetyDiag* diagnostics;
    SafetyDiag* diag_tail;
    int error_count;
    int warning_count;
    const char* filename;
    int in_proc;              // Currently inside a proc body
    const char* current_proc; // Name of current proc being analyzed
} SafetyContext;

// ============================================================================
// Public API
// ============================================================================

// Create/destroy safety context
SafetyContext* safety_context_new(SafetyMode mode, const char* filename);
void safety_context_free(SafetyContext* ctx);

// The main safety analysis pass (compatible with PassFn signature via wrapper)
Stmt* pass_safety(Stmt* program, PassContext* pctx);

// Run safety analysis with explicit mode
int safety_analyze(Stmt* program, SafetyMode mode, const char* filename);

// Scope management
SafetyScope* safety_push_scope(SafetyContext* ctx, int is_unsafe, int is_safe);
void safety_pop_scope(SafetyContext* ctx);

// Variable tracking
SafetyVar* safety_declare(SafetyContext* ctx, const char* name, int name_len, int line);
SafetyVar* safety_lookup(SafetyContext* ctx, const char* name, int name_len);
void safety_mark_moved(SafetyContext* ctx, SafetyVar* var, int line, const char* dest);
void safety_mark_borrowed(SafetyContext* ctx, SafetyVar* var, const char* borrower, int line, int is_mutable);

// Ownership checks
int safety_check_use(SafetyContext* ctx, const char* name, int name_len, int line);
int safety_check_move(SafetyContext* ctx, const char* name, int name_len, int line, const char* dest);
int safety_check_borrow(SafetyContext* ctx, const char* name, int name_len, int line, int is_mutable);

// Option type enforcement
int safety_check_nil_usage(SafetyContext* ctx, int line);

// Thread safety
int safety_check_send(SafetyContext* ctx, const char* name, int name_len, int line);
int safety_check_sync(SafetyContext* ctx, const char* name, int name_len, int line);

// Unsafe context
int safety_in_unsafe(SafetyContext* ctx);

// Diagnostics
void safety_emit(SafetyContext* ctx, SafetyLevel level, SafetyDiagKind kind,
                 const char* message, const char* hint, int line);
void safety_print_diagnostics(SafetyContext* ctx);
int safety_has_errors(SafetyContext* ctx);

#endif // SAGE_SAFETY_H
