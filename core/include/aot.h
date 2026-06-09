#ifndef SAGE_AOT_H
#define SAGE_AOT_H

#include "ast.h"
#include "jit.h"

// ============================================================================
// AOT (Ahead-of-Time) Compiler for Sage
//
// Generates optimized C code with type specialization.
// Can work independently (whole-program compile) or with JIT
// (AOT provides baseline, JIT reoptimizes hot paths).
//
// Modes:
//   AOT-only:  sage --aot file.sage -o binary
//   JIT-only:  sage --jit file.sage
//   Combined:  sage --aot --jit file.sage (AOT baseline + JIT reopt)
// ============================================================================

// Type inference context for AOT
typedef struct {
    char* name;
    JitTypeTag inferred_type;
} AotVarType;

typedef struct {
    AotVarType* vars;
    int count;
    int capacity;
} AotTypeEnv;

// AOT compiler state
typedef struct {
    char** lines;       // Output C source lines
    int line_count;
    int line_capacity;
    int indent;
    int next_temp;
    AotTypeEnv type_env;
    int opt_level;       // 0-3
    int emit_guards;     // If 1, emit type guards (for JIT interop)
} AotCompiler;

// Lifecycle
void aot_init(AotCompiler* aot, int opt_level);
void aot_free(AotCompiler* aot);

// Type inference
void aot_infer_types(AotCompiler* aot, Stmt* program);
JitTypeTag aot_get_var_type(AotCompiler* aot, const char* name);
void aot_set_var_type(AotCompiler* aot, const char* name, JitTypeTag type);

// Compilation
char* aot_compile_program(AotCompiler* aot, Stmt* program);
void aot_compile_stmt(AotCompiler* aot, Stmt* stmt);
char* aot_compile_expr(AotCompiler* aot, Expr* expr);

// Specialized emission (optimized paths for known types)
char* aot_emit_add_int(AotCompiler* aot, const char* left, const char* right);
char* aot_emit_add_string(AotCompiler* aot, const char* left, const char* right);
char* aot_emit_add_generic(AotCompiler* aot, const char* left, const char* right);

// Output
int aot_write_c_file(AotCompiler* aot, const char* path);
int aot_compile_to_binary(AotCompiler* aot, const char* c_path, const char* bin_path);

#endif // SAGE_AOT_H
