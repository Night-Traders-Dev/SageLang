#include "program.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#include "lexer.h"
#include "parser.h"
#include "pass.h"

static void set_program_error(char* error, size_t error_size, const char* message) {
    if (error != NULL && error_size > 0) {
        snprintf(error, error_size, "%s", message);
    }
}

static int ensure_chunk_capacity(BytecodeProgram* program) {
    if (program->chunk_count < program->chunk_capacity) {
        return 1;
    }

    int new_capacity = program->chunk_capacity == 0 ? 8 : program->chunk_capacity * 2;
    BytecodeChunk* new_chunks = realloc(program->chunks, sizeof(BytecodeChunk) * (size_t)new_capacity);
    if (new_chunks == NULL) {
        return 0;
    }

    program->chunks = new_chunks;
    program->chunk_capacity = new_capacity;
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

    Value* new_constants = realloc(chunk->constants, sizeof(Value) * (size_t)new_capacity);
    if (new_constants == NULL) {
        return 0;
    }

    chunk->constants = new_constants;
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

    uint8_t* new_code = malloc((size_t)new_capacity);
    int* new_lines = malloc(sizeof(int) * (size_t)new_capacity);
    int* new_columns = malloc(sizeof(int) * (size_t)new_capacity);
    if (new_code == NULL || new_lines == NULL || new_columns == NULL) {
        free(new_code);
        free(new_lines);
        free(new_columns);
        return 0;
    }

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

    program->chunks[program->chunk_count++] = *chunk;
    memset(chunk, 0, sizeof(*chunk));
    return 1;
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

void bytecode_program_init(BytecodeProgram* program) {
    memset(program, 0, sizeof(*program));
}

void bytecode_program_free(BytecodeProgram* program) {
    for (int i = 0; i < program->chunk_count; i++) {
        bytecode_chunk_free(&program->chunks[i]);
    }
    free(program->chunks);
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

        if (!bytecode_compile_statement_mode(&chunk, stmt, mode, error, error_size)) {
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

    int ok = fprintf(out, "SAGEBC1\nchunks %d\n", program->chunk_count) >= 0;
    for (int i = 0; ok && i < program->chunk_count; i++) {
        const BytecodeChunk* chunk = &program->chunks[i];
        ok = fprintf(out, "chunk\nconstants %d\n", chunk->constant_count) >= 0;

        for (int j = 0; ok && j < chunk->constant_count; j++) {
            Value constant = chunk->constants[j];
            if (IS_NUMBER(constant)) {
                ok = fprintf(out, "number %.17g\n", AS_NUMBER(constant)) >= 0;
            } else if (IS_STRING(constant)) {
                size_t string_len = strlen(AS_STRING(constant));
                ok = fprintf(out, "string %zu\n", string_len) >= 0 &&
                     write_hex_line(out, (const uint8_t*)AS_STRING(constant), string_len);
            } else {
                set_program_error(error, error_size, "Compiled VM artifacts only support number/string constants.");
                ok = 0;
            }
        }

        if (ok) {
            ok = fprintf(out, "code %d\n", chunk->code_count) >= 0 &&
                 write_hex_line(out, chunk->code, (size_t)chunk->code_count) &&
                 fprintf(out, "endchunk\n") >= 0;
        }
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

    if (!read_trimmed_line(file, &line, &line_capacity) || strncmp(line, "chunks ", 7) != 0) {
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

        if (!read_trimmed_line(file, &line, &line_capacity) || strncmp(line, "constants ", 10) != 0) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Missing constant table in VM artifact.");
            goto cleanup;
        }

        int constant_count = 0;
        if (!parse_nonnegative_int(line + 10, &constant_count)) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Invalid constant count in VM artifact.");
            goto cleanup;
        }

        for (int j = 0; j < constant_count; j++) {
            if (!read_trimmed_line(file, &line, &line_capacity)) {
                bytecode_chunk_free(&chunk);
                set_program_error(error, error_size, "Unexpected EOF while reading constants.");
                goto cleanup;
            }

            if (strncmp(line, "number ", 7) == 0) {
                double value = 0.0;
                if (!parse_double_value(line + 7, &value) || !append_constant(&chunk, val_number(value))) {
                    bytecode_chunk_free(&chunk);
                    set_program_error(error, error_size, "Invalid number constant in VM artifact.");
                    goto cleanup;
                }
                continue;
            }

            if (strncmp(line, "string ", 7) == 0) {
                int string_len = 0;
                if (!parse_nonnegative_int(line + 7, &string_len)) {
                    bytecode_chunk_free(&chunk);
                    set_program_error(error, error_size, "Invalid string length in VM artifact.");
                    goto cleanup;
                }

                if (!read_trimmed_line(file, &line, &line_capacity)) {
                    bytecode_chunk_free(&chunk);
                    set_program_error(error, error_size, "Unexpected EOF while reading string constant.");
                    goto cleanup;
                }

                char* decoded = malloc((size_t)string_len + 1);
                if (decoded == NULL) {
                    bytecode_chunk_free(&chunk);
                    set_program_error(error, error_size, "Out of memory while decoding string constant.");
                    goto cleanup;
                }

                if (!decode_hex_line(line, (size_t)string_len, (uint8_t*)decoded)) {
                    free(decoded);
                    bytecode_chunk_free(&chunk);
                    set_program_error(error, error_size, "Invalid string constant payload in VM artifact.");
                    goto cleanup;
                }
                decoded[string_len] = '\0';

                if (!append_constant(&chunk, val_string_take(decoded))) {
                    bytecode_chunk_free(&chunk);
                    set_program_error(error, error_size, "Out of memory while storing string constant.");
                    goto cleanup;
                }
                continue;
            }

            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Unknown constant entry in VM artifact.");
            goto cleanup;
        }

        if (!read_trimmed_line(file, &line, &line_capacity) || strncmp(line, "code ", 5) != 0) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Missing bytecode payload in VM artifact.");
            goto cleanup;
        }

        int code_count = 0;
        if (!parse_nonnegative_int(line + 5, &code_count) || !ensure_code_capacity(&chunk, code_count)) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Invalid code size in VM artifact.");
            goto cleanup;
        }

        if (!read_trimmed_line(file, &line, &line_capacity)) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Unexpected EOF while reading bytecode payload.");
            goto cleanup;
        }

        if (!decode_hex_line(line, (size_t)code_count, chunk.code)) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Invalid bytecode payload in VM artifact.");
            goto cleanup;
        }

        chunk.code_count = code_count;
        for (int j = 0; j < code_count; j++) {
            chunk.lines[j] = 0;
            chunk.columns[j] = 0;
        }

        if (!read_trimmed_line(file, &line, &line_capacity) || strcmp(line, "endchunk") != 0) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Missing endchunk marker in VM artifact.");
            goto cleanup;
        }

        if (!append_chunk(program, &chunk, error, error_size)) {
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
