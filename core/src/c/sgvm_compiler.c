#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

// Validate a path contains no shell metacharacters (prevents injection via system())
static int is_safe_path(const char* path) {
    if (!path) return 1;
    for (const char* p = path; *p; p++) {
        // Allow alphanumeric and strictly safe filename characters
        if (!isalnum((unsigned char)*p) && *p != '/' && *p != '.' &&
            *p != '-' && *p != '_' && *p != '~') {
            return 0;
        }
    }
    return 1;
}

void write_be16(FILE* f, uint16_t v) {
    fputc((v >> 8) & 0xFF, f);
    fputc(v & 0xFF, f);
}

void write_be32(FILE* f, uint32_t v) {
    fputc((v >> 24) & 0xFF, f);
    fputc((v >> 16) & 0xFF, f);
    fputc((v >> 8) & 0xFF, f);
    fputc(v & 0xFF, f);
}

uint8_t hex_to_byte(const char* hex) {
    uint32_t b;
    if (sscanf(hex, "%02x", &b) != 1) return 0;
    return (uint8_t)b;
}

typedef struct {
    int type; // 1=num, 3=str
    double num;
    char* str;
    int str_len;
} Const;

Const global_consts[1024];
int global_const_count = 0;

int add_const_num(double d) {
    for (int i = 0; i < global_const_count; i++) {
        if (global_consts[i].type == 1 && global_consts[i].num == d) return i;
    }
    global_consts[global_const_count].type = 1;
    global_consts[global_const_count].num = d;
    return global_const_count++;
}

int add_const_str(const char* s, int len) {
    for (int i = 0; i < global_const_count; i++) {
        if (global_consts[i].type == 3 && global_consts[i].str_len == len && memcmp(global_consts[i].str, s, len) == 0) return i;
    }
    global_consts[global_const_count].type = 3;
    global_consts[global_const_count].str = malloc(len + 1);
    memcpy(global_consts[global_const_count].str, s, len);
    global_consts[global_const_count].str_len = len;
    return global_const_count++;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: sgvmc <input.sage> <output.sgvm>\n");
        return 1;
    }

    if (!is_safe_path(argv[1]) || !is_safe_path(argv[2])) {
        fprintf(stderr, "Error: path contains unsafe characters.\n");
        return 1;
    }

    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "./sage --emit-vm %s -o .tmp.svm", argv[1]);
    if (system(cmd) != 0) return 1;

    FILE* in = fopen(".tmp.svm", "r");
    if (!in) return 1;

    char line[1024];
    int chunk_count = 0;
    int local_to_global[1024][256];
    int current_chunk = -1;

    while (fgets(line, sizeof(line), in)) {
        if (strncmp(line, "chunks ", 7) == 0) chunk_count = atoi(line + 7);
        else if (strcmp(line, "chunk\n") == 0) current_chunk++;
        else if (strncmp(line, "constants ", 10) == 0) {
            int count = atoi(line + 10);
            for (int i = 0; i < count; i++) {
                fgets(line, sizeof(line), in);
                if (strncmp(line, "number ", 7) == 0) {
                    local_to_global[current_chunk][i] = add_const_num(atof(line + 7));
                } else if (strncmp(line, "string ", 7) == 0) {
                    int len = atoi(line + 7);
                    fgets(line, sizeof(line), in);
                    char* buf = malloc(len);
                    for (int j = 0; j < len * 2; j += 2) buf[j / 2] = hex_to_byte(line + j);
                    local_to_global[current_chunk][i] = add_const_str(buf, len);
                    free(buf);
                }
            }
        }
    }

    FILE* out = fopen(argv[2], "wb");
    fwrite("SGVM", 1, 4, out);
    fputc(0x01, out); fputc(0x00, out);

    write_be16(out, (uint16_t)global_const_count);
    for (int i = 0; i < global_const_count; i++) {
        fputc(global_consts[i].type, out);
        if (global_consts[i].type == 1) fwrite(&global_consts[i].num, 1, 8, out);
        else {
            write_be16(out, (uint16_t)global_consts[i].str_len);
            fwrite(global_consts[i].str, 1, global_consts[i].str_len, out);
        }
    }

    write_be32(out, (uint32_t)chunk_count);
    fseek(in, 0, SEEK_SET);
    current_chunk = -1;
    while (fgets(line, sizeof(line), in)) {
        if (strcmp(line, "chunk\n") == 0) current_chunk++;
        else if (strncmp(line, "code ", 5) == 0) {
            int len = atoi(line + 5);
            write_be32(out, (uint32_t)len);
            fgets(line, sizeof(line), in);
            for (int j = 0; j < len * 2; ) {
                uint8_t op = hex_to_byte(line + j);
                fputc(op, out);
                j += 2;
                // List of opcodes that take 16-bit operand
                if (op == 0 || op == 5 || op == 6 || op == 7 || op == 8 || op == 9 || op == 10 ||
                    op == 34 || op == 35 || op == 36 || op == 37 || op == 38 || op == 39 || op == 40 ||
                    op == 50) {
                    if (op == 0 || op == 5 || op == 6 || op == 7) {
                        int local_idx = (hex_to_byte(line + j) << 8) | hex_to_byte(line + j + 2);
                        int g_idx = local_to_global[current_chunk][local_idx];
                        fputc((g_idx >> 8) & 0xFF, out);
                        fputc(g_idx & 0xFF, out);
                    } else {
                        fputc(hex_to_byte(line + j), out);
                        fputc(hex_to_byte(line + j + 2), out);
                    }
                    j += 4;
                }
            }
        }
    }

    fclose(in); fclose(out);
    remove(".tmp.svm");
    printf("Compiled %s to %s\n", argv[1], argv[2]);
    return 0;
}
