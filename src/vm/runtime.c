#include "runtime.h"
#include "bytecode.h"
#include "vm.h"

#include <stdio.h>
#include <string.h>

#include "gc.h"

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
