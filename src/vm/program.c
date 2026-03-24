#include "program.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#include "gc.h"
#include "lexer.h"
#include "parser.h"
#include "pass.h"

static void set_program_error(char* error, size_t error_size, const char* message) {
    if (error != NULL && error_size > 0) {
        snprintf(error, error_size, "%s", message);
    }
}

static char* dup_text(const char* text, size_t length) {
    char* copy = SAGE_ALLOC(length + 1);
    memcpy(copy, text, length);
    copy[length] = '\0';
    return copy;
}

static int ensure_chunk_capacity(BytecodeProgram* program) {
    if (program->chunk_count < program->chunk_capacity) {
        return 1;
    }

    int new_capacity = program->chunk_capacity == 0 ? 8 : program->chunk_capacity * 2;
    program->chunks = SAGE_REALLOC(program->chunks, sizeof(BytecodeChunk) * (size_t)new_capacity);
    program->chunk_capacity = new_capacity;
    return 1;
}

static int ensure_function_capacity(BytecodeProgram* program) {
    if (program->function_count < program->function_capacity) {
        return 1;
    }

    int new_capacity = program->function_capacity == 0 ? 8 : program->function_capacity * 2;
    program->functions = SAGE_REALLOC(program->functions, sizeof(BytecodeFunction) * (size_t)new_capacity);
    program->function_capacity = new_capacity;
    return 1;
}

static int ensure_constant_capacity(BytecodeChunk* chunk, int needed) {
    if (chunk->constant_count + needed <= chunk->constant_capacity) {
        return 1;
    }

    int new_capacity = chunk->constant_capacity == 0 ? 16 : chunk->constant_capacity * 2;
    while (new_capacity < chunk->constant_count + needed) {
        new_capacity *= 2;
    }

    chunk->constants = SAGE_REALLOC(chunk->constants, sizeof(Value) * (size_t)new_capacity);
    chunk->constant_capacity = new_capacity;
    return 1;
}

static int ensure_code_capacity(BytecodeChunk* chunk, int needed) {
    if (chunk->code_count + needed <= chunk->code_capacity) {
        return 1;
    }

    int new_capacity = chunk->code_capacity == 0 ? 64 : chunk->code_capacity * 2;
    while (new_capacity < chunk->code_count + needed) {
        new_capacity *= 2;
    }

    uint8_t* new_code = SAGE_ALLOC((size_t)new_capacity);
    int* new_lines = SAGE_ALLOC(sizeof(int) * (size_t)new_capacity);
    int* new_columns = SAGE_ALLOC(sizeof(int) * (size_t)new_capacity);

    if (chunk->code_count > 0) {
        memcpy(new_code, chunk->code, (size_t)chunk->code_count);
        memcpy(new_lines, chunk->lines, sizeof(int) * (size_t)chunk->code_count);
        memcpy(new_columns, chunk->columns, sizeof(int) * (size_t)chunk->code_count);
    }

    free(chunk->code);
    free(chunk->lines);
    free(chunk->columns);

    chunk->code = new_code;
    chunk->lines = new_lines;
    chunk->columns = new_columns;
    chunk->code_capacity = new_capacity;
    return 1;
}

static int append_constant(BytecodeChunk* chunk, Value value) {
    if (!ensure_constant_capacity(chunk, 1)) {
        return 0;
    }
    chunk->constants[chunk->constant_count++] = value;
    return 1;
}

static int append_chunk(BytecodeProgram* program, BytecodeChunk* chunk, char* error, size_t error_size) {
    if (!ensure_chunk_capacity(program)) {
        set_program_error(error, error_size, "Out of memory while storing compiled VM chunks.");
        return 0;
    }

    chunk->program = program;
    program->chunks[program->chunk_count++] = *chunk;
    memset(chunk, 0, sizeof(*chunk));
    return 1;
}

static int compile_program_function(void* data, ProcStmt* proc, char* error, size_t error_size,
                                    int* function_index_out);

static int append_function(BytecodeProgram* program, BytecodeFunction* function, char* error,
                           size_t error_size, int* function_index_out) {
    if (!ensure_function_capacity(program)) {
        set_program_error(error, error_size, "Out of memory while storing compiled VM functions.");
        return 0;
    }

    function->chunk.program = program;
    program->functions[program->function_count] = *function;
    if (function_index_out != NULL) {
        *function_index_out = program->function_count;
    }
    program->function_count++;
    memset(function, 0, sizeof(*function));
    return 1;
}

static int compile_program_function(void* data, ProcStmt* proc, char* error, size_t error_size,
                                    int* function_index_out) {
    BytecodeProgram* program = data;
    BytecodeFunction function;

    memset(&function, 0, sizeof(function));
    bytecode_chunk_init(&function.chunk);

    function.param_count = proc->param_count;
    if (function.param_count > 0) {
        function.params = SAGE_ALLOC((size_t)function.param_count * sizeof(char*));
        memset(function.params, 0, (size_t)function.param_count * sizeof(char*));

        for (int i = 0; i < function.param_count; i++) {
            function.params[i] = dup_text(proc->params[i].start, (size_t)proc->params[i].length);
            if (function.params[i] == NULL) {
                for (int j = 0; j < i; j++) {
                    free(function.params[j]);
                }
                free(function.params);
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Out of memory while copying function parameter name.");
                return 0;
            }
        }
    }

    if (!bytecode_compile_function_body(&function.chunk, proc->body,
                                        compile_program_function, program,
                                        error, error_size)) {
        for (int i = 0; i < function.param_count; i++) {
            free(function.params[i]);
        }
        free(function.params);
        bytecode_chunk_free(&function.chunk);
        return 0;
    }

    return append_function(program, &function, error, error_size, function_index_out);
}

static Stmt* parse_program(const char* source, const char* input_path) {
    init_lexer(source, input_path);
    parser_init();

    Stmt* head = NULL;
    Stmt* tail = NULL;
    while (1) {
        Stmt* stmt = parse();
        if (stmt == NULL) {
            break;
        }

        if (head == NULL) {
            head = stmt;
        } else {
            tail->next = stmt;
        }
        tail = stmt;
    }

    return head;
}

static char hex_digit(int value) {
    return (char)(value < 10 ? ('0' + value) : ('a' + (value - 10)));
}

static int write_hex_line(FILE* out, const uint8_t* bytes, size_t byte_count) {
    for (size_t i = 0; i < byte_count; i++) {
        unsigned int value = bytes[i];
        if (fputc(hex_digit((int)((value >> 4) & 0xf)), out) == EOF ||
            fputc(hex_digit((int)(value & 0xf)), out) == EOF) {
            return 0;
        }
    }
    return fputc('\n', out) != EOF;
}

static int parse_nonnegative_int(const char* text, int* out) {
    char* end = NULL;
    long value = strtol(text, &end, 10);
    if (end == text || *end != '\0' || value < 0 || value > 0x7fffffffL) {
        return 0;
    }
    *out = (int)value;
    return 1;
}

static int parse_double_value(const char* text, double* out) {
    char* end = NULL;
    double value = strtod(text, &end);
    if (end == text || *end != '\0') {
        return 0;
    }
    *out = value;
    return 1;
}

static int hex_value(int ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return 10 + (ch - 'a');
    if (ch >= 'A' && ch <= 'F') return 10 + (ch - 'A');
    return -1;
}

static int decode_hex_line(const char* hex, size_t byte_count, uint8_t* out) {
    size_t expected_length = byte_count * 2;
    if (strlen(hex) != expected_length) {
        return 0;
    }

    for (size_t i = 0; i < byte_count; i++) {
        int high = hex_value((unsigned char)hex[i * 2]);
        int low = hex_value((unsigned char)hex[i * 2 + 1]);
        if (high < 0 || low < 0) {
            return 0;
        }
        out[i] = (uint8_t)((high << 4) | low);
    }

    return 1;
}

static int read_trimmed_line(FILE* file, char** line, size_t* capacity) {
    ssize_t line_len = getline(line, capacity, file);
    if (line_len < 0) {
        return 0;
    }

    while (line_len > 0 && ((*line)[line_len - 1] == '\n' || (*line)[line_len - 1] == '\r')) {
        (*line)[--line_len] = '\0';
    }
    return 1;
}

static int write_chunk_constants(FILE* out, const BytecodeChunk* chunk, char* error, size_t error_size) {
    if (fprintf(out, "constants %d\n", chunk->constant_count) < 0) {
        return 0;
    }

    for (int i = 0; i < chunk->constant_count; i++) {
        Value constant = chunk->constants[i];
        if (IS_NUMBER(constant)) {
            if (fprintf(out, "number %.17g\n", AS_NUMBER(constant)) < 0) {
                return 0;
            }
        } else if (IS_STRING(constant)) {
            size_t string_len = strlen(AS_STRING(constant));
            if (fprintf(out, "string %zu\n", string_len) < 0 ||
                !write_hex_line(out, (const uint8_t*)AS_STRING(constant), string_len)) {
                return 0;
            }
        } else {
            set_program_error(error, error_size,
                              "Compiled VM artifacts only support number/string constants.");
            return 0;
        }
    }

    return 1;
}

static int write_chunk_payload(FILE* out, const BytecodeChunk* chunk, const char* end_marker,
                               char* error, size_t error_size) {
    if (!write_chunk_constants(out, chunk, error, error_size)) {
        return 0;
    }

    return fprintf(out, "code %d\n", chunk->code_count) >= 0 &&
           write_hex_line(out, chunk->code, (size_t)chunk->code_count) &&
           fprintf(out, "%s\n", end_marker) >= 0;
}

static int read_chunk_constants(FILE* file, BytecodeChunk* chunk, char** line, size_t* line_capacity,
                                char* error, size_t error_size) {
    if (!read_trimmed_line(file, line, line_capacity) || strncmp(*line, "constants ", 10) != 0) {
        set_program_error(error, error_size, "Missing constant table in VM artifact.");
        return 0;
    }

    int constant_count = 0;
    if (!parse_nonnegative_int(*line + 10, &constant_count)) {
        set_program_error(error, error_size, "Invalid constant count in VM artifact.");
        return 0;
    }

    for (int i = 0; i < constant_count; i++) {
        if (!read_trimmed_line(file, line, line_capacity)) {
            set_program_error(error, error_size, "Unexpected EOF while reading constants.");
            return 0;
        }

        if (strncmp(*line, "number ", 7) == 0) {
            double value = 0.0;
            if (!parse_double_value(*line + 7, &value) ||
                !append_constant(chunk, val_number(value))) {
                set_program_error(error, error_size, "Invalid number constant in VM artifact.");
                return 0;
            }
            continue;
        }

        if (strncmp(*line, "string ", 7) == 0) {
            int string_len = 0;
            if (!parse_nonnegative_int(*line + 7, &string_len)) {
                set_program_error(error, error_size, "Invalid string length in VM artifact.");
                return 0;
            }

            if (!read_trimmed_line(file, line, line_capacity)) {
                set_program_error(error, error_size, "Unexpected EOF while reading string constant.");
                return 0;
            }

            char* decoded = SAGE_ALLOC((size_t)string_len + 1);

            if (!decode_hex_line(*line, (size_t)string_len, (uint8_t*)decoded)) {
                free(decoded);
                set_program_error(error, error_size, "Invalid string constant payload in VM artifact.");
                return 0;
            }
            decoded[string_len] = '\0';

            if (!append_constant(chunk, val_string_take(decoded))) {
                set_program_error(error, error_size, "Out of memory while storing string constant.");
                return 0;
            }
            continue;
        }

        set_program_error(error, error_size, "Unknown constant entry in VM artifact.");
        return 0;
    }

    return 1;
}

static int read_code_payload(FILE* file, BytecodeChunk* chunk, char** line, size_t* line_capacity,
                             const char* end_marker, char* error, size_t error_size) {
    if (!read_trimmed_line(file, line, line_capacity) || strncmp(*line, "code ", 5) != 0) {
        set_program_error(error, error_size, "Missing bytecode payload in VM artifact.");
        return 0;
    }

    int code_count = 0;
    if (!parse_nonnegative_int(*line + 5, &code_count) || !ensure_code_capacity(chunk, code_count)) {
        set_program_error(error, error_size, "Invalid code size in VM artifact.");
        return 0;
    }

    if (!read_trimmed_line(file, line, line_capacity)) {
        set_program_error(error, error_size, "Unexpected EOF while reading bytecode payload.");
        return 0;
    }

    if (!decode_hex_line(*line, (size_t)code_count, chunk->code)) {
        set_program_error(error, error_size, "Invalid bytecode payload in VM artifact.");
        return 0;
    }

    chunk->code_count = code_count;
    for (int i = 0; i < code_count; i++) {
        chunk->lines[i] = 0;
        chunk->columns[i] = 0;
    }

    if (!read_trimmed_line(file, line, line_capacity) || strcmp(*line, end_marker) != 0) {
        set_program_error(error, error_size, "Missing VM artifact end marker.");
        return 0;
    }

    return 1;
}

void bytecode_program_init(BytecodeProgram* program) {
    memset(program, 0, sizeof(*program));
}

void bytecode_program_free(BytecodeProgram* program) {
    for (int i = 0; i < program->chunk_count; i++) {
        bytecode_chunk_free(&program->chunks[i]);
    }
    free(program->chunks);

    for (int i = 0; i < program->function_count; i++) {
        for (int j = 0; j < program->functions[i].param_count; j++) {
            free(program->functions[i].params[j]);
        }
        free(program->functions[i].params);
        bytecode_chunk_free(&program->functions[i].chunk);
    }
    free(program->functions);

    memset(program, 0, sizeof(*program));
}

int bytecode_compile_program(BytecodeProgram* program, Stmt* statements, BytecodeCompileMode mode,
                             char* error, size_t error_size) {
    if (error != NULL && error_size > 0) {
        error[0] = '\0';
    }

    for (Stmt* stmt = statements; stmt != NULL; stmt = stmt->next) {
        BytecodeChunk chunk;
        bytecode_chunk_init(&chunk);

        if (!bytecode_compile_statement_with_functions(&chunk, stmt, mode,
                                                      mode == BYTECODE_COMPILE_STRICT ? compile_program_function : NULL,
                                                      program,
                                                      error, error_size)) {
            bytecode_chunk_free(&chunk);
            return 0;
        }

        if (!append_chunk(program, &chunk, error, error_size)) {
            bytecode_chunk_free(&chunk);
            return 0;
        }
    }

    return 1;
}

int bytecode_program_write_file(const BytecodeProgram* program, const char* output_path,
                                char* error, size_t error_size) {
    FILE* out = fopen(output_path, "wb");
    if (out == NULL) {
        if (error != NULL && error_size > 0) {
            snprintf(error, error_size, "Could not open \"%s\": %s", output_path, strerror(errno));
        }
        return 0;
    }

    int ok = fprintf(out, "SAGEBC1\nfunctions %d\n", program->function_count) >= 0;
    for (int i = 0; ok && i < program->function_count; i++) {
        const BytecodeFunction* function = &program->functions[i];
        ok = fprintf(out, "function\nparams %d\n", function->param_count) >= 0;
        for (int j = 0; ok && j < function->param_count; j++) {
            size_t param_len = strlen(function->params[j]);
            ok = fprintf(out, "param %zu\n", param_len) >= 0 &&
                 write_hex_line(out, (const uint8_t*)function->params[j], param_len);
        }
        if (ok) {
            ok = write_chunk_payload(out, &function->chunk, "endfunction", error, error_size);
        }
    }

    if (ok) {
        ok = fprintf(out, "chunks %d\n", program->chunk_count) >= 0;
    }
    for (int i = 0; ok && i < program->chunk_count; i++) {
        ok = fprintf(out, "chunk\n") >= 0 &&
             write_chunk_payload(out, &program->chunks[i], "endchunk", error, error_size);
    }

    if (fclose(out) != 0) {
        ok = 0;
    }

    if (!ok && error != NULL && error_size > 0 && error[0] == '\0') {
        snprintf(error, error_size, "Could not write compiled VM artifact \"%s\".", output_path);
    }

    return ok;
}

int bytecode_program_read_file(BytecodeProgram* program, const char* input_path,
                               char* error, size_t error_size) {
    FILE* file = fopen(input_path, "rb");
    char* line = NULL;
    size_t line_capacity = 0;
    int ok = 0;

    if (file == NULL) {
        if (error != NULL && error_size > 0) {
            snprintf(error, error_size, "Could not open \"%s\": %s", input_path, strerror(errno));
        }
        return 0;
    }

    if (!read_trimmed_line(file, &line, &line_capacity) || strcmp(line, "SAGEBC1") != 0) {
        set_program_error(error, error_size, "Invalid VM artifact header.");
        goto cleanup;
    }

    if (!read_trimmed_line(file, &line, &line_capacity)) {
        set_program_error(error, error_size, "Unexpected EOF while reading VM artifact.");
        goto cleanup;
    }

    if (strncmp(line, "functions ", 10) == 0) {
        int function_count = 0;
        if (!parse_nonnegative_int(line + 10, &function_count)) {
            set_program_error(error, error_size, "Invalid function count in VM artifact.");
            goto cleanup;
        }

        for (int i = 0; i < function_count; i++) {
            BytecodeFunction function;
            memset(&function, 0, sizeof(function));
            bytecode_chunk_init(&function.chunk);

            if (!read_trimmed_line(file, &line, &line_capacity) || strcmp(line, "function") != 0) {
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Invalid function marker in VM artifact.");
                goto cleanup;
            }

            if (!read_trimmed_line(file, &line, &line_capacity) || strncmp(line, "params ", 7) != 0) {
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Missing function parameter table in VM artifact.");
                goto cleanup;
            }

            if (!parse_nonnegative_int(line + 7, &function.param_count)) {
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Invalid function parameter count in VM artifact.");
                goto cleanup;
            }

            if (function.param_count > 0) {
                function.params = SAGE_ALLOC((size_t)function.param_count * sizeof(char*));
                memset(function.params, 0, (size_t)function.param_count * sizeof(char*));
            }

            for (int j = 0; j < function.param_count; j++) {
                int param_len = 0;
                if (!read_trimmed_line(file, &line, &line_capacity) || strncmp(line, "param ", 6) != 0 ||
                    !parse_nonnegative_int(line + 6, &param_len)) {
                    for (int k = 0; k < j; k++) free(function.params[k]);
                    free(function.params);
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Invalid function parameter entry in VM artifact.");
                    goto cleanup;
                }

                if (!read_trimmed_line(file, &line, &line_capacity)) {
                    for (int k = 0; k < j; k++) free(function.params[k]);
                    free(function.params);
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Unexpected EOF while reading function parameter.");
                    goto cleanup;
                }

                function.params[j] = SAGE_ALLOC((size_t)param_len + 1);

                if (!decode_hex_line(line, (size_t)param_len, (uint8_t*)function.params[j])) {
                    for (int k = 0; k <= j; k++) free(function.params[k]);
                    free(function.params);
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Invalid function parameter payload in VM artifact.");
                    goto cleanup;
                }
                function.params[j][param_len] = '\0';
            }

            if (!read_chunk_constants(file, &function.chunk, &line, &line_capacity, error, error_size) ||
                !read_code_payload(file, &function.chunk, &line, &line_capacity, "endfunction",
                                   error, error_size) ||
                !append_function(program, &function, error, error_size, NULL)) {
                for (int j = 0; j < function.param_count; j++) free(function.params[j]);
                free(function.params);
                bytecode_chunk_free(&function.chunk);
                goto cleanup;
            }
        }

        if (!read_trimmed_line(file, &line, &line_capacity)) {
            set_program_error(error, error_size, "Unexpected EOF while reading chunk table.");
            goto cleanup;
        }
    }

    if (strncmp(line, "chunks ", 7) != 0) {
        set_program_error(error, error_size, "Missing chunk table in VM artifact.");
        goto cleanup;
    }

    int chunk_count = 0;
    if (!parse_nonnegative_int(line + 7, &chunk_count)) {
        set_program_error(error, error_size, "Invalid chunk count in VM artifact.");
        goto cleanup;
    }

    for (int i = 0; i < chunk_count; i++) {
        BytecodeChunk chunk;
        bytecode_chunk_init(&chunk);

        if (!read_trimmed_line(file, &line, &line_capacity) || strcmp(line, "chunk") != 0) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Invalid chunk marker in VM artifact.");
            goto cleanup;
        }

        if (!read_chunk_constants(file, &chunk, &line, &line_capacity, error, error_size) ||
            !read_code_payload(file, &chunk, &line, &line_capacity, "endchunk", error, error_size) ||
            !append_chunk(program, &chunk, error, error_size)) {
            bytecode_chunk_free(&chunk);
            goto cleanup;
        }
    }

    ok = 1;

cleanup:
    free(line);
    fclose(file);
    if (!ok) {
        bytecode_program_free(program);
    }
    return ok;
}

int compile_source_to_vm_artifact(const char* source, const char* input_path, const char* output_path,
                                  int opt_level, int debug_info) {
    BytecodeProgram program;
    char error[256];
    Stmt* ast = parse_program(source, input_path);
    bytecode_program_init(&program);

    if (opt_level > 0) {
        PassContext pass_ctx;
        pass_ctx.opt_level = opt_level;
        pass_ctx.debug_info = debug_info;
        pass_ctx.verbose = 0;
        pass_ctx.input_path = input_path;
        ast = run_passes(ast, &pass_ctx);
    }

    if (!bytecode_compile_program(&program, ast, BYTECODE_COMPILE_STRICT, error, sizeof(error))) {
        fprintf(stderr, "VM compile error: %s\n", error[0] ? error : "unknown error");
        bytecode_program_free(&program);
        free_stmt(ast);
        return 0;
    }

    if (!bytecode_program_write_file(&program, output_path, error, sizeof(error))) {
        fprintf(stderr, "VM artifact error: %s\n", error[0] ? error : "unknown error");
        bytecode_program_free(&program);
        free_stmt(ast);
        return 0;
    }

    bytecode_program_free(&program);
    free_stmt(ast);
    return 1;
}
