#include "bytecode.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#include "gc.h"
#include "token.h"

#define MAX_LOOP_DEPTH 128
#define MAX_BREAK_PATCHES 128

typedef struct {
    int break_patches[MAX_BREAK_PATCHES];
    int break_count;
    int continue_target;
    int has_for_cleanup;  // for-loops need extra stack cleanup before break
    int for_pop_count;    // number of extra pops needed for for-loop break
    int local_count_at_entry;
} LoopContext;

typedef struct {
    Token name;
    int depth;
} Local;

#define MAX_LOCALS 256

typedef struct {
    BytecodeChunk* chunk;
    BytecodeCompileMode mode;
    BytecodeBuildFunctionFn build_function;
    void* build_function_data;
    int allow_return;
    char* error;
    size_t error_size;
    LoopContext loops[MAX_LOOP_DEPTH];
    int loop_depth;
    Local locals[MAX_LOCALS];
    int local_count;
    int scope_depth;
    // Whether local slots may be allocated at all. Locals are addressed as
    // absolute indices into the frame's slot array (frame->slots), which is only
    // meaningful inside a compiled function: there frame->slots points at the
    // argument block, so slot 0 is the first parameter and locals line up.
    //
    // The top-level chunk sets frame->slots = vm.stack, i.e. the bottom of the
    // VM stack, so slot 0 is merely the first value the chunk happened to
    // push. A block bumps scope_depth, which used to be enough to make `let`
    // allocate a local there -- so the first local of any top-level block
    // aliased whatever the chunk had already pushed. Inside a `for` loop that
    // is the iterable itself, so `let r = 7` in a loop body read the array
    // being iterated. Locals are therefore disabled outside function bodies.
    int locals_valid;
} BytecodeCompiler;

// ---------------------------------------------------------------------------
// Call signatures, for filling in default arguments at the call site.
//
// The C backend does this with its ProcEntry table: it knows each procedure's
// param_count, required_count and defaults, so it rewrites `two(1)` into
// `two(1, 99, 100)` in the generated C. The bytecode compiler had no equivalent,
// so a call that omitted a default reached the VM with fewer arguments than the
// function declared and was rejected as an arity mismatch.
//
// The VM cannot paper over it. BytecodeFunction carries only parameter *names*,
// and it is serialised into the .svm artifact, so defaults cannot be added to it
// without a format change. The VM also has no expression evaluator of its own
// for this path. Filling them in here, where the same AST is in hand, is the
// same fix the C backend already makes.
//
// The table is file-static so procedure bodies compiled via
// bytecode_compile_function_body() can see top-level signatures too: their
// compiler instance is fresh and receives only the body, not the enclosing
// program. Compilation is single-threaded, and bytecode_register_signatures()
// resets the table per program.
//
// Method calls (obj.m()) are not padded: the receiver's type is not tracked, so
// two classes may define the same method name with different signatures and
// choosing one would be a guess. Those keep failing loudly rather than silently
// binding the wrong default. Methods reached by name, and constructors, are
// handled -- see below.
#define MAX_CALL_SIGNATURES 1024

typedef struct {
    const char* name;
    int name_len;
    int param_count;
    int required_count;
    /* 1 when this signature came from a class's init, so declared parameter 0
     * is `self` and the call's arguments map to parameters 1..N rather than
     * 0..N-1. Getting this wrong pads the wrong slots: an extra NIL lands in the
     * first real parameter and every value shifts. */
    int is_ctor;
    Expr** defaults; /* Borrowed from the AST, as chunk->ast_stmts already is. */
} CallSignature;

static CallSignature g_call_signatures[MAX_CALL_SIGNATURES];
static int g_call_signature_count = 0;

static void register_signature(const Token* name, int param_count, int required_count,
                               Expr** defaults, int is_ctor) {
    if (g_call_signature_count >= MAX_CALL_SIGNATURES) {
        return;
    }
    CallSignature* sig = &g_call_signatures[g_call_signature_count++];
    sig->name = name->start;
    sig->name_len = name->length;
    sig->param_count = param_count;
    sig->required_count = required_count;
    sig->is_ctor = is_ctor;
    sig->defaults = defaults;
}

static void register_proc_signature(Stmt* stmt) {
    if (stmt == NULL) {
        return;
    }
    if (stmt->type == STMT_PROC || stmt->type == STMT_ASYNC_PROC) {
        ProcStmt* proc = (stmt->type == STMT_ASYNC_PROC) ? &stmt->as.async_proc
                                                         : &stmt->as.proc;
        register_signature(&proc->name, proc->param_count, proc->required_count,
                           proc->defaults, 0);
    } else if (stmt->type == STMT_CLASS) {
        ClassStmt* cls = &stmt->as.class_stmt;
        for (Stmt* m = cls->methods; m != NULL; m = m->next) {
            if (m->type != STMT_PROC) {
                continue;
            }
            ProcStmt* method = &m->as.proc;
            register_signature(&method->name, method->param_count,
                               method->required_count, method->defaults, 0);
            /* A bare `VFS(path)` constructs through init, so the class name needs
             * init's signature. This is what VFS.init's 18 defaulted parameters
             * were tripping over. */
            if (method->name.length == 4 && memcmp(method->name.start, "init", 4) == 0) {
                register_signature(&cls->name, method->param_count, method->required_count,
                                   method->defaults, 1);
            }
        }
    }
}

static CallSignature* find_signature(const Token* name) {
    for (int i = 0; i < g_call_signature_count; i++) {
        CallSignature* sig = &g_call_signatures[i];
        if (sig->name_len == name->length &&
            memcmp(sig->name, name->start, (size_t)name->length) == 0) {
            return sig;
        }
    }
    return NULL;
}

/* Like find_signature, but returns NULL when the name is ambiguous.
 *
 * Used for method calls: the receiver's type is not tracked, so two classes may
 * define the same method name with different signatures. Padding those would be a
 * guess, and a wrong guess binds a wrong default silently. Returning NULL leaves
 * the call alone so the VM reports the arity error. */
static CallSignature* find_unique_signature(const Token* name) {
    CallSignature* found = NULL;
    for (int i = 0; i < g_call_signature_count; i++) {
        CallSignature* sig = &g_call_signatures[i];
        if (sig->name_len == name->length &&
            memcmp(sig->name, name->start, (size_t)name->length) == 0) {
            if (found != NULL) {
                return NULL;
            }
            found = sig;
        }
    }
    return found;
}

void bytecode_register_signatures(Stmt* statements) {
    g_call_signature_count = 0;
    for (Stmt* stmt = statements; stmt != NULL; stmt = stmt->next) {
        register_proc_signature(stmt);
    }
}

static void set_error(BytecodeCompiler* compiler, const char* message) {
    if (compiler->error != NULL && compiler->error_size > 0) {
        snprintf(compiler->error, compiler->error_size, "%s", message);
    }
}

static int next_bytecode_capacity(int current, int initial, int needed) {
    if (needed < 0 || needed > INT_MAX - current) return 0;
    int capacity = current == 0 ? initial : current;
    while (capacity < needed) {
        if (capacity > INT_MAX / 2) return 0;
        capacity *= 2;
    }
    return capacity;
}

static int ensure_byte_capacity(BytecodeChunk* chunk, int needed) {
    if (chunk->code_count < 0 || chunk->code_capacity < 0 || needed < 0 ||
        chunk->code_count > INT_MAX - needed) return 0;
    if (chunk->code_count <= chunk->code_capacity - needed) return 1;

    int new_capacity = next_bytecode_capacity(chunk->code_capacity, 64, chunk->code_count + needed);
    if (new_capacity <= 0) return 0;

    chunk->code = SAGE_REALLOC(chunk->code, (size_t)new_capacity);
    chunk->lines = SAGE_REALLOC(chunk->lines, sizeof(int) * (size_t)new_capacity);
    chunk->columns = SAGE_REALLOC(chunk->columns, sizeof(int) * (size_t)new_capacity);
    chunk->code_capacity = new_capacity;
    return 1;
}

static int ensure_constant_capacity(BytecodeChunk* chunk) {
    if (chunk->constant_count < 0 || chunk->constant_capacity < 0) return 0;
    if (chunk->constant_count < chunk->constant_capacity) return 1;
    int new_capacity = next_bytecode_capacity(chunk->constant_capacity, 16, chunk->constant_count + 1);
    if (new_capacity <= 0) return 0;
    chunk->constants = SAGE_REALLOC(chunk->constants, sizeof(Value) * (size_t)new_capacity);
    chunk->constant_capacity = new_capacity;
    return 1;
}

static int ensure_ast_stmt_capacity(BytecodeChunk* chunk) {
    if (chunk->ast_stmt_count < 0 || chunk->ast_stmt_capacity < 0) return 0;
    if (chunk->ast_stmt_count < chunk->ast_stmt_capacity) return 1;
    int new_capacity = next_bytecode_capacity(chunk->ast_stmt_capacity, 8, chunk->ast_stmt_count + 1);
    if (new_capacity <= 0) return 0;
    chunk->ast_stmts = SAGE_REALLOC(chunk->ast_stmts, sizeof(Stmt*) * (size_t)new_capacity);
    chunk->ast_stmt_capacity = new_capacity;
    return 1;
}

void bytecode_chunk_init(BytecodeChunk* chunk) {
    memset(chunk, 0, sizeof(*chunk));
}

void bytecode_chunk_free(BytecodeChunk* chunk) {
    free(chunk->code);
    free(chunk->lines);
    free(chunk->columns);
    free(chunk->constants);
    free(chunk->ast_stmts);
    memset(chunk, 0, sizeof(*chunk));
}

static int emit_byte(BytecodeCompiler* compiler, uint8_t byte, int line, int column) {
    BytecodeChunk* chunk = compiler->chunk;
    if (!ensure_byte_capacity(chunk, 1)) {
        set_error(compiler, "Out of memory while writing bytecode.");
        return 0;
    }
    chunk->code[chunk->code_count] = byte;
    chunk->lines[chunk->code_count] = line;
    chunk->columns[chunk->code_count] = column;
    chunk->code_count++;
    return 1;
}

static int emit_u16(BytecodeCompiler* compiler, uint16_t value, int line, int column) {
    return emit_byte(compiler, (uint8_t)((value >> 8) & 0xff), line, column) &&
           emit_byte(compiler, (uint8_t)(value & 0xff), line, column);
}

static int emit_u8(BytecodeCompiler* compiler, uint8_t value, int line, int column) {
    return emit_byte(compiler, value, line, column);
}

static int emit_op(BytecodeCompiler* compiler, BytecodeOp op, int line, int column) {
    return emit_byte(compiler, (uint8_t)op, line, column);
}

static int add_constant(BytecodeCompiler* compiler, Value value) {
    BytecodeChunk* chunk = compiler->chunk;
    if (!ensure_constant_capacity(chunk)) {
        set_error(compiler, "Out of memory while growing constant pool.");
        return -1;
    }
    chunk->constants[chunk->constant_count] = value;
    return chunk->constant_count++;
}

static void add_local(BytecodeCompiler* compiler, Token name) {
    if (compiler->local_count >= MAX_LOCALS) {
        set_error(compiler, "Too many local variables in function.");
        return;
    }
    Local* local = &compiler->locals[compiler->local_count++];
    local->name = name;
    local->depth = compiler->scope_depth;
}

static int resolve_local(BytecodeCompiler* compiler, Token name) {
    if (!compiler->locals_valid) return -1;
    for (int i = compiler->local_count - 1; i >= 0; i--) {
        Local* local = &compiler->locals[i];
        if (local->name.length == name.length &&
            memcmp(local->name.start, name.start, name.length) == 0) {
            return i;
        }
    }
    return -1;
}

static void begin_scope(BytecodeCompiler* compiler) {
    compiler->scope_depth++;
}

static int end_scope(BytecodeCompiler* compiler) {
    compiler->scope_depth--;
    int count = 0;
    while (compiler->local_count > 0 &&
           compiler->locals[compiler->local_count - 1].depth > compiler->scope_depth) {
        compiler->local_count--;
        count++;
    }
    return count;
}

static int add_name_constant(BytecodeCompiler* compiler, const char* start, int length) {
    char* name = SAGE_ALLOC((size_t)length + 1);
    memcpy(name, start, (size_t)length);
    name[length] = '\0';
    int index = add_constant(compiler, val_string_take(name));
    if (index > 0xffff) {
        set_error(compiler, "Bytecode name pool exceeded 65535 entries.");
        return -1;
    }
    return index;
}

static int add_ast_stmt(BytecodeCompiler* compiler, Stmt* stmt) {
    BytecodeChunk* chunk = compiler->chunk;
    if (!ensure_ast_stmt_capacity(chunk)) {
        set_error(compiler, "Out of memory while storing AST fallback statements.");
        return -1;
    }
    chunk->ast_stmts[chunk->ast_stmt_count] = stmt;
    return chunk->ast_stmt_count++;
}

static int emit_constant(BytecodeCompiler* compiler, Value value, int line, int column) {
    int index = add_constant(compiler, value);
    if (index < 0) return 0;
    if (index > 0xffff) {
        set_error(compiler, "Bytecode constant pool exceeded 65535 entries.");
        return 0;
    }
    return emit_op(compiler, BC_OP_CONSTANT, line, column) &&
           emit_u16(compiler, (uint16_t)index, line, column);
}

static int emit_name_op(BytecodeCompiler* compiler, BytecodeOp op, Token token) {
    int index = add_name_constant(compiler, token.start, token.length);
    if (index < 0) return 0;
    if (index > 0xffff) {
        set_error(compiler, "Bytecode name pool exceeded 65535 entries.");
        return 0;
    }
    return emit_op(compiler, op, token.line, token.column) &&
           emit_u16(compiler, (uint16_t)index, token.line, token.column);
}

static int emit_define_function(BytecodeCompiler* compiler, Token token, int function_index) {
    int name_index = add_name_constant(compiler, token.start, token.length);
    if (name_index < 0) return 0;
    if (name_index > 0xffff || function_index > 0xffff) {
        set_error(compiler, "Bytecode function table exceeded 65535 entries.");
        return 0;
    }
    return emit_op(compiler, BC_OP_DEFINE_FUNCTION, token.line, token.column) &&
           emit_u16(compiler, (uint16_t)name_index, token.line, token.column) &&
           emit_u16(compiler, (uint16_t)function_index, token.line, token.column);
}

static int emit_create_generator(BytecodeCompiler* compiler, Token token, int function_index) {
    int name_index = add_name_constant(compiler, token.start, token.length);
    if (name_index < 0) return 0;
    if (name_index > 0xffff || function_index > 0xffff) {
        set_error(compiler, "Bytecode function table exceeded 65535 entries.");
        return 0;
    }
    return emit_op(compiler, BC_OP_CREATE_GENERATOR, token.line, token.column) &&
           emit_u16(compiler, (uint16_t)name_index, token.line, token.column) &&
           emit_u16(compiler, (uint16_t)function_index, token.line, token.column);
}

// Recursively check if a statement tree contains a yield statement
static int stmt_contains_yield(Stmt* stmt) {
    if (stmt == NULL) return 0;
    if (stmt->type == STMT_YIELD) return 1;
    switch (stmt->type) {
        case STMT_BLOCK:
            for (Stmt* s = stmt->as.block.statements; s; s = s->next) {
                if (stmt_contains_yield(s)) return 1;
            }
            return 0;
        case STMT_IF:
            return stmt_contains_yield(stmt->as.if_stmt.then_branch) ||
                   stmt_contains_yield(stmt->as.if_stmt.else_branch);
        case STMT_WHILE:
            return stmt_contains_yield(stmt->as.while_stmt.body);
        case STMT_FOR:
            return stmt_contains_yield(stmt->as.for_stmt.body);
        case STMT_TRY:
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                if (stmt_contains_yield(stmt->as.try_stmt.catches[i]->body)) return 1;
            }
            if (stmt->as.try_stmt.finally_block && stmt_contains_yield(stmt->as.try_stmt.finally_block)) return 1;
            return stmt_contains_yield(stmt->as.try_stmt.try_block);
        case STMT_PROC:
        case STMT_ASYNC_PROC:
            return 0; // Nested procs don't count
        default:
            return 0;
    }
}

static int emit_dup(BytecodeCompiler* compiler, uint8_t distance, int line, int column) {
    return emit_op(compiler, BC_OP_DUP, line, column) &&
           emit_u8(compiler, distance, line, column);
}

static int emit_ast_stmt(BytecodeCompiler* compiler, Stmt* stmt) {
    if (compiler->mode == BYTECODE_COMPILE_STRICT) {
        if (stmt->type == STMT_IMPORT) {
            set_error(compiler, "from-imports ('from module import name') are not "
                                "supported by the bytecode VM yet; use "
                                "'import module' or 'import module as name'");
            return 0;
        }
        printf("DEBUG: Unsupported stmt type %d requires AST fallback\n", stmt->type);
        set_error(compiler,
                  "Statement requires AST fallback and cannot be emitted as a compiled VM artifact yet.");
        return 0;
    }

    int index = add_ast_stmt(compiler, stmt);
    if (index < 0) return 0;
    if (index > 0xffff) {
        set_error(compiler, "Bytecode AST fallback table exceeded 65535 entries.");
        return 0;
    }
    return emit_op(compiler, BC_OP_EXEC_AST_STMT, 0, 0) &&
           emit_u16(compiler, (uint16_t)index, 0, 0);
}

static int current_offset(BytecodeCompiler* compiler) {
    return compiler->chunk->code_count;
}

static int emit_jump(BytecodeCompiler* compiler, BytecodeOp op, int line, int column) {
    if (!emit_op(compiler, op, line, column)) return -1;
    int patch_location = current_offset(compiler);
    if (!emit_u16(compiler, 0, line, column)) return -1;
    return patch_location;
}

static int patch_jump(BytecodeCompiler* compiler, int patch_location, int target) {
    if (patch_location < 0 || patch_location + 1 >= compiler->chunk->code_count) {
        set_error(compiler, "Invalid jump patch location.");
        return 0;
    }
    compiler->chunk->code[patch_location] = (uint8_t)((target >> 8) & 0xff);
    compiler->chunk->code[patch_location + 1] = (uint8_t)(target & 0xff);
    return 1;
}

static int stmt_requires_ast_fallback(BytecodeCompiler* compiler, Stmt* stmt);
static int compile_stmt(BytecodeCompiler* compiler, Stmt* stmt, int want_result);
static int compile_expr(BytecodeCompiler* compiler, Expr* expr);
static int stmt_has_pragma(Stmt* stmt, const char* name);

static int stmt_requires_ast_fallback(BytecodeCompiler* compiler, Stmt* stmt) {
    if (stmt == NULL) return 0;

    // @no_vm pragma: force AST fallback
    if (stmt_has_pragma(stmt, "no_vm")) return 1;
    // @VM pragma: compile to bytecode regardless of other considerations
    if (stmt_has_pragma(stmt, "VM")) return 0;

    switch (stmt->type) {
        case STMT_BREAK:
        case STMT_CONTINUE:
            if (compiler->loop_depth <= 0) { printf("DEBUG: break/continue outside loop\n"); return 1; }
            return 0;
        case STMT_YIELD:
            return 0;
        case STMT_RETURN:
            if (!compiler->allow_return) { printf("DEBUG: STMT_RETURN not allowed\n"); return 1; }
            return 0;
        case STMT_BLOCK: {
            for (Stmt* current = stmt->as.block.statements; current != NULL; current = current->next) {
                if (stmt_requires_ast_fallback(compiler, current)) return 1;
            }
            return 0;
        }
        case STMT_IF:
            return stmt_requires_ast_fallback(compiler, stmt->as.if_stmt.then_branch) ||
                   stmt_requires_ast_fallback(compiler, stmt->as.if_stmt.else_branch);
        case STMT_WHILE: {
            compiler->loop_depth++;
            int res = stmt_requires_ast_fallback(compiler, stmt->as.while_stmt.body);
            compiler->loop_depth--;
            return res;
        }
        case STMT_FOR: {
            compiler->loop_depth++;
            int res = stmt_requires_ast_fallback(compiler, stmt->as.for_stmt.body);
            compiler->loop_depth--;
            return res;
        }
        case STMT_TRY:
            return 0;
        case STMT_IMPORT:
            // "import module" and "import module as alias" both compile
            // natively: the emitter writes BC_OP_IMPORT and then
            // BC_OP_DEFINE_GLOBAL naming the alias, or the last dotted segment
            // when there is no alias. Rejecting the aliased form here was what
            // made `import os as o` fail even though the emitter could already
            // produce it.
            //
            // Only from-imports ("from module import a, b") need the richer
            // per-item binding logic in interpreter.c. They must stay a hard
            // error rather than a fallback: the walker is addressed by pointer
            // into the live AST (vm.c reads chunk->ast_stmts[...]), and that
            // table is not written into a .sgvm/.svm artifact, so a fallback
            // opcode in a file would be unrunnable. A clear compile error
            // beats a silently broken artifact.
            return stmt->as.import.import_all ? 0 : 1;
        case STMT_CLASS:
        case STMT_PROC:
            return compiler->build_function == NULL;
        case STMT_ASYNC_PROC:
            return 1;
        default:
            return 0;
    }
}

static int compile_short_circuit(BytecodeCompiler* compiler, BinaryExpr* binary) {
    if (!compile_expr(compiler, binary->left)) return 0;

    if (binary->op.type == TOKEN_OR) {
        int jump_false = emit_jump(compiler, BC_OP_JUMP_IF_FALSE, binary->op.line, binary->op.column);
        if (jump_false < 0) return 0;
        if (!emit_op(compiler, BC_OP_POP, binary->op.line, binary->op.column)) return 0;
        if (!emit_op(compiler, BC_OP_TRUE, binary->op.line, binary->op.column)) return 0;
        int end_jump = emit_jump(compiler, BC_OP_JUMP, binary->op.line, binary->op.column);
        if (end_jump < 0) return 0;
        if (!patch_jump(compiler, jump_false, current_offset(compiler))) return 0;
        if (!emit_op(compiler, BC_OP_POP, binary->op.line, binary->op.column)) return 0;
        if (!compile_expr(compiler, binary->right)) return 0;
        if (!emit_op(compiler, BC_OP_TRUTHY, binary->op.line, binary->op.column)) return 0;
        return patch_jump(compiler, end_jump, current_offset(compiler));
    }

    int jump_false = emit_jump(compiler, BC_OP_JUMP_IF_FALSE, binary->op.line, binary->op.column);
    if (jump_false < 0) return 0;
    if (!emit_op(compiler, BC_OP_POP, binary->op.line, binary->op.column)) return 0;
    if (!compile_expr(compiler, binary->right)) return 0;
    if (!emit_op(compiler, BC_OP_TRUTHY, binary->op.line, binary->op.column)) return 0;
    int end_jump = emit_jump(compiler, BC_OP_JUMP, binary->op.line, binary->op.column);
    if (end_jump < 0) return 0;
    if (!patch_jump(compiler, jump_false, current_offset(compiler))) return 0;
    if (!emit_op(compiler, BC_OP_POP, binary->op.line, binary->op.column)) return 0;
    if (!emit_op(compiler, BC_OP_FALSE, binary->op.line, binary->op.column)) return 0;
    return patch_jump(compiler, end_jump, current_offset(compiler));
}

static int compile_expr(BytecodeCompiler* compiler, Expr* expr) {
    if (expr == NULL) {
        return emit_op(compiler, BC_OP_NIL, 0, 0);
    }

    switch (expr->type) {
        case EXPR_NUMBER:
            return emit_constant(compiler, val_number(expr->as.number.value), 0, 0);
        case EXPR_STRING:
            return emit_constant(compiler, val_string(expr->as.string.value), 0, 0);
        case EXPR_BOOL:
            return emit_op(compiler, expr->as.boolean.value ? BC_OP_TRUE : BC_OP_FALSE, 0, 0);
        case EXPR_NIL:
            return emit_op(compiler, BC_OP_NIL, 0, 0);
        case EXPR_VARIABLE: {
            int arg = resolve_local(compiler, expr->as.variable.name);
            if (arg != -1) {
                return emit_op(compiler, BC_OP_GET_LOCAL, 0, 0) &&
                       emit_u16(compiler, (uint16_t)arg, 0, 0);
            }
            return emit_name_op(compiler, BC_OP_GET_GLOBAL, expr->as.variable.name);
        }
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                if (!compile_expr(compiler, expr->as.array.elements[i])) return 0;
            }
            return emit_op(compiler, BC_OP_ARRAY, 0, 0) &&
                   emit_u16(compiler, (uint16_t)expr->as.array.count, 0, 0);
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                if (!compile_expr(compiler, expr->as.tuple.elements[i])) return 0;
            }
            return emit_op(compiler, BC_OP_TUPLE, 0, 0) &&
                   emit_u16(compiler, (uint16_t)expr->as.tuple.count, 0, 0);
        case EXPR_PROC:
            set_error(compiler, "inline procedures are not compiled to bytecode yet.");
            return 0;
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                if (!emit_constant(compiler, val_string(expr->as.dict.keys[i]), 0, 0)) return 0;
                if (!compile_expr(compiler, expr->as.dict.values[i])) return 0;
            }
            return emit_op(compiler, BC_OP_DICT, 0, 0) &&
                   emit_u16(compiler, (uint16_t)expr->as.dict.count, 0, 0);
        case EXPR_INDEX:
            return compile_expr(compiler, expr->as.index.array) &&
                   compile_expr(compiler, expr->as.index.index) &&
                   emit_op(compiler, BC_OP_GET_INDEX, 0, 0);
        case EXPR_INDEX_SET:
            return compile_expr(compiler, expr->as.index_set.array) &&
                   compile_expr(compiler, expr->as.index_set.index) &&
                   compile_expr(compiler, expr->as.index_set.value) &&
                   emit_op(compiler, BC_OP_SET_INDEX, 0, 0);
        case EXPR_SLICE:
            if (!compile_expr(compiler, expr->as.slice.array)) return 0;
            if (expr->as.slice.start != NULL) {
                if (!compile_expr(compiler, expr->as.slice.start)) return 0;
            } else if (!emit_op(compiler, BC_OP_NIL, 0, 0)) {
                return 0;
            }
            if (expr->as.slice.end != NULL) {
                if (!compile_expr(compiler, expr->as.slice.end)) return 0;
            } else if (!emit_op(compiler, BC_OP_NIL, 0, 0)) {
                return 0;
            }
            return emit_op(compiler, BC_OP_SLICE, 0, 0);
        case EXPR_GET:
            return compile_expr(compiler, expr->as.get.object) &&
                   emit_name_op(compiler, BC_OP_GET_PROPERTY, expr->as.get.property);
        case EXPR_SET:
            if (expr->as.set.object == NULL) {
                if (!compile_expr(compiler, expr->as.set.value)) return 0;
                int arg = resolve_local(compiler, expr->as.set.property);
                if (arg != -1) {
                    return emit_op(compiler, BC_OP_SET_LOCAL, 0, 0) &&
                           emit_u16(compiler, (uint16_t)arg, 0, 0);
                }
                return emit_name_op(compiler, BC_OP_SET_GLOBAL, expr->as.set.property);
            }
            return compile_expr(compiler, expr->as.set.object) &&
                   compile_expr(compiler, expr->as.set.value) &&
                   emit_name_op(compiler, BC_OP_SET_PROPERTY, expr->as.set.property);
        case EXPR_CALL: {
            if (expr->as.call.callee->type == EXPR_GET) {
                GetExpr* get = &expr->as.call.callee->as.get;
                if (!compile_expr(compiler, get->object)) return 0;
                for (int i = 0; i < expr->as.call.arg_count; i++) {
                    if (!compile_expr(compiler, expr->as.call.args[i])) return 0;
                }
                /* Pad a method call's omitted defaults, but only when exactly one
                 * class defines that method name -- see find_unique_signature.
                 *
                 * Declared parameter 0 is `self`, which the receiver supplies, so
                 * the caller's N arguments fill declared parameters 1..N and the
                 * remaining defaults are for N+1..param_count-1. They are emitted
                 * after the real arguments because the stack is
                 * [object, arg0, arg1, ...] and CALL_METHOD reads the arguments
                 * from the top. */
                int method_args = expr->as.call.arg_count;
                CallSignature* msig = find_unique_signature(&get->property);
                if (msig != NULL && method_args < msig->param_count - 1 &&
                    method_args + 1 >= msig->required_count) {
                    for (int i = method_args + 1; i < msig->param_count; i++) {
                        Expr* def = (msig->defaults != NULL) ? msig->defaults[i] : NULL;
                        if (def == NULL) {
                            if (!emit_op(compiler, BC_OP_NIL, 0, 0)) return 0;
                        } else if (!compile_expr(compiler, def)) {
                            return 0;
                        }
                    }
                    method_args = msig->param_count - 1;
                }
                int name_index = add_name_constant(compiler, get->property.start, get->property.length);
                if (name_index < 0) return 0;
                if (name_index > 0xffff || method_args > 0xff) {
                    set_error(compiler, "Method call operand limit exceeded.");
                    return 0;
                }
                return emit_op(compiler, BC_OP_CALL_METHOD, get->property.line, get->property.column) &&
                       emit_u16(compiler, (uint16_t)name_index, get->property.line, get->property.column) &&
                       emit_u8(compiler, (uint8_t)method_args, get->property.line, get->property.column);
            }

            if (!compile_expr(compiler, expr->as.call.callee)) return 0;
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                if (!compile_expr(compiler, expr->as.call.args[i])) return 0;
            }

            /* Fill in omitted default arguments.
             *
             * `two(1)` must reach the VM as `two(1, 99, 100)`: it checks
             * arg_count against the declared param_count and rejects a mismatch.
             * The C backend substitutes defaults here for the same reason.
             *
             * A call passing fewer arguments than required_count is left alone,
             * so the VM still reports the arity error rather than binding nil to
             * a parameter the caller was obliged to supply. */
            int emit_count = expr->as.call.arg_count;
            if (expr->as.call.callee->type == EXPR_VARIABLE) {
                CallSignature* sig = find_signature(&expr->as.call.callee->as.variable.name);
                if (sig != NULL) {
                    /* A constructor's parameter 0 is `self`, supplied implicitly,
                     * so the call's arguments occupy parameters 1..N. A plain
                     * function's occupy 0..N-1. */
                    int base = sig->is_ctor ? 1 : 0;
                    int last_arg_param = base + emit_count;
                    if (emit_count + base < sig->param_count &&
                        last_arg_param >= sig->required_count) {
                        for (int i = last_arg_param; i < sig->param_count; i++) {
                            Expr* def = (sig->defaults != NULL) ? sig->defaults[i] : NULL;
                            if (def == NULL) {
                                if (!emit_op(compiler, BC_OP_NIL, 0, 0)) return 0;
                            } else if (!compile_expr(compiler, def)) {
                                return 0;
                            }
                        }
                        emit_count = sig->param_count - base;
                    }
                }
            }

            if (emit_count > 0xff) {
                set_error(compiler, "Call argument count exceeded 255.");
                return 0;
            }
            return emit_op(compiler, BC_OP_CALL, 0, 0) &&
                   emit_u8(compiler, (uint8_t)emit_count, 0, 0);
        }
        case EXPR_BINARY: {
            BinaryExpr* binary = &expr->as.binary;
            if (binary->op.type == TOKEN_OR || binary->op.type == TOKEN_AND) {
                return compile_short_circuit(compiler, binary);
            }

            if (!compile_expr(compiler, binary->left)) return 0;

            if (binary->op.type == TOKEN_NOT) {
                return emit_op(compiler, BC_OP_NOT, binary->op.line, binary->op.column);
            }
            if (binary->op.type == TOKEN_TILDE) {
                return emit_op(compiler, BC_OP_BIT_NOT, binary->op.line, binary->op.column);
            }

            if (binary->right == NULL) {
                set_error(compiler, "Unsupported unary bytecode expression.");
                return 0;
            }

            if (!compile_expr(compiler, binary->right)) return 0;

            switch (binary->op.type) {
                case TOKEN_PLUS: return emit_op(compiler, BC_OP_ADD, binary->op.line, binary->op.column);
                case TOKEN_MINUS: return emit_op(compiler, BC_OP_SUB, binary->op.line, binary->op.column);
                case TOKEN_STAR: return emit_op(compiler, BC_OP_MUL, binary->op.line, binary->op.column);
                case TOKEN_SLASH: return emit_op(compiler, BC_OP_DIV, binary->op.line, binary->op.column);
                case TOKEN_PERCENT: return emit_op(compiler, BC_OP_MOD, binary->op.line, binary->op.column);
                case TOKEN_EQ: return emit_op(compiler, BC_OP_EQUAL, binary->op.line, binary->op.column);
                case TOKEN_NEQ: return emit_op(compiler, BC_OP_NOT_EQUAL, binary->op.line, binary->op.column);
                case TOKEN_GT: return emit_op(compiler, BC_OP_GREATER, binary->op.line, binary->op.column);
                case TOKEN_GTE: return emit_op(compiler, BC_OP_GREATER_EQUAL, binary->op.line, binary->op.column);
                case TOKEN_LT: return emit_op(compiler, BC_OP_LESS, binary->op.line, binary->op.column);
                case TOKEN_LTE: return emit_op(compiler, BC_OP_LESS_EQUAL, binary->op.line, binary->op.column);
                case TOKEN_AMP: return emit_op(compiler, BC_OP_BIT_AND, binary->op.line, binary->op.column);
                case TOKEN_PIPE: return emit_op(compiler, BC_OP_BIT_OR, binary->op.line, binary->op.column);
                case TOKEN_CARET: return emit_op(compiler, BC_OP_BIT_XOR, binary->op.line, binary->op.column);
                case TOKEN_LSHIFT: return emit_op(compiler, BC_OP_SHIFT_LEFT, binary->op.line, binary->op.column);
                case TOKEN_RSHIFT: return emit_op(compiler, BC_OP_SHIFT_RIGHT, binary->op.line, binary->op.column);
                default:
                    set_error(compiler, "Unsupported binary expression in bytecode mode.");
                    return 0;
            }
        }
        case EXPR_AWAIT:
            set_error(compiler, "await expressions are not compiled to bytecode yet.");
            return 0;
        case EXPR_SUPER:
            set_error(compiler, "super expressions are not compiled to bytecode yet.");
            return 0;
        case EXPR_COMPTIME:
            return compile_expr(compiler, expr->as.comptime.expression);
    }

    set_error(compiler, "Unsupported expression in bytecode mode.");
    return 0;
}

static int push_loop(BytecodeCompiler* compiler, int continue_target, int is_for, int for_pop_count, int local_count_at_entry) {
    if (compiler->loop_depth >= MAX_LOOP_DEPTH) {
        set_error(compiler, "Loop nesting depth exceeded.");
        return 0;
    }
    LoopContext* loop = &compiler->loops[compiler->loop_depth++];
    loop->break_count = 0;
    loop->continue_target = continue_target;
    loop->has_for_cleanup = is_for;
    loop->for_pop_count = for_pop_count;
    loop->local_count_at_entry = local_count_at_entry;
    return 1;
}

static int pop_loop_and_patch_breaks(BytecodeCompiler* compiler) {
    if (compiler->loop_depth <= 0) {
        set_error(compiler, "No loop to pop.");
        return 0;
    }
    compiler->loop_depth--;
    LoopContext* loop = &compiler->loops[compiler->loop_depth];
    int target = current_offset(compiler);
    for (int i = 0; i < loop->break_count; i++) {
        if (!patch_jump(compiler, loop->break_patches[i], target)) return 0;
    }
    return 1;
}

static int compile_block(BytecodeCompiler* compiler, Stmt* stmt) {
    begin_scope(compiler);
    for (Stmt* current = stmt->as.block.statements; current != NULL; current = current->next) {
        if (!compile_stmt(compiler, current, 0)) return 0;
    }
    int pops = end_scope(compiler);
    for (int i = 0; i < pops; i++) {
        if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
    }
    return 1;
}

static int emit_load_function(BytecodeCompiler* compiler, int function_index) {
    return emit_op(compiler, BC_OP_LOAD_FUNCTION, 0, 0) &&
           emit_u16(compiler, (uint16_t)function_index, 0, 0);
}

// Check if a statement has a specific pragma
static int stmt_has_pragma(Stmt* stmt, const char* name) {
    if (!stmt || !stmt->pragmas) return 0;
    for (Pragma* p = stmt->pragmas; p; p = p->next) {
        if (strcmp(p->name, name) == 0) return 1;
    }
    return 0;
}

static int compile_stmt(BytecodeCompiler* compiler, Stmt* stmt, int want_result) {
    if (stmt == NULL) {
        if (want_result) {
            return emit_op(compiler, BC_OP_NIL, 0, 0);
        }
        return 1;
    }

    // @no_vm: skip bytecode compilation entirely (forces AST fallback)
    if (stmt_has_pragma(stmt, "no_vm")) {
        if (!emit_ast_stmt(compiler, stmt)) return 0;
        if (!want_result) {
            return emit_op(compiler, BC_OP_POP, 0, 0);
        }
        return 1;
    }

    if (stmt_requires_ast_fallback(compiler, stmt)) {
        if (!emit_ast_stmt(compiler, stmt)) return 0;
        if (!want_result) {
            return emit_op(compiler, BC_OP_POP, 0, 0);
        }
        return 1;
    }

    switch (stmt->type) {
        case STMT_PRINT:
            if (!compile_expr(compiler, stmt->as.print.expression)) break;
            if (!emit_op(compiler, BC_OP_PRINT, 0, 0)) return 0;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        case STMT_LET:
            if (stmt->as.let.initializer != NULL) {
                if (!compile_expr(compiler, stmt->as.let.initializer)) break;
            } else if (!emit_op(compiler, BC_OP_NIL, 0, 0)) {
                return 0;
            }
            if (compiler->locals_valid && compiler->scope_depth > 0) {
                add_local(compiler, stmt->as.let.name);
                // The value is already on top of the stack from compile_expr
                if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
                return 1;
            }
            if (!emit_name_op(compiler, BC_OP_DEFINE_GLOBAL, stmt->as.let.name)) return 0;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        case STMT_PROC: {
            int function_index = -1;
            if (compiler->build_function == NULL) break;
            if (!compiler->build_function(compiler->build_function_data, &stmt->as.proc,
                                          compiler->error, compiler->error_size, &function_index)) {
                return 0;
            }
            int is_generator = stmt_contains_yield((Stmt*)stmt->as.proc.body);
            if (is_generator) {
                if (!emit_create_generator(compiler, stmt->as.proc.name, function_index)) return 0;
            } else {
                if (!emit_define_function(compiler, stmt->as.proc.name, function_index)) return 0;
            }
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_EXPRESSION:
            if (!compile_expr(compiler, stmt->as.expression)) break;
            if (!want_result) return emit_op(compiler, BC_OP_POP, 0, 0);
            return 1;
        case STMT_BLOCK:
            if (!compile_block(compiler, stmt)) break;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        case STMT_IF: {
            if (!compile_expr(compiler, stmt->as.if_stmt.condition)) break;
            int else_jump = emit_jump(compiler, BC_OP_JUMP_IF_FALSE, 0, 0);
            if (else_jump < 0) return 0;
            if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
            if (!compile_stmt(compiler, stmt->as.if_stmt.then_branch, 0)) return 0;
            int end_jump = emit_jump(compiler, BC_OP_JUMP, 0, 0);
            if (end_jump < 0) return 0;
            if (!patch_jump(compiler, else_jump, current_offset(compiler))) return 0;
            if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
            if (stmt->as.if_stmt.else_branch != NULL) {
                if (!compile_stmt(compiler, stmt->as.if_stmt.else_branch, 0)) return 0;
            }
            if (!patch_jump(compiler, end_jump, current_offset(compiler))) return 0;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_WHILE: {
            int loop_start = current_offset(compiler);
            if (!compile_expr(compiler, stmt->as.while_stmt.condition)) break;
            int exit_jump = emit_jump(compiler, BC_OP_JUMP_IF_FALSE, 0, 0);
            if (exit_jump < 0) return 0;
            if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
            if (!push_loop(compiler, loop_start, 0, 0, compiler->local_count)) return 0;
            if (!compile_stmt(compiler, stmt->as.while_stmt.body, 0)) {
                compiler->loop_depth--;
                return 0;
            }
            if (!emit_op(compiler, BC_OP_JUMP, 0, 0)) return 0;
            if (!emit_u16(compiler, (uint16_t)loop_start, 0, 0)) return 0;
            if (!pop_loop_and_patch_breaks(compiler)) return 0;
            if (!patch_jump(compiler, exit_jump, current_offset(compiler))) return 0;
            if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_FOR: {
            Token loop_var = stmt->as.for_stmt.variable;

            if (!compile_expr(compiler, stmt->as.for_stmt.iterable)) break;
            if (!emit_op(compiler, BC_OP_PUSH_ENV, loop_var.line, loop_var.column)) return 0;
            if (!emit_constant(compiler, val_number(0), loop_var.line, loop_var.column)) return 0;

            int loop_start = current_offset(compiler);

            if (!emit_dup(compiler, 0, loop_var.line, loop_var.column) ||
                !emit_dup(compiler, 2, loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_ARRAY_LEN, loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_LESS, loop_var.line, loop_var.column)) {
                return 0;
            }
            int exit_jump = emit_jump(compiler, BC_OP_JUMP_IF_FALSE, loop_var.line, loop_var.column);
            if (exit_jump < 0) return 0;

            // Pop the condition result so the stack is just [array, index]
            if (!emit_op(compiler, BC_OP_POP, loop_var.line, loop_var.column)) return 0;

            if (!emit_dup(compiler, 1, loop_var.line, loop_var.column) ||
                !emit_dup(compiler, 1, loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_GET_INDEX, loop_var.line, loop_var.column)) {
                return 0;
            }
            if (compiler->locals_valid && compiler->scope_depth > 0) {
                add_local(compiler, loop_var);
            } else {
                if (!emit_name_op(compiler, BC_OP_DEFINE_GLOBAL, loop_var)) return 0;
            }

            // continue_target points to the increment section
            int continue_target_placeholder = current_offset(compiler);
            // for-loop break needs: pop index, pop array, pop_env
            // If local scope, we also need to account for the local variable
            int extra_pops = (compiler->locals_valid && compiler->scope_depth > 0) ? 3 : 2;
            if (!push_loop(compiler, continue_target_placeholder, 1, extra_pops, compiler->local_count)) return 0;

            if (!compile_stmt(compiler, stmt->as.for_stmt.body, 0)) {
                compiler->loop_depth--;
                return 0;
            }

            // If we added a local, we must pop it before the next iteration
            if (compiler->locals_valid && compiler->scope_depth > 0) {
                if (!emit_op(compiler, BC_OP_POP, loop_var.line, loop_var.column)) return 0;
                compiler->local_count--; // Remove from local tracking for this iteration
            }

            // Patch continue target to the increment section (right here)
            compiler->loops[compiler->loop_depth - 1].continue_target = current_offset(compiler);

            if (!emit_constant(compiler, val_number(1), loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_ADD, loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_JUMP, loop_var.line, loop_var.column) ||
                !emit_u16(compiler, (uint16_t)loop_start, loop_var.line, loop_var.column)) {
                compiler->loop_depth--;
                return 0;
            }

            if (!patch_jump(compiler, exit_jump, current_offset(compiler)) ||
                !emit_op(compiler, BC_OP_POP, loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_POP, loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_POP, loop_var.line, loop_var.column) ||
                !emit_op(compiler, BC_OP_POP_ENV, loop_var.line, loop_var.column)) {
                return 0;
            }

            if (!pop_loop_and_patch_breaks(compiler)) return 0;

            if (want_result) return emit_op(compiler, BC_OP_NIL, loop_var.line, loop_var.column);
            return 1;
        }
        case STMT_BREAK: {
            if (compiler->loop_depth <= 0) break;  // fall to AST fallback
            LoopContext* loop = &compiler->loops[compiler->loop_depth - 1];
            int body_pops = compiler->local_count - loop->local_count_at_entry;
            if (body_pops < 0) {
                set_error(compiler, "Invalid local scope while compiling loop control.");
                return 0;
            }
            for (int i = 0; i < body_pops; i++) {
                if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
            }
            if (!loop->has_for_cleanup) {
                if (!emit_op(compiler, BC_OP_NIL, 0, 0)) return 0;
            }
            // For-loops need to clean up stack: pop index, pop array, and pop env
            if (loop->has_for_cleanup) {
                for (int i = 0; i < loop->for_pop_count; i++) {
                    if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
                }
                if (!emit_op(compiler, BC_OP_POP_ENV, 0, 0)) return 0;
            }
            if (loop->break_count >= MAX_BREAK_PATCHES) {
                set_error(compiler, "Too many break statements in loop.");
                return 0;
            }
            int jump_loc = emit_jump(compiler, BC_OP_JUMP, 0, 0);
            if (jump_loc < 0) return 0;
            loop->break_patches[loop->break_count++] = jump_loc;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_CONTINUE: {
            if (compiler->loop_depth <= 0) break;  // fall to AST fallback
            LoopContext* loop = &compiler->loops[compiler->loop_depth - 1];
            int body_pops = compiler->local_count - loop->local_count_at_entry;
            if (body_pops < 0) {
                set_error(compiler, "Invalid local scope while compiling loop control.");
                return 0;
            }
            for (int i = 0; i < body_pops; i++) {
                if (!emit_op(compiler, BC_OP_POP, 0, 0)) return 0;
            }
            if (!emit_op(compiler, BC_OP_JUMP, 0, 0)) return 0;
            if (!emit_u16(compiler, (uint16_t)loop->continue_target, 0, 0)) return 0;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_IMPORT: {
            Token name_token = {0};
            name_token.start = stmt->as.import.module_name;
            name_token.length = (int)strlen(stmt->as.import.module_name);
            if (!emit_name_op(compiler, BC_OP_IMPORT, name_token)) return 0;

            const char* bind_name = stmt->as.import.alias;
            if (bind_name == NULL) {
                const char* dot = strrchr(stmt->as.import.module_name, '.');
                bind_name = dot ? dot + 1 : stmt->as.import.module_name;
            }
            Token bind_token = {0};
            bind_token.start = bind_name;
            bind_token.length = (int)strlen(bind_name);
            if (!emit_name_op(compiler, BC_OP_DEFINE_GLOBAL, bind_token)) return 0;

            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_TRY: {
            int handler_jump = emit_jump(compiler, BC_OP_SETUP_TRY, 0, 0);
            if (handler_jump < 0) return 0;
            if (!compile_stmt(compiler, stmt->as.try_stmt.try_block, 0)) return 0;
            if (!emit_op(compiler, BC_OP_END_TRY, 0, 0)) return 0;
            int end_jump = emit_jump(compiler, BC_OP_JUMP, 0, 0);
            if (end_jump < 0) return 0;
            if (!patch_jump(compiler, handler_jump, current_offset(compiler))) return 0;
            if (stmt->as.try_stmt.catch_count > 0) {
                CatchClause* catch_clause = stmt->as.try_stmt.catches[0];
                if (!emit_op(compiler, BC_OP_PUSH_ENV, 0, 0)) return 0;
                if (!emit_name_op(compiler, BC_OP_DEFINE_GLOBAL, catch_clause->exception_var)) return 0;
                if (!compile_stmt(compiler, catch_clause->body, 0)) return 0;
                if (!emit_op(compiler, BC_OP_POP_ENV, 0, 0)) return 0;
            } else {
                if (!emit_op(compiler, BC_OP_RAISE, 0, 0)) return 0;
            }
            if (!patch_jump(compiler, end_jump, current_offset(compiler))) return 0;
            if (stmt->as.try_stmt.finally_block != NULL) {
                if (!compile_stmt(compiler, stmt->as.try_stmt.finally_block, 0)) return 0;
            }
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_RAISE: {
            if (!compile_expr(compiler, stmt->as.raise.exception)) return 0;
            if (!emit_op(compiler, BC_OP_RAISE, 0, 0)) return 0;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_CLASS: {
            if (stmt->as.class_stmt.has_parent) {
                if (!emit_name_op(compiler, BC_OP_GET_GLOBAL, stmt->as.class_stmt.parent)) return 0;
            }
            if (!emit_name_op(compiler, BC_OP_CLASS, stmt->as.class_stmt.name)) return 0;
            if (stmt->as.class_stmt.has_parent) {
                if (!emit_op(compiler, BC_OP_INHERIT, 0, 0)) return 0;
            }
            Stmt* method = stmt->as.class_stmt.methods;
            while (method != NULL) {
                if (method->type == STMT_PROC) {
                    int function_index = -1;
                    if (compiler->build_function != NULL) {
                        if (!compiler->build_function(compiler->build_function_data, &method->as.proc,
                                                      compiler->error, compiler->error_size, &function_index)) {
                            return 0;
                        }
                        if (!emit_load_function(compiler, function_index)) return 0;
                        if (!emit_name_op(compiler, BC_OP_METHOD, method->as.proc.name)) return 0;
                    }
                }
                method = method->next;
            }
            if (!emit_name_op(compiler, BC_OP_DEFINE_GLOBAL, stmt->as.class_stmt.name)) return 0;
            if (want_result) return emit_op(compiler, BC_OP_NIL, 0, 0);
            return 1;
        }
        case STMT_RETURN:
            if (!compiler->allow_return) break;
            if (stmt->as.ret.value != NULL) {
                if (!compile_expr(compiler, stmt->as.ret.value)) return 0;
            } else if (!emit_op(compiler, BC_OP_NIL, 0, 0)) {
                return 0;
            }
            return emit_op(compiler, BC_OP_RETURN, 0, 0);
        case STMT_YIELD:
            if (stmt->as.yield_stmt.value != NULL) {
                if (!compile_expr(compiler, stmt->as.yield_stmt.value)) return 0;
            } else if (!emit_op(compiler, BC_OP_NIL, 0, 0)) {
                return 0;
            }
            return emit_op(compiler, BC_OP_YIELD, 0, 0);
        default:
            break;
    }

    if (!emit_ast_stmt(compiler, stmt)) return 0;
    if (!want_result) {
        return emit_op(compiler, BC_OP_POP, 0, 0);
    }
    return 1;
}

int bytecode_compile_statement(BytecodeChunk* chunk, Stmt* stmt, char* error, size_t error_size) {
    return bytecode_compile_statement_mode(chunk, stmt, BYTECODE_COMPILE_HYBRID, error, error_size);
}

int bytecode_compile_statement_mode(BytecodeChunk* chunk, Stmt* stmt, BytecodeCompileMode mode,
                                    char* error, size_t error_size) {
    return bytecode_compile_statement_with_functions(chunk, stmt, mode, NULL, NULL, error, error_size);
}

int bytecode_compile_statement_with_functions(BytecodeChunk* chunk, Stmt* stmt, BytecodeCompileMode mode,
                                              BytecodeBuildFunctionFn build_function,
                                              void* build_function_data,
                                              char* error, size_t error_size) {
    gc_pin();
    BytecodeCompiler compiler;
    memset(&compiler, 0, sizeof(compiler));
    compiler.chunk = chunk;
    compiler.mode = mode;
    compiler.build_function = build_function;
    compiler.build_function_data = build_function_data;
    compiler.allow_return = 0;
    compiler.error = error;
    compiler.error_size = error_size;
    if (error != NULL && error_size > 0) {
        error[0] = '\0';
    }

    int success = compile_stmt(&compiler, stmt, 1);
    if (!success) {
        if (error != NULL && error[0] == '\0') {
            snprintf(error, error_size, "failed to compile statement");
        }
    } else {
        success = emit_op(&compiler, BC_OP_RETURN, 0, 0);
    }
    gc_unpin();
    return success;
}

int bytecode_compile_function_body(BytecodeChunk* chunk, Stmt* body,
                                   char** params, int param_count,
                                   BytecodeBuildFunctionFn build_function,
                                   void* build_function_data,
                                   char* error, size_t error_size) {
    BytecodeCompiler compiler;
    memset(&compiler, 0, sizeof(compiler));
    compiler.chunk = chunk;
    compiler.mode = BYTECODE_COMPILE_STRICT;
    compiler.build_function = build_function;
    compiler.build_function_data = build_function_data;
    compiler.allow_return = 1;
    compiler.error = error;
    compiler.error_size = error_size;
    compiler.locals_valid = 1; // Only function bodies have a meaningful slot base
    compiler.scope_depth = 1; // Parameters and body are in local scope
    if (error != NULL && error_size > 0) {
        error[0] = '\0';
    }

    // Register parameters as locals
    for (int i = 0; i < param_count; i++) {
        Token t = {0};
        t.start = params[i];
        t.length = (int)strlen(params[i]);
        t.line = 0;
        t.column = 0;
        add_local(&compiler, t);
    }

    if (!compile_stmt(&compiler, body, 0)) {
        if (error != NULL && error_size > 0 && error[0] == '\0') {
            snprintf(error, error_size, "failed to compile function body");
        }
        return 0;
    }

    if (!emit_op(&compiler, BC_OP_NIL, 0, 0) ||
        !emit_op(&compiler, BC_OP_RETURN, 0, 0)) {
        return 0;
    }
    return 1;
}
