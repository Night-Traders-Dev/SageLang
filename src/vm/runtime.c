#include "runtime.h"
#include "bytecode.h"
#include "vm.h"
#include "jit.h"
#include "aot.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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

ExecResult sage_execute_stmt(Stmt* stmt, Env* env, SageRuntimeMode mode) {
    if (stmt == NULL) {
        return runtime_normal(val_nil());
    }

    if (mode == SAGE_RUNTIME_AUTO) {
        mode = SAGE_RUNTIME_BYTECODE;
    }

    if (mode == SAGE_RUNTIME_JIT) {
        // JIT mode: interpret with profiling enabled
        if (!g_repl_jit_initialized) {
            jit_init(&g_repl_jit);
            g_repl_jit_initialized = 1;
            fprintf(stderr, "JIT: Enabled (threshold=%d calls, pool=%zuKB)\n",
                    JIT_HOT_THRESHOLD, g_repl_jit.pool.capacity / 1024);
        }
        interpreter_set_jit(&g_repl_jit);
        ExecResult result = interpret(stmt, env);
        // Leave JIT wired in for subsequent calls (persistent across REPL lines)
        return result;
    }

    if (mode == SAGE_RUNTIME_AOT) {
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
            char c_path[] = "/tmp/sage_aot_XXXXXX";
            int fd = mkstemp(c_path);
            if (fd >= 0) {
                FILE* f = fdopen(fd, "w");
                if (f) { fputs(c_code, f); fclose(f); }
                char bin_path[512];
                snprintf(bin_path, sizeof(bin_path), "%s.bin", c_path);
                if (aot_compile_to_binary(&aot, c_path, bin_path)) {
                    // Execute the compiled binary and capture output
                    char cmd[1024];
                    snprintf(cmd, sizeof(cmd), "%s", bin_path);
                    int ret = system(cmd);
                    unlink(bin_path);
                    unlink(c_path);
                    free(c_code);
                    aot_free(&aot);
                    if (ret != 0) {
                        return runtime_exception(val_exception("AOT: compiled binary returned non-zero"));
                    }
                    return runtime_normal(val_nil());
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
