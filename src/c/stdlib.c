// src/stdlib.c - Native standard library modules
//
// Provides C-backed implementations for: math, io, string, sys, thread
// These are registered as pre-loaded modules in the module cache,
// so `import math` finds the native version before any .sage file.

#define _DEFAULT_SOURCE
#include "module.h"
#include "value.h"
#include "env.h"
#include "gc.h"
#include "interpreter.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include "sage_thread.h"

// ============================================================================
// Helper: Create a native module (pre-loaded, no .sage file needed)
// ============================================================================

Module* create_native_module(ModuleCache* cache, const char* name) {
    Module* m = SAGE_ALLOC(sizeof(Module));
    m->name = SAGE_STRDUP(name);
    m->path = NULL;
    m->source = NULL;
    m->ast = NULL;
    m->ast_tail = NULL;
    m->env = env_create(g_global_env);
    m->is_loaded = true;
    m->is_loading = false;
    m->next = cache->modules;
    cache->modules = m;
    return m;
}

// ============================================================================
// MATH MODULE
// ============================================================================

static Value math_sin_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(sin(AS_NUMBER(args[0])));
}

static Value math_cos_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(cos(AS_NUMBER(args[0])));
}

static Value math_tan_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(tan(AS_NUMBER(args[0])));
}

static Value math_asin_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(asin(AS_NUMBER(args[0])));
}

static Value math_acos_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(acos(AS_NUMBER(args[0])));
}

static Value math_atan_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(atan(AS_NUMBER(args[0])));
}

static Value math_atan2_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    return val_number(atan2(AS_NUMBER(args[0]), AS_NUMBER(args[1])));
}

static Value math_random_native(int argCount, Value* args) {
    return val_number((double)rand() / (double)RAND_MAX);
}

static Value math_sqrt_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(sqrt(AS_NUMBER(args[0])));
}

static Value math_pow_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    return val_number(pow(AS_NUMBER(args[0]), AS_NUMBER(args[1])));
}

static Value math_log_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(log(AS_NUMBER(args[0])));
}

static Value math_log10_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(log10(AS_NUMBER(args[0])));
}

static Value math_exp_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(exp(AS_NUMBER(args[0])));
}

static Value math_floor_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(floor(AS_NUMBER(args[0])));
}

static Value math_ceil_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(ceil(AS_NUMBER(args[0])));
}

static Value math_round_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(round(AS_NUMBER(args[0])));
}

static Value math_abs_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    return val_number(fabs(AS_NUMBER(args[0])));
}

static Value math_fmod_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    return val_number(fmod(AS_NUMBER(args[0]), AS_NUMBER(args[1])));
}

static Value math_min_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    double a = AS_NUMBER(args[0]), b = AS_NUMBER(args[1]);
    return val_number(a < b ? a : b);
}

static Value math_max_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    double a = AS_NUMBER(args[0]), b = AS_NUMBER(args[1]);
    return val_number(a > b ? a : b);
}

static Value math_clamp_native(int argCount, Value* args) {
    if (argCount < 3 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1]) || !IS_NUMBER(args[2]))
        return val_nil();
    double v = AS_NUMBER(args[0]);
    double lo = AS_NUMBER(args[1]);
    double hi = AS_NUMBER(args[2]);
    if (v < lo) return val_number(lo);
    if (v > hi) return val_number(hi);
    return val_number(v);
}

static Value math_isnan_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    return val_bool(isnan(AS_NUMBER(args[0])));
}

static Value math_isinf_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    return val_bool(isinf(AS_NUMBER(args[0])));
}

Module* create_math_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "math");
    Environment* e = m->env;

    // Trig
    env_define(e, "sin", 3, val_native(math_sin_native));
    env_define(e, "cos", 3, val_native(math_cos_native));
    env_define(e, "tan", 3, val_native(math_tan_native));
    env_define(e, "asin", 4, val_native(math_asin_native));
    env_define(e, "acos", 4, val_native(math_acos_native));
    env_define(e, "atan", 4, val_native(math_atan_native));
    env_define(e, "atan2", 5, val_native(math_atan2_native));

    // Powers & roots
    env_define(e, "sqrt", 4, val_native(math_sqrt_native));
    env_define(e, "pow", 3, val_native(math_pow_native));
    env_define(e, "log", 3, val_native(math_log_native));
    env_define(e, "log10", 5, val_native(math_log10_native));
    env_define(e, "exp", 3, val_native(math_exp_native));

    // Rounding
    env_define(e, "floor", 5, val_native(math_floor_native));
    env_define(e, "ceil", 4, val_native(math_ceil_native));
    env_define(e, "round", 5, val_native(math_round_native));
    env_define(e, "abs", 3, val_native(math_abs_native));
    env_define(e, "fmod", 4, val_native(math_fmod_native));

    // Min/max/clamp
    env_define(e, "min", 3, val_native(math_min_native));
    env_define(e, "max", 3, val_native(math_max_native));
    env_define(e, "clamp", 5, val_native(math_clamp_native));

    // Checks
    env_define(e, "isnan", 5, val_native(math_isnan_native));
    env_define(e, "isinf", 5, val_native(math_isinf_native));

    // Constants
    env_define(e, "pi", 2, val_number(3.14159265358979323846));
    env_define(e, "PI", 2, val_number(3.14159265358979323846));  // Uppercase alias
    env_define(e, "e", 1, val_number(2.71828182845904523536));
    env_define(e, "inf", 3, val_number(INFINITY));
    env_define(e, "nan", 3, val_number(NAN));
    env_define(e, "tau", 3, val_number(6.28318530717958647692));

    // Random
    env_define(e, "random", 6, val_native(math_random_native));

    return m;
}

// ============================================================================
// IO MODULE
// ============================================================================

static Value io_readfile_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    const char* path = AS_STRING(args[0]);

    FILE* f = fopen(path, "rb");
    if (!f) return val_nil();

    fseek(f, 0, SEEK_END);
    long length = ftell(f);
    if (length < 0) { fclose(f); return val_nil(); }
    fseek(f, 0, SEEK_SET);

    char* buf = SAGE_ALLOC((size_t)length + 1);
    size_t read = fread(buf, 1, (size_t)length, f);
    buf[read] = '\0';
    fclose(f);

    return val_string_take(buf);
}

static Value io_writefile_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    const char* path = AS_STRING(args[0]);
    const char* content = AS_STRING(args[1]);

    FILE* f = fopen(path, "wb");
    if (!f) return val_bool(0);

    size_t len = strlen(content);
    size_t written = fwrite(content, 1, len, f);
    fclose(f);

    return val_bool(written == len);
}

static Value io_writebytes_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_ARRAY(args[1])) return val_bool(0);
    const char* path = AS_STRING(args[0]);
    ArrayValue* arr = AS_ARRAY(args[1]);

    FILE* f = fopen(path, "wb");
    if (!f) return val_bool(0);

    unsigned char* buf = malloc((size_t)arr->count);
    for (int i = 0; i < arr->count; i++) {
        if (IS_NUMBER(arr->elements[i])) {
            buf[i] = (unsigned char)AS_NUMBER(arr->elements[i]);
        } else {
            buf[i] = 0;
        }
    }

    size_t written = fwrite(buf, 1, (size_t)arr->count, f);
    free(buf);
    fclose(f);

    return val_bool(written == (size_t)arr->count);
}

static Value io_appendbytes_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_ARRAY(args[1])) return val_bool(0);
    const char* path = AS_STRING(args[0]);
    ArrayValue* arr = AS_ARRAY(args[1]);

    FILE* f = fopen(path, "ab");
    if (!f) return val_bool(0);

    unsigned char* buf = malloc((size_t)arr->count);
    for (int i = 0; i < arr->count; i++) {
        if (IS_NUMBER(arr->elements[i])) {
            buf[i] = (unsigned char)AS_NUMBER(arr->elements[i]);
        } else {
            buf[i] = 0;
        }
    }

    size_t written = fwrite(buf, 1, (size_t)arr->count, f);
    free(buf);
    fclose(f);

    return val_bool(written == (size_t)arr->count);
}

static Value io_appendfile_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    const char* path = AS_STRING(args[0]);
    const char* content = AS_STRING(args[1]);

    FILE* f = fopen(path, "ab");
    if (!f) return val_bool(0);

    size_t len = strlen(content);
    size_t written = fwrite(content, 1, len, f);
    fclose(f);

    return val_bool(written == len);
}

static Value io_exists_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_bool(0);
    struct stat st;
    return val_bool(stat(AS_STRING(args[0]), &st) == 0);
}

static Value io_remove_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_bool(0);
    return val_bool(remove(AS_STRING(args[0])) == 0);
}

static Value io_isdir_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_bool(0);
    struct stat st;
    if (stat(AS_STRING(args[0]), &st) != 0) return val_bool(0);
    return val_bool(S_ISDIR(st.st_mode));
}

static Value io_filesize_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_number(-1);
    struct stat st;
    if (stat(AS_STRING(args[0]), &st) != 0) return val_number(-1);
    return val_number((double)st.st_size);
}

// io.readbytes(path) -> array of byte values (0-255)
static Value io_readbytes_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    FILE* f = fopen(AS_STRING(args[0]), "rb");
    if (!f) return val_nil();
    fseek(f, 0, SEEK_END);
    long length = ftell(f);
    if (length < 0 || length > 100*1024*1024) { fclose(f); return val_nil(); } // 100MB max
    fseek(f, 0, SEEK_SET);
    unsigned char* buf = malloc((size_t)length);
    size_t read = fread(buf, 1, (size_t)length, f);
    fclose(f);
    // Create array of byte values
    ArrayValue* arr = SAGE_ALLOC(sizeof(ArrayValue));
    arr->count = (int)read;
    arr->capacity = (int)read;
    arr->elements = SAGE_ALLOC(sizeof(Value) * read);
    for (size_t i = 0; i < read; i++) {
        arr->elements[i] = val_number((double)buf[i]);
    }
    free(buf);
    Value result;
    result.type = VAL_ARRAY;
    result.as.array = arr;
    return result;
}

// io.listdir(path) -> array of filename strings
static Value io_listdir_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    DIR* d = opendir(AS_STRING(args[0]));
    if (!d) return val_nil();
    ArrayValue* arr = SAGE_ALLOC(sizeof(ArrayValue));
    arr->count = 0;
    arr->capacity = 32;
    arr->elements = SAGE_ALLOC(sizeof(Value) * 32);
    struct dirent* entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.') continue; // skip hidden/. /..
        if (arr->count >= arr->capacity) {
            arr->capacity *= 2;
            arr->elements = SAGE_REALLOC(arr->elements, sizeof(Value) * arr->capacity);
        }
        arr->elements[arr->count++] = val_string(entry->d_name);
    }
    closedir(d);
    Value result;
    result.type = VAL_ARRAY;
    result.as.array = arr;
    return result;
}

Module* create_io_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "io");
    Environment* e = m->env;

    env_define(e, "readfile", 8, val_native(io_readfile_native));
    env_define(e, "writefile", 9, val_native(io_writefile_native));
    env_define(e, "appendfile", 10, val_native(io_appendfile_native));
    env_define(e, "writebytes", 10, val_native(io_writebytes_native));
    env_define(e, "appendbytes", 11, val_native(io_appendbytes_native));
    env_define(e, "exists", 6, val_native(io_exists_native));
    env_define(e, "remove", 6, val_native(io_remove_native));
    env_define(e, "isdir", 5, val_native(io_isdir_native));
    env_define(e, "filesize", 8, val_native(io_filesize_native));
    env_define(e, "readbytes", 9, val_native(io_readbytes_native));
    env_define(e, "listdir", 7, val_native(io_listdir_native));

    return m;
}

// ============================================================================
// STRING MODULE
// ============================================================================

static Value str_find_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_number(-1);
    const char* haystack = AS_STRING(args[0]);
    const char* needle = AS_STRING(args[1]);
    const char* p = strstr(haystack, needle);
    if (!p) return val_number(-1);
    return val_number((double)(p - haystack));
}

static Value str_rfind_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_number(-1);
    const char* haystack = AS_STRING(args[0]);
    const char* needle = AS_STRING(args[1]);
    size_t hlen = strlen(haystack);
    size_t nlen = strlen(needle);
    if (nlen > hlen) return val_number(-1);
    for (size_t i = hlen - nlen + 1; i > 0; i--) {
        if (memcmp(haystack + i - 1, needle, nlen) == 0)
            return val_number((double)(i - 1));
    }
    return val_number(-1);
}

static Value str_startswith_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    const char* s = AS_STRING(args[0]);
    const char* prefix = AS_STRING(args[1]);
    size_t plen = strlen(prefix);
    return val_bool(strncmp(s, prefix, plen) == 0);
}

static Value str_endswith_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    const char* s = AS_STRING(args[0]);
    const char* suffix = AS_STRING(args[1]);
    size_t slen = strlen(s);
    size_t xlen = strlen(suffix);
    if (xlen > slen) return val_bool(0);
    return val_bool(memcmp(s + slen - xlen, suffix, xlen) == 0);
}

static Value str_contains_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    return val_bool(strstr(AS_STRING(args[0]), AS_STRING(args[1])) != NULL);
}

static Value str_char_at_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    const char* s = AS_STRING(args[0]);
    int idx = (int)AS_NUMBER(args[1]);
    int slen = (int)strlen(s);
    if (idx < 0 || idx >= slen) return val_nil();
    char buf[2] = { s[idx], '\0' };
    return val_string(buf);
}

static Value str_ord_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    const char* s = AS_STRING(args[0]);
    if (s[0] == '\0') return val_nil();
    return val_number((double)(unsigned char)s[0]);
}

static Value str_chr_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    int code = (int)AS_NUMBER(args[0]);
    if (code < 0 || code > 127) return val_nil();
    char buf[2] = { (char)code, '\0' };
    return val_string(buf);
}

static Value str_repeat_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    const char* s = AS_STRING(args[0]);
    int count = (int)AS_NUMBER(args[1]);
    if (count <= 0) return val_string("");
    size_t slen = strlen(s);
    if (slen > 0 && (size_t)count > (64 * 1024 * 1024) / slen) return val_nil();  // overflow guard
    size_t total = slen * (size_t)count;
    char* buf = SAGE_ALLOC(total + 1);
    for (int i = 0; i < count; i++) {
        memcpy(buf + (size_t)i * slen, s, slen);
    }
    buf[total] = '\0';
    return val_string_take(buf);
}

static Value str_count_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_number(0);
    const char* s = AS_STRING(args[0]);
    const char* sub = AS_STRING(args[1]);
    size_t sublen = strlen(sub);
    if (sublen == 0) return val_number(0);
    int count = 0;
    const char* p = s;
    while ((p = strstr(p, sub)) != NULL) {
        count++;
        p += sublen;
    }
    return val_number((double)count);
}

static Value str_substr_native(int argCount, Value* args) {
    if (argCount < 3 || !IS_STRING(args[0]) || !IS_NUMBER(args[1]) || !IS_NUMBER(args[2]))
        return val_nil();
    const char* s = AS_STRING(args[0]);
    int start = (int)AS_NUMBER(args[1]);
    int length = (int)AS_NUMBER(args[2]);
    int slen = (int)strlen(s);
    if (start < 0) start = 0;
    if (start >= slen) return val_string("");
    if (length < 0) length = 0;
    if (start + length > slen) length = slen - start;
    char* buf = SAGE_ALLOC((size_t)length + 1);
    memcpy(buf, s + start, (size_t)length);
    buf[length] = '\0';
    return val_string_take(buf);
}

static Value str_reverse_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    const char* s = AS_STRING(args[0]);
    size_t slen = strlen(s);
    char* buf = SAGE_ALLOC(slen + 1);
    for (size_t i = 0; i < slen; i++) {
        buf[i] = s[slen - 1 - i];
    }
    buf[slen] = '\0';
    return val_string_take(buf);
}

Module* create_string_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "string");
    Environment* e = m->env;

    env_define(e, "find", 4, val_native(str_find_native));
    env_define(e, "rfind", 5, val_native(str_rfind_native));
    env_define(e, "startswith", 10, val_native(str_startswith_native));
    env_define(e, "endswith", 8, val_native(str_endswith_native));
    env_define(e, "contains", 8, val_native(str_contains_native));
    env_define(e, "char_at", 7, val_native(str_char_at_native));
    env_define(e, "ord", 3, val_native(str_ord_native));
    env_define(e, "chr", 3, val_native(str_chr_native));
    env_define(e, "repeat", 6, val_native(str_repeat_native));
    env_define(e, "count", 5, val_native(str_count_native));
    env_define(e, "substr", 6, val_native(str_substr_native));
    env_define(e, "reverse", 7, val_native(str_reverse_native));

    return m;
}

// ============================================================================
// SYS MODULE
// ============================================================================

static int s_argc = 0;
static const char** s_argv = NULL;

void sage_set_args(int argc, const char** argv) {
    s_argc = argc;
    s_argv = argv;
}

static Value sys_args_native(int argCount, Value* args) {
    (void)argCount; (void)args;
    gc_pin();
    Value arr = val_array();
    for (int i = 0; i < s_argc; i++) {
        array_push(&arr, val_string(s_argv[i]));
    }
    gc_unpin();
    return arr;
}

static Value sys_exit_native(int argCount, Value* args) {
    int code = 0;
    if (argCount >= 1 && IS_NUMBER(args[0])) {
        code = (int)AS_NUMBER(args[0]);
    }
    exit(code);
    return val_nil(); // unreachable
}

static Value sys_platform_native(int argCount, Value* args) {
    (void)argCount; (void)args;
#if defined(__linux__)
    return val_string("linux");
#elif defined(__APPLE__)
    return val_string("darwin");
#elif defined(_WIN32)
    return val_string("windows");
#elif defined(PICO_BUILD)
    return val_string("pico");
#else
    return val_string("unknown");
#endif
}

static Value sys_getenv_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    const char* val = getenv(AS_STRING(args[0]));
    if (!val) return val_nil();
    return val_string(val);
}

static Value sys_clock_native(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_number((double)clock() / CLOCKS_PER_SEC);
}

static Value sys_sleep_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    double seconds = AS_NUMBER(args[0]);
    if (seconds > 0) {
        struct timespec ts;
        ts.tv_sec = (time_t)seconds;
        ts.tv_nsec = (long)((seconds - (double)ts.tv_sec) * 1e9);
        nanosleep(&ts, NULL);
    }
    return val_nil();
}

static Value sys_exec_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    const char* cmd = AS_STRING(args[0]);
    int result = system(cmd);
    return val_number(result);
}

Module* create_sys_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "sys");
    Environment* e = m->env;

    // args is a function that returns the array (so it's always current)
    env_define(e, "args", 4, val_native(sys_args_native));
    env_define(e, "exit", 4, val_native(sys_exit_native));
    env_define(e, "getenv", 6, val_native(sys_getenv_native));
    env_define(e, "clock", 5, val_native(sys_clock_native));
    env_define(e, "sleep", 5, val_native(sys_sleep_native));
    env_define(e, "exec", 4, val_native(sys_exec_native));

    // Constants
    env_define(e, "version", 7, val_string(SAGE_VERSION_STR));
    {
        Value plat = sys_platform_native(0, NULL);
        env_define(e, "platform", 8, plat);
    }

    return m;
}

// ============================================================================
// FAT MODULE
// ============================================================================

typedef struct {
    int valid;
    int fat_bits;
    uint32_t bytes_per_sector;
    uint32_t sectors_per_cluster;
    uint32_t reserved_sector_count;
    uint32_t fat_count;
    uint32_t root_entry_count;
    uint32_t total_sectors;
    uint32_t sectors_per_fat;
    uint32_t root_dir_sectors;
    uint32_t first_data_sector;
    uint32_t data_sector_count;
    uint32_t cluster_count;
    uint32_t root_cluster;
    uint32_t media_descriptor;
    char fs_type_label[16];
    char volume_label[16];
} FatBootInfo;

static uint16_t fat_le16(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t fat_le32(const uint8_t* p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static int fat_is_pow2(uint32_t x) {
    return x != 0 && (x & (x - 1)) == 0;
}

static void fat_copy_trimmed(char* dst, size_t dst_cap, const uint8_t* src, size_t src_len) {
    if (dst_cap == 0) return;
    size_t n = src_len;
    while (n > 0 && (src[n - 1] == ' ' || src[n - 1] == '\0')) {
        n--;
    }
    if (n >= dst_cap) n = dst_cap - 1;
    for (size_t i = 0; i < n; i++) {
        dst[i] = (char)src[i];
    }
    dst[n] = '\0';
}

static int fat_prefix_eq(const char* s, const char* prefix) {
    size_t n = strlen(prefix);
    return strncmp(s, prefix, n) == 0;
}

static void fat_parse_boot_info(const uint8_t* bytes, size_t len, FatBootInfo* info) {
    memset(info, 0, sizeof(*info));
    if (bytes == NULL || len < 64) {
        return;
    }

    info->bytes_per_sector = fat_le16(bytes + 11);
    info->sectors_per_cluster = bytes[13];
    info->reserved_sector_count = fat_le16(bytes + 14);
    info->fat_count = bytes[16];
    info->root_entry_count = fat_le16(bytes + 17);
    uint32_t total16 = fat_le16(bytes + 19);
    info->media_descriptor = bytes[21];
    uint32_t fat16 = fat_le16(bytes + 22);
    uint32_t total32 = fat_le32(bytes + 32);
    uint32_t fat32 = fat_le32(bytes + 36);
    info->root_cluster = fat_le32(bytes + 44);

    info->total_sectors = (total16 != 0) ? total16 : total32;
    info->sectors_per_fat = (fat16 != 0) ? fat16 : fat32;

    if (len >= 90) {
        if (info->root_entry_count == 0) {
            fat_copy_trimmed(info->volume_label, sizeof(info->volume_label), bytes + 71, 11);
            fat_copy_trimmed(info->fs_type_label, sizeof(info->fs_type_label), bytes + 82, 8);
        } else {
            fat_copy_trimmed(info->volume_label, sizeof(info->volume_label), bytes + 43, 11);
            fat_copy_trimmed(info->fs_type_label, sizeof(info->fs_type_label), bytes + 54, 8);
        }
    }

    if (!fat_is_pow2(info->bytes_per_sector) || info->bytes_per_sector < 128 || info->bytes_per_sector > 4096) {
        return;
    }
    if (!fat_is_pow2(info->sectors_per_cluster) || info->sectors_per_cluster == 0 || info->sectors_per_cluster > 128) {
        return;
    }
    if (info->reserved_sector_count == 0 || info->fat_count == 0 || info->sectors_per_fat == 0 || info->total_sectors == 0) {
        return;
    }

    uint32_t root_dir_sectors = (uint32_t)(((uint64_t)info->root_entry_count * 32u + (info->bytes_per_sector - 1u)) / info->bytes_per_sector);
    uint64_t first_data = (uint64_t)info->reserved_sector_count + ((uint64_t)info->fat_count * info->sectors_per_fat) + root_dir_sectors;
    if (first_data >= info->total_sectors) {
        return;
    }
    uint32_t data_sectors = (uint32_t)(info->total_sectors - first_data);
    uint32_t cluster_count = data_sectors / info->sectors_per_cluster;

    info->root_dir_sectors = root_dir_sectors;
    info->first_data_sector = (uint32_t)first_data;
    info->data_sector_count = data_sectors;
    info->cluster_count = cluster_count;

    // Include FAT8 for very small data regions as requested.
    if (cluster_count < 16) info->fat_bits = 8;
    else if (cluster_count < 4085) info->fat_bits = 12;
    else if (cluster_count < 65525) info->fat_bits = 16;
    else info->fat_bits = 32;

    // Let explicit filesystem labels refine the guess.
    if (fat_prefix_eq(info->fs_type_label, "FAT8")) info->fat_bits = 8;
    else if (fat_prefix_eq(info->fs_type_label, "FAT12")) info->fat_bits = 12;
    else if (fat_prefix_eq(info->fs_type_label, "FAT16")) info->fat_bits = 16;
    else if (fat_prefix_eq(info->fs_type_label, "FAT32")) info->fat_bits = 32;

    if (info->fat_bits == 32 && info->root_cluster == 0) {
        info->root_cluster = 2;
    }

    info->valid = 1;
}

static const char* fat_type_name_bits(int bits) {
    switch (bits) {
        case 8: return "FAT8";
        case 12: return "FAT12";
        case 16: return "FAT16";
        case 32: return "FAT32";
        default: return "UNKNOWN";
    }
}

static Value fat_boot_info_to_value(const FatBootInfo* info) {
    Value out = val_dict();
    dict_set(&out, "valid", val_bool(info->valid));
    dict_set(&out, "fat_bits", val_number((double)info->fat_bits));
    dict_set(&out, "fat_type", val_string(fat_type_name_bits(info->fat_bits)));
    dict_set(&out, "bytes_per_sector", val_number((double)info->bytes_per_sector));
    dict_set(&out, "sectors_per_cluster", val_number((double)info->sectors_per_cluster));
    dict_set(&out, "reserved_sector_count", val_number((double)info->reserved_sector_count));
    dict_set(&out, "fat_count", val_number((double)info->fat_count));
    dict_set(&out, "root_entry_count", val_number((double)info->root_entry_count));
    dict_set(&out, "total_sectors", val_number((double)info->total_sectors));
    dict_set(&out, "sectors_per_fat", val_number((double)info->sectors_per_fat));
    dict_set(&out, "root_dir_sectors", val_number((double)info->root_dir_sectors));
    dict_set(&out, "first_data_sector", val_number((double)info->first_data_sector));
    dict_set(&out, "data_sector_count", val_number((double)info->data_sector_count));
    dict_set(&out, "cluster_count", val_number((double)info->cluster_count));
    dict_set(&out, "root_cluster", val_number((double)info->root_cluster));
    dict_set(&out, "media_descriptor", val_number((double)info->media_descriptor));
    dict_set(&out, "fs_type_label", val_string(info->fs_type_label));
    dict_set(&out, "volume_label", val_string(info->volume_label));
    return out;
}

static Value fat_parse_boot_sector_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_ARRAY(args[0])) return val_nil();
    ArrayValue* arr = AS_ARRAY(args[0]);
    if (arr == NULL || arr->count <= 0 || arr->count > 1024 * 1024) return val_nil();

    uint8_t* bytes = SAGE_ALLOC((size_t)arr->count);
    for (int i = 0; i < arr->count; i++) {
        Value v = arr->elements[i];
        if (!IS_NUMBER(v)) {
            free(bytes);
            return val_nil();
        }
        double d = AS_NUMBER(v);
        if (d < 0.0 || d > 255.0) {
            free(bytes);
            return val_nil();
        }
        bytes[i] = (uint8_t)((unsigned int)d & 0xffu);
    }

    FatBootInfo info;
    fat_parse_boot_info(bytes, (size_t)arr->count, &info);
    free(bytes);
    return fat_boot_info_to_value(&info);
}

static Value fat_probe_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_STRING(args[0])) return val_nil();
    const char* path = AS_STRING(args[0]);
    FILE* f = fopen(path, "rb");
    if (!f) return val_nil();

    uint8_t sector[4096];
    size_t nread = fread(sector, 1, sizeof(sector), f);
    fclose(f);

    FatBootInfo info;
    fat_parse_boot_info(sector, nread, &info);
    Value out = fat_boot_info_to_value(&info);
    dict_set(&out, "source_path", val_string(path));
    return out;
}

static int fat_dict_number(Value* dict, const char* key, double* out) {
    if (dict == NULL || out == NULL || !IS_DICT(*dict)) return 0;
    Value v = dict_get(dict, key);
    if (!IS_NUMBER(v)) return 0;
    *out = AS_NUMBER(v);
    return 1;
}

static Value fat_cluster_to_lba_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_DICT(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    double first_data = 0.0;
    double spc = 0.0;
    if (!fat_dict_number(&args[0], "first_data_sector", &first_data) ||
        !fat_dict_number(&args[0], "sectors_per_cluster", &spc)) {
        return val_nil();
    }
    double cluster = AS_NUMBER(args[1]);
    if (cluster < 2.0 || spc <= 0.0) return val_nil();
    double lba = first_data + (cluster - 2.0) * spc;
    return val_number(lba);
}

static Value fat_fat_entry_offset_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_DICT(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    double fat_bits = 0.0;
    if (!fat_dict_number(&args[0], "fat_bits", &fat_bits)) return val_nil();
    double cluster = AS_NUMBER(args[1]);
    if (cluster < 0.0) return val_nil();

    uint32_t bits = (uint32_t)fat_bits;
    uint32_t cl = (uint32_t)cluster;
    uint32_t offset = 0;
    if (bits == 12) {
        offset = (cl * 3u) / 2u;
    } else {
        offset = (uint32_t)(((uint64_t)cl * (uint64_t)bits) / 8u);
    }

    Value out = val_dict();
    dict_set(&out, "byte_offset", val_number((double)offset));
    dict_set(&out, "is_odd", val_bool((bits == 12) ? (cl & 1u) : 0));
    dict_set(&out, "fat_bits", val_number((double)bits));
    return out;
}

Module* create_fat_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "fat");
    Environment* e = m->env;

    env_define(e, "parse_boot_sector", 17, val_native(fat_parse_boot_sector_native));
    env_define(e, "probe", 5, val_native(fat_probe_native));
    env_define(e, "cluster_to_lba", 14, val_native(fat_cluster_to_lba_native));
    env_define(e, "fat_entry_offset", 16, val_native(fat_fat_entry_offset_native));

    env_define(e, "FAT8", 4, val_number(8));
    env_define(e, "FAT12", 5, val_number(12));
    env_define(e, "FAT16", 5, val_number(16));
    env_define(e, "FAT32", 5, val_number(32));

    return m;
}

// ============================================================================
// THREAD MODULE
// ============================================================================

// Thread entry data
typedef struct {
    FunctionValue* func;
    Value* args;
    int arg_count;
    Value result;
} SageThreadData;

static void* sage_thread_entry(void* data) {
    SageThreadData* td = (SageThreadData*)data;
    ProcStmt* proc = (ProcStmt*)td->func->proc;

    // Create execution scope from function closure
    gc_lock();
    Env* scope = env_create(td->func->closure);
    for (int i = 0; i < td->arg_count && i < proc->param_count; i++) {
        Token paramName = proc->params[i];
        env_define(scope, paramName.start, paramName.length, td->args[i]);
    }
    gc_unlock();

    // Execute the function body
    ExecResult res = interpret(proc->body, scope);
    td->result = res.value;

    return NULL;
}

// thread.spawn(func, arg1, arg2, ...) -> thread handle
Value thread_spawn_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_FUNCTION(args[0])) {
        fprintf(stderr, "Runtime Error: thread.spawn requires a function argument.\n");
        return val_nil();
    }

    FunctionValue* func = args[0].as.function;
    if (func->proc == NULL || func->is_vm) {
        fprintf(stderr, "Runtime Error: thread.spawn requires a non-bytecode function.\n");
        return val_nil();
    }
    int nargs = argCount - 1;

    // Allocate thread data
    SageThreadData* td = SAGE_ALLOC(sizeof(SageThreadData));
    td->func = func;
    td->arg_count = nargs;
    td->result = val_nil();
    if (nargs > 0) {
        td->args = SAGE_ALLOC(sizeof(Value) * (size_t)nargs);
        memcpy(td->args, args + 1, sizeof(Value) * (size_t)nargs);
    } else {
        td->args = NULL;
    }

    // Create thread
    sage_thread_t* handle = SAGE_ALLOC(sizeof(sage_thread_t));
    int err = sage_thread_create(handle, sage_thread_entry, td);
    if (err != 0) {
        fprintf(stderr, "Runtime Error: Failed to create thread (error %d).\n", err);
        free(td->args);
        free(td);
        free(handle);
        return val_nil();
    }

    // Create thread value
    ThreadValue* tv = SAGE_ALLOC(sizeof(ThreadValue));
    tv->handle = handle;
    tv->data = td;
    tv->joined = 0;

    return val_thread(tv);
}

// thread.join(handle) -> result value
static Value thread_join_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_THREAD(args[0])) {
        fprintf(stderr, "Runtime Error: thread.join requires a thread handle.\n");
        return val_nil();
    }

    ThreadValue* tv = AS_THREAD(args[0]);
    if (tv->joined) {
        // Already joined, return cached result
        SageThreadData* td = (SageThreadData*)tv->data;
        return td->result;
    }

    sage_thread_t* handle = (sage_thread_t*)tv->handle;
    sage_thread_join(*handle, NULL);
    tv->joined = 1;

    SageThreadData* td = (SageThreadData*)tv->data;
    Value result = td->result;
    // Free thread resources
    free(td->args);
    free(td);
    free(handle);
    tv->data = NULL;
    tv->handle = NULL;
    return result;
}

// thread.mutex() -> mutex handle
static Value thread_mutex_native(int argCount, Value* args) {
    (void)argCount; (void)args;

    sage_mutex_t* mtx = SAGE_ALLOC(sizeof(sage_mutex_t));
    sage_mutex_init(mtx);

    MutexValue* mv = SAGE_ALLOC(sizeof(MutexValue));
    mv->handle = mtx;

    return val_mutex(mv);
}

// thread.lock(mutex)
static Value thread_lock_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_MUTEX(args[0])) {
        fprintf(stderr, "Runtime Error: thread.lock requires a mutex.\n");
        return val_nil();
    }
    sage_mutex_t* mtx = (sage_mutex_t*)AS_MUTEX(args[0])->handle;
    sage_mutex_lock(mtx);
    return val_nil();
}

// thread.unlock(mutex)
static Value thread_unlock_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_MUTEX(args[0])) {
        fprintf(stderr, "Runtime Error: thread.unlock requires a mutex.\n");
        return val_nil();
    }
    sage_mutex_t* mtx = (sage_mutex_t*)AS_MUTEX(args[0])->handle;
    sage_mutex_unlock(mtx);
    return val_nil();
}

// thread.sleep(seconds)
static Value thread_sleep_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_NUMBER(args[0])) return val_nil();
    double seconds = AS_NUMBER(args[0]);
    sage_sleep_secs(seconds);
    return val_nil();
}

// thread.id() -> current thread id as number
static Value thread_id_native(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_number((double)sage_thread_id());
}

Module* create_thread_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "thread");
    Environment* e = m->env;

    env_define(e, "spawn", 5, val_native(thread_spawn_native));
    env_define(e, "join", 4, val_native(thread_join_native));
    env_define(e, "mutex", 5, val_native(thread_mutex_native));
    env_define(e, "lock", 4, val_native(thread_lock_native));
    env_define(e, "unlock", 6, val_native(thread_unlock_native));
    env_define(e, "sleep", 5, val_native(thread_sleep_native));
    env_define(e, "id", 2, val_native(thread_id_native));

    return m;
}
