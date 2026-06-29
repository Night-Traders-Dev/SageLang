#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/wait.h>

// Strip # comments from a line (returns pointer into the line buffer)
static char* strip_comment(char* line) {
    for (char* p = line; *p; p++) {
        if (*p == '#') {
            *p = '\0';
            break;
        }
    }
    return line;
}

// Trim trailing whitespace from a string
static char* trim_right(char* line) {
    int len = strlen(line);
    while (len > 0 && (line[len-1] == ' ' || line[len-1] == '\t' || 
                       line[len-1] == '\r' || line[len-1] == '\n')) {
        line[--len] = '\0';
    }
    return line;
}

// Validate a path contains no shell metacharacters (prevents injection via system())
static int is_safe_path(const char* path) {
    if (!path) return 1;
    if (path[0] == '-') return 0;
    for (const char* p = path; *p; p++) {
        // Allow alphanumeric and strictly safe filename characters
        // Note: Space is allowed here but must be handled carefully (quoted or via execvp)
        if (!isalnum((unsigned char)*p) && *p != '/' && *p != '.' &&
            *p != '-' && *p != '_' && *p != '~' && *p != ' ') {
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

#define MAX_CONSTS 1024
#define MAX_CHUNKS 1024
#define MAX_LOCALS 256

typedef struct {
    int type; // 1=num, 3=str
    double num;
    char* str;
    int str_len;
} Const;

Const global_consts[MAX_CONSTS];
int global_const_count = 0;

int add_const_num(double d) {
    for (int i = 0; i < global_const_count; i++) {
        if (global_consts[i].type == 1 && global_consts[i].num == d) return i;
    }
    if (global_const_count >= MAX_CONSTS) return -1;
    global_consts[global_const_count].type = 1;
    global_consts[global_const_count].num = d;
    return global_const_count++;
}

int add_const_str(const char* s, int len) {
    for (int i = 0; i < global_const_count; i++) {
        if (global_consts[i].type == 3 && global_consts[i].str_len == len && memcmp(global_consts[i].str, s, len) == 0) return i;
    }
    if (global_const_count >= MAX_CONSTS) return -1;
    global_consts[global_const_count].type = 3;
    global_consts[global_const_count].str = malloc(len + 1);
    if (!global_consts[global_const_count].str) return -1;
    memcpy(global_consts[global_const_count].str, s, len);
    global_consts[global_const_count].str[len] = '\0';
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

    char tmp_svm[] = "/tmp/sgvm_XXXXXX.svm";
    int fd = mkstemps(tmp_svm, 4);
    if (fd < 0) {
        perror("mkstemps");
        return 1;
    }
    close(fd);

    int ok = 0;
    pid_t pid = fork();
    if (pid == 0) {
        char* sage_args[] = {"./sage", "--emit-vm", argv[1], "-o", tmp_svm, NULL};
        execvp(sage_args[0], sage_args);
        _exit(127);
    } else if (pid > 0) {
        int status;
        waitpid(pid, &status, 0);
        ok = (WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }

    if (!ok) {
        remove(tmp_svm);
        return 1;
    }

    FILE* in = fopen(tmp_svm, "r");
    if (!in) {
        remove(tmp_svm);
        return 1;
    }

    char line[1024];
    int chunk_count = 0;
    int (*local_to_global)[MAX_LOCALS] = calloc(MAX_CHUNKS, sizeof(*local_to_global));
    if (!local_to_global) {
        fclose(in);
        return 1;
    }
    int current_chunk = -1;

    while (fgets(line, sizeof(line), in)) {
        strip_comment(line);
        char* nl = strchr(line, '\n');
        if (nl) {
            // Trim trailing whitespace before newline
            char* p = nl;
            while (p > line && (p[-1] == ' ' || p[-1] == '\t')) p--;
            memmove(p, nl, strlen(nl) + 1);
        }
        if (strncmp(line, "chunks ", 7) == 0) chunk_count = atoi(line + 7);
        else if (strcmp(line, "chunk\n") == 0) current_chunk++;
        else if (strncmp(line, "constants ", 10) == 0) {
            int count = atoi(line + 10);
            if (current_chunk < 0 || current_chunk >= MAX_CHUNKS) continue;
            for (int i = 0; i < count; i++) {
                if (!fgets(line, sizeof(line), in)) break;
                if (i >= MAX_LOCALS) continue;
                if (strncmp(line, "number ", 7) == 0) {
                    local_to_global[current_chunk][i] = add_const_num(atof(line + 7));
                } else if (strncmp(line, "string ", 7) == 0) {
                    int len = atoi(line + 7);
                    if (!fgets(line, sizeof(line), in)) break;
                    if (len >= 0 && (size_t)len * 2 <= strlen(line)) {
                        if (len == 0) {
                            local_to_global[current_chunk][i] = add_const_str("", 0);
                        } else {
                            char* buf = malloc(len);
                            if (buf) {
                                for (int j = 0; j < len * 2; j += 2) buf[j / 2] = hex_to_byte(line + j);
                                local_to_global[current_chunk][i] = add_const_str(buf, len);
                                free(buf);
                            } else {
                                local_to_global[current_chunk][i] = -1;
                            }
                        }
                    } else {
                        local_to_global[current_chunk][i] = -1;
                    }
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
        strip_comment(line);
        char* nl2 = strchr(line, '\n');
        if (nl2) {
            char* p = nl2;
            while (p > line && (p[-1] == ' ' || p[-1] == '\t')) p--;
            memmove(p, nl2, strlen(nl2) + 1);
        }
        if (strcmp(line, "chunk\n") == 0) current_chunk++;
        else if (strncmp(line, "code ", 5) == 0) {
            int len = atoi(line + 5);
            write_be32(out, (uint32_t)len);
            if (!fgets(line, sizeof(line), in)) break;
            for (int j = 0; j < len * 2; ) {
                uint8_t op = hex_to_byte(line + j);
                fputc(op, out);
                j += 2;
                // List of opcodes that take operands
                // List of opcodes that take operands
                if (op == 0 || op == 5 || op == 6 || op == 7 || op == 9 || op == 10 || op == 52 || op == 53 || op == 54) {
                    int local_idx = (hex_to_byte(line + j) << 8) | hex_to_byte(line + j + 2);
                    int g_idx = (current_chunk >= 0 && current_chunk < MAX_CHUNKS && local_idx >= 0 && local_idx < MAX_LOCALS)
                                ? local_to_global[current_chunk][local_idx] : -1;
                    if (g_idx < 0) g_idx = 0; // Fallback for invalid constants
                    fputc((g_idx >> 8) & 0xFF, out);
                    fputc(g_idx & 0xFF, out);
                    j += 4;
                } else if (op == 8) { // DEFINE_FUNCTION (16-bit name, 16-bit function)
                    int local_idx = (hex_to_byte(line + j) << 8) | hex_to_byte(line + j + 2);
                    int g_idx = local_to_global[current_chunk][local_idx];
                    fputc((g_idx >> 8) & 0xFF, out);
                    fputc(g_idx & 0xFF, out);
                    fputc(hex_to_byte(line + j + 4), out);
                    fputc(hex_to_byte(line + j + 6), out);
                    j += 8;
                } else if (op == 13 || op == 35 || op == 36 || op == 39 || op == 40 || op == 41 || 
                           op == 43 || op == 49 || op == 50 || op == 51 || op == 56) {
                    // 16-bit non-constant operand
                    fputc(hex_to_byte(line + j), out);
                    fputc(hex_to_byte(line + j + 2), out);
                    j += 4;
                } else if (op == 38) { // CALL_METHOD (16-bit name, 8-bit count)
                    int local_idx = (hex_to_byte(line + j) << 8) | hex_to_byte(line + j + 2);
                    int g_idx = local_to_global[current_chunk][local_idx];
                    fputc((g_idx >> 8) & 0xFF, out);
                    fputc(g_idx & 0xFF, out);
                    fputc(hex_to_byte(line + j + 4), out);
                    j += 6;
                } else if (op == 37 || op == 47) { // 8-bit operand
                    fputc(hex_to_byte(line + j), out);
                    j += 2;
                }
            }
        }
    }

    fclose(in); fclose(out);
    free(local_to_global);
    remove(tmp_svm);
    printf("Compiled %s to %s\n", argv[1], argv[2]);
    return 0;
}
