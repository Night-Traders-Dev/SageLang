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
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>

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
    env_define(e, "e", 1, val_number(2.71828182845904523536));
    env_define(e, "inf", 3, val_number(INFINITY));
    env_define(e, "nan", 3, val_number(NAN));
    env_define(e, "tau", 3, val_number(6.28318530717958647692));

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

Module* create_io_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "io");
    Environment* e = m->env;

    env_define(e, "readfile", 8, val_native(io_readfile_native));
    env_define(e, "writefile", 9, val_native(io_writefile_native));
    env_define(e, "appendfile", 10, val_native(io_appendfile_native));
    env_define(e, "exists", 6, val_native(io_exists_native));
    env_define(e, "remove", 6, val_native(io_remove_native));
    env_define(e, "isdir", 5, val_native(io_isdir_native));
    env_define(e, "filesize", 8, val_native(io_filesize_native));

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
    Value arr = val_array();
    for (int i = 0; i < s_argc; i++) {
        array_push(&arr, val_string(s_argv[i]));
    }
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

Module* create_sys_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "sys");
    Environment* e = m->env;

    // args is a function that returns the array (so it's always current)
    env_define(e, "args", 4, val_native(sys_args_native));
    env_define(e, "exit", 4, val_native(sys_exit_native));
    env_define(e, "getenv", 6, val_native(sys_getenv_native));
    env_define(e, "clock", 5, val_native(sys_clock_native));
    env_define(e, "sleep", 5, val_native(sys_sleep_native));

    // Constants
    env_define(e, "version", 7, val_string("0.10.0"));
    {
        Value plat = sys_platform_native(0, NULL);
        env_define(e, "platform", 8, plat);
    }

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
    pthread_t* handle = SAGE_ALLOC(sizeof(pthread_t));
    int err = pthread_create(handle, NULL, sage_thread_entry, td);
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

    pthread_t* handle = (pthread_t*)tv->handle;
    pthread_join(*handle, NULL);
    tv->joined = 1;

    SageThreadData* td = (SageThreadData*)tv->data;
    return td->result;
}

// thread.mutex() -> mutex handle
static Value thread_mutex_native(int argCount, Value* args) {
    (void)argCount; (void)args;

    pthread_mutex_t* mtx = SAGE_ALLOC(sizeof(pthread_mutex_t));
    pthread_mutex_init(mtx, NULL);

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
    pthread_mutex_t* mtx = (pthread_mutex_t*)AS_MUTEX(args[0])->handle;
    pthread_mutex_lock(mtx);
    return val_nil();
}

// thread.unlock(mutex)
static Value thread_unlock_native(int argCount, Value* args) {
    if (argCount < 1 || !IS_MUTEX(args[0])) {
        fprintf(stderr, "Runtime Error: thread.unlock requires a mutex.\n");
        return val_nil();
    }
    pthread_mutex_t* mtx = (pthread_mutex_t*)AS_MUTEX(args[0])->handle;
    pthread_mutex_unlock(mtx);
    return val_nil();
}

// thread.sleep(seconds)
static Value thread_sleep_native(int argCount, Value* args) {
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

// thread.id() -> current thread id as number
static Value thread_id_native(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_number((double)(uintptr_t)pthread_self());
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
