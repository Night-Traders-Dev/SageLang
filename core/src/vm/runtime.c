#define _GNU_SOURCE
#include "runtime.h"
#include "bytecode.h"
#include "vm.h"
#include "jit.h"
#include "aot.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#include "gc.h"

// JIT/AOT integration — defined in interpreter.c
extern void interpreter_set_jit(JitState* jit_state);
extern JitState* interpreter_get_jit(void);

// Per-runtime-mode persistent state
static JitState g_repl_jit;
static int g_repl_jit_initialized = 0;

static ExecResult runtime_normal(Value value) {
    ExecResult result = {0};
    result.value = value;
    return result;
}

static ExecResult runtime_exception(Value value) {
    ExecResult result = {0};
    result.value = val_nil();
    result.is_throwing = 1;
    result.exception_value = value;
    return result;
}

const char* sage_runtime_mode_name(SageRuntimeMode mode) {
    switch (mode) {
        case SAGE_RUNTIME_AST: return "ast";
        case SAGE_RUNTIME_BYTECODE: return "bytecode";
        case SAGE_RUNTIME_JIT: return "jit";
        case SAGE_RUNTIME_AOT: return "aot";
        case SAGE_RUNTIME_AUTO: return "auto";
        default: return "unknown";
    }
}

int sage_runtime_parse_mode(const char* text, SageRuntimeMode* mode_out) {
    if (text == NULL || mode_out == NULL) {
        return 0;
    }
    if (strcmp(text, "ast") == 0) {
        *mode_out = SAGE_RUNTIME_AST;
        return 1;
    }
    if (strcmp(text, "bytecode") == 0 || strcmp(text, "vm") == 0) {
        *mode_out = SAGE_RUNTIME_BYTECODE;
        return 1;
    }
    if (strcmp(text, "jit") == 0) {
        *mode_out = SAGE_RUNTIME_JIT;
        return 1;
    }
    if (strcmp(text, "aot") == 0) {
        *mode_out = SAGE_RUNTIME_AOT;
        return 1;
    }
    if (strcmp(text, "auto") == 0) {
        *mode_out = SAGE_RUNTIME_AUTO;
        return 1;
    }
    return 0;
}

// Local pragma check (Pragma struct available via ast.h included from bytecode.h)
static int stmt_has_pragma(Stmt* stmt, const char* name) {
    if (!stmt || !stmt->pragmas) return 0;
    for (Pragma* p = stmt->pragmas; p; p = p->next) {
        if (strcmp(p->name, name) == 0) return 1;
    }
    return 0;
}

static int aot_expr_is_stateless(const Expr* expr) {
    if (!expr) return 1;
    switch (expr->type) {
        case EXPR_NUMBER:
        case EXPR_STRING:
        case EXPR_BOOL:
        case EXPR_NIL:
            return 1;
        case EXPR_BINARY:
            return 0;
        default:
            return 0;
    }
}

static int aot_stmt_list_requires_interpreter(const Stmt* stmt);

static int aot_stmt_requires_interpreter(const Stmt* stmt) {
    if (!stmt) return 0;
    for (const Stmt* current = stmt; current; current = current->next) {
        switch (current->type) {
            case STMT_PRINT:
                if (!aot_expr_is_stateless(current->as.print.expression)) return 1;
                break;
            case STMT_EXPRESSION:
                if (!aot_expr_is_stateless(current->as.expression)) return 1;
                break;
            case STMT_BLOCK:
                if (aot_stmt_list_requires_interpreter(current->as.block.statements))
                    return 1;
                break;
            case STMT_IF:
                if (!aot_expr_is_stateless(current->as.if_stmt.condition) ||
                    aot_stmt_list_requires_interpreter(current->as.if_stmt.then_branch) ||
                    aot_stmt_list_requires_interpreter(current->as.if_stmt.else_branch))
                    return 1;
                break;
            case STMT_MATCH: {
                if (!aot_expr_is_stateless(current->as.match_stmt.value))
                    return 1;
                for (int i = 0; i < current->as.match_stmt.case_count; i++) {
                    const CaseClause* clause = current->as.match_stmt.cases[i];
                    if (!aot_expr_is_stateless(clause->pattern) ||
                        (clause->guard && !aot_expr_is_stateless(clause->guard)) ||
                        aot_stmt_list_requires_interpreter(clause->body))
                        return 1;
                }
                if (aot_stmt_list_requires_interpreter(current->as.match_stmt.default_case))
                    return 1;
                break;
            }
            default:
                return 1;
        }
    }
    return 0;
}

static int aot_stmt_list_requires_interpreter(const Stmt* stmt) {
    return aot_stmt_requires_interpreter(stmt);
}

ExecResult sage_execute_stmt(Stmt* stmt, Env* env, SageRuntimeMode mode) {
    if (stmt == NULL) {
        return runtime_normal(val_nil());
    }

    // @VM pragma: force bytecode VM mode for this statement
    if (stmt_has_pragma(stmt, "VM")) {
        mode = SAGE_RUNTIME_BYTECODE;
    }
    // @no_vm pragma: force AST interpreter mode for this statement
    if (stmt_has_pragma(stmt, "no_vm")) {
        mode = SAGE_RUNTIME_AST;
    }

    if (mode == SAGE_RUNTIME_AUTO) {
        // Auto mode: JIT profiling + interpreter (hybrid).
        // The JIT profiles function calls and provides type feedback.
        // On bare-metal / Pico this falls back to AST (no fork/system).
#if SAGE_PLATFORM_PICO
        mode = SAGE_RUNTIME_AST;
#else
        mode = SAGE_RUNTIME_JIT;
#endif
    }

    if (mode == SAGE_RUNTIME_SANDBOX) {
        int previous_sandbox_mode = interpreter_sandbox_mode();
        interpreter_set_sandbox_mode(1);
        ExecResult result = interpret(stmt, env);
        interpreter_set_sandbox_mode(previous_sandbox_mode);
        return result;
    }

    if (mode == SAGE_RUNTIME_JIT) {
        // JIT mode: interpret with profiling enabled
        if (!g_repl_jit_initialized) {
            jit_init(&g_repl_jit);
            g_repl_jit_initialized = 1;
            // Only show JIT banner in explicit --jit mode (not auto)
        }
        interpreter_set_jit(&g_repl_jit);
        ExecResult result = interpret(stmt, env);
        // Leave JIT wired in for subsequent calls (persistent across REPL lines)
        return result;
    }

    if (mode == SAGE_RUNTIME_AOT) {
        if (aot_stmt_requires_interpreter(stmt)) {
            return interpret(stmt, env);
        }
        // AOT mode: compile statement to optimized C, then compile and run
        AotCompiler aot;
        aot_init(&aot, 2);

        // If JIT profiling data exists, transfer type feedback
        if (g_repl_jit_initialized) {
            aot.emit_guards = 1;
            for (int i = 0; i < g_repl_jit.profile_count; i++) {
                JitProfile* p = g_repl_jit.profiles[i];
                if (p && p->call_count > 0 && p->return_type != JIT_TYPE_UNKNOWN) {
                    char name[32];
                    snprintf(name, sizeof(name), "__func_%d", i);
                    aot_set_var_type(&aot, name, p->return_type);
                }
            }
        }

        char* c_code = aot_compile_program(&aot, stmt);
        if (c_code) {
            // Write and compile to temp binary
            char c_path[] = "/tmp/sage_aot_XXXXXX.c";
            int fd = mkstemps(c_path, 2);
            if (fd >= 0) {
                FILE* f = fdopen(fd, "w");
                if (f) { fputs(c_code, f); fclose(f); }
                char bin_path[] = "/tmp/sage_aot_bin_XXXXXX.bin";
                int bin_fd = mkstemps(bin_path, 4);
                if (bin_fd >= 0) {
                    close(bin_fd); // Close securely opened fd to allow compilation to overwrite it
                    if (aot_compile_to_binary(&aot, c_path, bin_path)) {
                        // Execute the compiled binary directly without invoking shell (CWE-78 defense-in-depth)
                        int ret = -1;
                        pid_t pid = fork();
                        if (pid == 0) {
                            char* args[] = {bin_path, NULL};
                            execv(bin_path, args);
                            _exit(127);
                        } else if (pid > 0) {
                            int status;
                            waitpid(pid, &status, 0);
                            if (WIFEXITED(status)) {
                                ret = WEXITSTATUS(status);
                            }
                        }
                        unlink(bin_path);
                        unlink(c_path);
                        free(c_code);
                        aot_free(&aot);
                        if (ret != 0) {
                            return runtime_exception(val_exception("AOT: compiled binary returned non-zero"));
                        }
                        return runtime_normal(val_nil());
                    }
                    unlink(bin_path);
                }
                unlink(c_path);
            }
        }

        // Fallback: if AOT compilation fails, interpret normally
        if (c_code) free(c_code);
        aot_free(&aot);
        fprintf(stderr, "AOT: Compilation failed, falling back to interpreter\n");
        return interpret(stmt, env);
    }

    if (mode == SAGE_RUNTIME_AST) {
        return interpret(stmt, env);
    }

    BytecodeChunk chunk;
    char error[256];
    bytecode_chunk_init(&chunk);

    gc_pin();
    int compiled = bytecode_compile_statement(&chunk, stmt, error, sizeof(error));
    gc_unpin();

    if (!compiled) {
        bytecode_chunk_free(&chunk);
        fprintf(stderr, "Bytecode compile error: %s\n", error[0] ? error : "unknown error");
        return runtime_exception(val_exception(error[0] ? error : "Bytecode compile error"));
    }

    ExecResult result = vm_execute_chunk(&chunk, env);
    bytecode_chunk_free(&chunk);
    return result;
}
