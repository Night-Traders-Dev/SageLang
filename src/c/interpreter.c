#define _GNU_SOURCE   // for mkstemps
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>    // isalnum
#include <stdint.h>   // uintptr_t
#include <math.h>     // isinf, isnan
#include <unistd.h>   // getpid, unlink
#include "sage_thread.h"  // Phase 11: async/await thread joining
#ifndef SAGE_NO_FFI
#include <dlfcn.h>    // Phase 9: FFI (dlopen, dlsym, dlclose)
#endif
#include "interpreter.h"
#include "token.h"
#include "env.h"
#include "value.h"
#include "gc.h"
#include "ast.h"
#include "module.h"  // Phase 8: Module system
#include "repl.h"    // Phase 12: REPL error recovery

// Helper macro for creating normal expression results
#define EVAL_RESULT(v) ((ExecResult){ (v), 0, 0, 0, 0, val_nil(), 0, NULL })
#define EVAL_EXCEPTION(exc) ((ExecResult){ val_nil(), 0, 0, 0, 1, (exc), 0, NULL })
#define RESULT_NORMAL(v) ((ExecResult){ (v), 0, 0, 0, 0, val_nil(), 0, NULL })

Environment* g_global_env = NULL;
Environment* g_gc_root_env = NULL;
static Stmt* g_generator_resume_target = NULL;

// Recursion depth tracking to prevent stack overflow
#define MAX_RECURSION_DEPTH 1000
// Maximum loop iterations to prevent hangs and stack exhaustion
#define MAX_LOOP_ITERATIONS 1000000
#if SAGE_PLATFORM_PICO
static int g_recursion_depth = 0;  // No TLS on Cortex-M0+
#else
static __thread int g_recursion_depth = 0;
#endif

static int stmt_contains_target(Stmt* stmt, Stmt* target) {
    if (stmt == NULL || target == NULL) return 0;
    if (stmt == target) return 1;

    switch (stmt->type) {
        case STMT_BLOCK:
            for (Stmt* current = stmt->as.block.statements; current != NULL; current = current->next) {
                if (stmt_contains_target(current, target)) return 1;
            }
            return 0;
        case STMT_IF:
            return stmt_contains_target(stmt->as.if_stmt.then_branch, target) ||
                   stmt_contains_target(stmt->as.if_stmt.else_branch, target);
        case STMT_WHILE:
            return stmt_contains_target(stmt->as.while_stmt.body, target);
        case STMT_FOR:
            return stmt_contains_target(stmt->as.for_stmt.body, target);
        case STMT_TRY: {
            if (stmt_contains_target(stmt->as.try_stmt.try_block, target) ||
                stmt_contains_target(stmt->as.try_stmt.finally_block, target)) {
                return 1;
            }
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                if (stmt_contains_target(stmt->as.try_stmt.catches[i]->body, target)) {
                    return 1;
                }
            }
            return 0;
        }
        default:
            return 0;
    }
}

// --- Native Functions ---

static Value clock_native(int argCount, Value* args) {
    return val_number((double)clock() / CLOCKS_PER_SEC);
}

static Value input_native(int argCount, Value* args) {
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') buffer[len-1] = '\0';

        char* str = SAGE_ALLOC(len + 1);
        memcpy(str, buffer, len + 1);
        return val_string_take(str);
    }
    return val_nil();
}

static Value tonumber_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (IS_NUMBER(args[0])) return args[0];
    if (IS_STRING(args[0])) {
        return val_number(strtod(AS_STRING(args[0]), NULL));
    }
    return val_nil();
}

// PHASE 7: str() function for number-to-string conversion
static Value str_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    
    char buffer[256];
    if (IS_NUMBER(args[0])) {
        double n = AS_NUMBER(args[0]);
        if (n == (long long)n && n >= -9007199254740992.0 && n <= 9007199254740992.0) {
            snprintf(buffer, sizeof(buffer), "%lld", (long long)n);
        } else {
            snprintf(buffer, sizeof(buffer), "%g", n);
        }
        size_t slen = strlen(buffer);
        char* str = SAGE_ALLOC(slen + 1);
        memcpy(str, buffer, slen + 1);
        return val_string_take(str);
    }
    if (IS_STRING(args[0])) {
        return args[0];
    }
    if (IS_BOOL(args[0])) {
        char* str = AS_BOOL(args[0]) ? "true" : "false";
        size_t slen = strlen(str);
        char* result = SAGE_ALLOC(slen + 1);
        memcpy(result, str, slen + 1);
        return val_string_take(result);
    }
    if (args[0].type == VAL_ARRAY) {
        ArrayValue* arr = args[0].as.array;
        // Estimate size: "[" + elements + "]"
        size_t buf_size = 1024;
        char* buf = SAGE_ALLOC(buf_size);
        size_t pos = 0;
        buf[pos++] = '[';
        for (int i = 0; i < arr->count && pos < buf_size - 32; i++) {
            if (i > 0) { buf[pos++] = ','; buf[pos++] = ' '; }
            Value elem = arr->elements[i];
            if (IS_NUMBER(elem)) {
                double en = AS_NUMBER(elem);
                if (en == (long long)en && en >= -9007199254740992.0 && en <= 9007199254740992.0) {
                    pos += snprintf(buf + pos, buf_size - pos, "%lld", (long long)en);
                } else {
                    pos += snprintf(buf + pos, buf_size - pos, "%g", en);
                }
            } else if (IS_STRING(elem)) {
                pos += snprintf(buf + pos, buf_size - pos, "%s", AS_STRING(elem));
            } else if (IS_BOOL(elem)) {
                pos += snprintf(buf + pos, buf_size - pos, "%s", AS_BOOL(elem) ? "true" : "false");
            } else if (elem.type == VAL_NIL) {
                pos += snprintf(buf + pos, buf_size - pos, "nil");
            } else {
                pos += snprintf(buf + pos, buf_size - pos, "<%d>", elem.type);
            }
        }
        if (arr->count > 0 && pos >= buf_size - 32) {
            pos += snprintf(buf + pos, buf_size - pos, "...");
        }
        buf[pos++] = ']';
        buf[pos] = '\0';
        return val_string_take(buf);
    }
    if (args[0].type == VAL_NIL) {
        return val_string("nil");
    }
    // For other types, return a type description
    const char* type_names[] = {"number","bool","nil","string","function","native",
                                "array","dict","tuple","class","instance","module",
                                "exception","generator","clib","pointer","thread","mutex"};
    int t = args[0].type;
    if (t >= 0 && t <= 17) {
        snprintf(buffer, sizeof(buffer), "<%s>", type_names[t]);
    } else {
        snprintf(buffer, sizeof(buffer), "<unknown:%d>", t);
    }
    return val_string(buffer);
}

static Value len_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (args[0].type == VAL_ARRAY) {
        return val_number(args[0].as.array->count);
    }
    if (args[0].type == VAL_STRING) {
        return val_number(strlen(AS_STRING(args[0])));
    }
    if (args[0].type == VAL_TUPLE) {
        return val_number(args[0].as.tuple->count);
    }
    if (args[0].type == VAL_DICT) {
        return val_number(args[0].as.dict->count);
    }
    return val_nil();
}

static Value push_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (args[0].type != VAL_ARRAY) return val_nil();
    array_push(&args[0], args[1]);
    return val_nil();
}

// array_extend(target, source) - append all elements of source to target (native speed)
static Value array_extend_native(int argCount, Value* args) {
    if (argCount != 2 || args[0].type != VAL_ARRAY || args[1].type != VAL_ARRAY) return val_nil();
    ArrayValue* target = args[0].as.array;
    ArrayValue* source = args[1].as.array;
    int new_count = target->count + source->count;
    if (new_count > target->capacity) {
        size_t old_bytes = sizeof(Value) * (size_t)target->capacity;
        while (target->capacity < new_count) target->capacity = target->capacity == 0 ? 8 : target->capacity * 2;
        target->elements = SAGE_REALLOC(target->elements, sizeof(Value) * target->capacity);
        gc_track_external_resize(old_bytes, sizeof(Value) * (size_t)target->capacity);
    }
    memcpy(target->elements + target->count, source->elements, sizeof(Value) * source->count);
    target->count = new_count;
    return val_nil();
}

static Value pop_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (args[0].type != VAL_ARRAY) return val_nil();
    
    ArrayValue* a = args[0].as.array;
    if (a->count == 0) return val_nil();
    
    Value result = a->elements[a->count - 1];
    a->count--;
    return result;
}

// build_quad_verts(quads_array) -> flat float array of vertices
// Each quad is a dict with x,y,w,h,color (array of 4 floats)
// Output: 6 verts per quad, each vert = [px,py,u,v,r,g,b,a] = 8 floats
static Value build_quad_verts_native(int argCount, Value* args) {
    if (argCount != 1 || args[0].type != VAL_ARRAY) return val_nil();
    ArrayValue* quads = args[0].as.array;
    int quad_count = quads->count;
    int vert_count = quad_count * 6;
    int float_count = vert_count * 8;

    // Pre-allocate output array
    ArrayValue* out = SAGE_ALLOC(sizeof(ArrayValue));
    out->count = 0;
    out->capacity = float_count;
    out->elements = SAGE_ALLOC(sizeof(Value) * float_count);

    for (int i = 0; i < quad_count; i++) {
        Value q = quads->elements[i];
        if (q.type != VAL_DICT) continue;

        // Extract quad properties via dict_get
        Value vx = dict_get(&q, "x");
        Value vy = dict_get(&q, "y");
        Value vw = dict_get(&q, "w");
        Value vh = dict_get(&q, "h");
        Value vc = dict_get(&q, "color");
        if (!IS_NUMBER(vx) || !IS_NUMBER(vy)) continue;

        double x0 = AS_NUMBER(vx), y0 = AS_NUMBER(vy);
        double w = IS_NUMBER(vw) ? AS_NUMBER(vw) : 0;
        double h = IS_NUMBER(vh) ? AS_NUMBER(vh) : 0;
        double x1 = x0 + w, y1 = y0 + h;

        double cr = 1, cg = 1, cb = 1, ca = 1;
        if (vc.type == VAL_ARRAY && vc.as.array->count >= 4) {
            cr = AS_NUMBER(vc.as.array->elements[0]);
            cg = AS_NUMBER(vc.as.array->elements[1]);
            cb = AS_NUMBER(vc.as.array->elements[2]);
            ca = AS_NUMBER(vc.as.array->elements[3]);
        }

        // 6 vertices per quad (2 triangles)
        // Vertex = px,py,u,v,r,g,b,a
        #define EMIT_VERT(px,py,u,v) do { \
            out->elements[out->count++] = val_number(px); \
            out->elements[out->count++] = val_number(py); \
            out->elements[out->count++] = val_number(u);  \
            out->elements[out->count++] = val_number(v);  \
            out->elements[out->count++] = val_number(cr);  \
            out->elements[out->count++] = val_number(cg);  \
            out->elements[out->count++] = val_number(cb);  \
            out->elements[out->count++] = val_number(ca);  \
        } while(0)

        EMIT_VERT(x0, y0, 0, 0);
        EMIT_VERT(x1, y0, 1, 0);
        EMIT_VERT(x1, y1, 1, 1);
        EMIT_VERT(x0, y0, 0, 0);
        EMIT_VERT(x1, y1, 1, 1);
        EMIT_VERT(x0, y1, 0, 1);
        #undef EMIT_VERT
    }

    Value result;
    result.type = VAL_ARRAY;
    result.as.array = out;
    return result;
}

// build_line_quads(line_verts, thickness, color_r, color_g, color_b, color_a) -> quad array
// Takes line segments [x1,y1,x2,y2,...] and produces quads suitable for build_quad_verts
static Value build_line_quads_native(int argCount, Value* args) {
    if (argCount < 2 || args[0].type != VAL_ARRAY) return val_nil();
    ArrayValue* lines = args[0].as.array;
    double thickness = AS_NUMBER(args[1]);
    double cr = argCount > 2 ? AS_NUMBER(args[2]) : 1.0;
    double cg = argCount > 3 ? AS_NUMBER(args[3]) : 1.0;
    double cb = argCount > 4 ? AS_NUMBER(args[4]) : 1.0;
    double ca = argCount > 5 ? AS_NUMBER(args[5]) : 1.0;

    int seg_count = lines->count / 4;
    // Output: array of dicts, each with x,y,w,h,color
    ArrayValue* out = SAGE_ALLOC(sizeof(ArrayValue));
    out->count = 0;
    out->capacity = seg_count;
    out->elements = SAGE_ALLOC(sizeof(Value) * seg_count);

    // Color array (shared)
    ArrayValue* color = SAGE_ALLOC(sizeof(ArrayValue));
    color->count = 4;
    color->capacity = 4;
    color->elements = SAGE_ALLOC(sizeof(Value) * 4);
    color->elements[0] = val_number(cr);
    color->elements[1] = val_number(cg);
    color->elements[2] = val_number(cb);
    color->elements[3] = val_number(ca);
    Value color_val;
    color_val.type = VAL_ARRAY;
    color_val.as.array = color;

    double half = thickness * 0.5;

    for (int i = 0; i + 3 < lines->count; i += 4) {
        double x1 = AS_NUMBER(lines->elements[i]);
        double y1 = AS_NUMBER(lines->elements[i+1]);
        double x2 = AS_NUMBER(lines->elements[i+2]);
        double y2 = AS_NUMBER(lines->elements[i+3]);

        // For each line, create an axis-aligned bounding quad
        double minx = x1 < x2 ? x1 : x2;
        double miny = y1 < y2 ? y1 : y2;
        double maxx = x1 > x2 ? x1 : x2;
        double maxy = y1 > y2 ? y1 : y2;
        double w = maxx - minx;
        double h = maxy - miny;
        if (w < thickness) { minx -= half; w = thickness; }
        if (h < thickness) { miny -= half; h = thickness; }

        Value quad_dict = val_dict();
        dict_set(&quad_dict, "x", val_number(minx));
        dict_set(&quad_dict, "y", val_number(miny));
        dict_set(&quad_dict, "w", val_number(w));
        dict_set(&quad_dict, "h", val_number(h));
        dict_set(&quad_dict, "color", color_val);

        if (out->count >= out->capacity) {
            out->capacity = out->capacity * 2 + 1;
            out->elements = SAGE_REALLOC(out->elements, sizeof(Value) * out->capacity);
        }
        out->elements[out->count++] = quad_dict;
    }

    Value result;
    result.type = VAL_ARRAY;
    result.as.array = out;
    return result;
}

static Value range_native(int argCount, Value* args) {
    if (argCount < 1 || argCount > 2) return val_nil();
    
    int start = 0, end = 0;
    
    if (argCount == 1) {
        if (!IS_NUMBER(args[0])) return val_nil();
        end = (int)AS_NUMBER(args[0]);
    } else {
        if (!IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
        start = (int)AS_NUMBER(args[0]);
        end = (int)AS_NUMBER(args[1]);
    }

    Value arr = val_array();
    for (int i = start; i < end; i++) {
        array_push(&arr, val_number(i));
    }
    return arr;
}

// String functions
static Value split_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    return string_split(AS_STRING(args[0]), AS_STRING(args[1]));
}

static Value join_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_ARRAY(args[0]) || !IS_STRING(args[1])) return val_nil();
    return string_join(&args[0], AS_STRING(args[1]));
}

static Value replace_native(int argCount, Value* args) {
    if (argCount != 3) return val_nil();
    if (!IS_STRING(args[0]) || !IS_STRING(args[1]) || !IS_STRING(args[2])) return val_nil();
    char* result = string_replace(AS_STRING(args[0]), AS_STRING(args[1]), AS_STRING(args[2]));
    return val_string_take(result);
}

static Value upper_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_STRING(args[0])) return val_nil();
    char* result = string_upper(AS_STRING(args[0]));
    return val_string_take(result);
}

static Value lower_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_STRING(args[0])) return val_nil();
    char* result = string_lower(AS_STRING(args[0]));
    return val_string_take(result);
}

static Value strip_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_STRING(args[0])) return val_nil();
    char* result = string_strip(AS_STRING(args[0]));
    return val_string_take(result);
}

// type(val) -> string name of type
static Value type_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    switch (args[0].type) {
        case VAL_NIL: return val_string("nil");
        case VAL_NUMBER: return val_string("number");
        case VAL_BOOL: return val_string("bool");
        case VAL_STRING: return val_string("string");
        case VAL_ARRAY: return val_string("array");
        case VAL_DICT: return val_string("dict");
        case VAL_FUNCTION: return val_string("function");
        case VAL_NATIVE: return val_string("native");
        case VAL_INSTANCE: return val_string("instance");
        case VAL_TUPLE: return val_string("tuple");
        case VAL_GENERATOR: return val_string("generator");
        default: return val_string("unknown");
    }
}

// chr(n) -> single-character string from ASCII code
static Value chr_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_NUMBER(args[0])) return val_nil();
    int code = (int)AS_NUMBER(args[0]);
    if (code < 0 || code > 127) return val_nil();
    char* s = SAGE_ALLOC(2);
    s[0] = (char)code;
    s[1] = '\0';
    return val_string_take(s);
}

// ord(s) -> ASCII code of first character
static Value ord_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_STRING(args[0])) return val_nil();
    char* s = AS_STRING(args[0]);
    if (s[0] == '\0') return val_nil();
    return val_number((double)(unsigned char)s[0]);
}

// startswith(s, prefix) -> bool
static Value startswith_native(int argCount, Value* args) {
    if (argCount != 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    char* s = AS_STRING(args[0]);
    char* prefix = AS_STRING(args[1]);
    size_t plen = strlen(prefix);
    return val_bool(strncmp(s, prefix, plen) == 0);
}

// endswith(s, suffix) -> bool
static Value endswith_native(int argCount, Value* args) {
    if (argCount != 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    char* s = AS_STRING(args[0]);
    char* suffix = AS_STRING(args[1]);
    size_t slen = strlen(s);
    size_t suflen = strlen(suffix);
    if (suflen > slen) return val_bool(0);
    return val_bool(strcmp(s + slen - suflen, suffix) == 0);
}

// contains(s, sub) -> bool
static Value contains_native(int argCount, Value* args) {
    if (argCount != 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    return val_bool(strstr(AS_STRING(args[0]), AS_STRING(args[1])) != NULL);
}

// indexof(s, sub) -> number (-1 if not found)
static Value indexof_native(int argCount, Value* args) {
    if (argCount != 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    char* s = AS_STRING(args[0]);
    char* sub = AS_STRING(args[1]);
    char* found = strstr(s, sub);
    if (found == NULL) return val_number(-1);
    return val_number((double)(found - s));
}

static Value slice_native(int argCount, Value* args) {
    if (argCount != 3) return val_nil();
    if (!IS_NUMBER(args[1]) || !IS_NUMBER(args[2])) return val_nil();
    int start = (int)AS_NUMBER(args[1]);
    int end = (int)AS_NUMBER(args[2]);
    if (IS_ARRAY(args[0])) {
        return array_slice(&args[0], start, end);
    }
    if (IS_STRING(args[0])) {
        char* str = AS_STRING(args[0]);
        int slen = (int)strlen(str);
        if (start < 0) start += slen;
        if (end < 0) end += slen;
        if (start < 0) start = 0;
        if (end > slen) end = slen;
        if (start >= end) return val_string(SAGE_STRDUP(""));
        int len = end - start;
        char* result = SAGE_ALLOC(len + 1);
        memcpy(result, str + start, len);
        result[len] = '\0';
        return val_string(result);
    }
    return val_nil();
}

// Dictionary functions
static Value dict_keys_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_DICT(args[0])) return val_nil();
    return dict_keys(&args[0]);
}

static Value dict_values_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_DICT(args[0])) return val_nil();
    return dict_values(&args[0]);
}

static Value dict_has_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_DICT(args[0]) || !IS_STRING(args[1])) return val_nil();
    return val_bool(dict_has(&args[0], AS_STRING(args[1])));
}

static Value dict_delete_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_DICT(args[0]) || !IS_STRING(args[1])) return val_nil();
    dict_delete(&args[0], AS_STRING(args[1]));
    return val_nil();
}

// GC functions
static Value gc_collect_native(int argCount, Value* args) {
    gc_collect();
    return val_nil();
}

static Value gc_stats_native(int argCount, Value* args) {
    GCStats stats = gc_get_stats();
    gc_pin();
    Value dict = val_dict();
    
    dict_set(&dict, "bytes_allocated", val_number(stats.bytes_allocated));
    dict_set(&dict, "current_bytes", val_number(stats.current_bytes));
    dict_set(&dict, "num_objects", val_number(stats.num_objects));
    dict_set(&dict, "collections", val_number(stats.collections));
    dict_set(&dict, "objects_freed", val_number(stats.objects_freed));
    dict_set(&dict, "next_gc", val_number(stats.next_gc));
    dict_set(&dict, "next_gc_bytes", val_number(stats.next_gc_bytes));
    
    gc_unpin();
    return dict;
}

static Value gc_collections_native(int argCount, Value* args) {
    GCStats stats = gc_get_stats();
    return val_number(stats.collections);
}

static Value gc_enable_native(int argCount, Value* args) {
    gc_enable();
    return val_nil();
}

static Value gc_disable_native(int argCount, Value* args) {
    gc_disable();
    return val_nil();
}

// PHASE 7: Generator next() function - Forward declaration (REMOVED static keyword)
ExecResult interpret(Stmt* stmt, Env* env);

static Value native_next(int arg_count, Value* args) {
    if (arg_count != 1) {
        fprintf(stderr, "next() expects 1 argument\n");
        sage_error_exit();
    }
    if (!IS_GENERATOR(args[0])) {
        fprintf(stderr, "next() expects a generator\n");
        sage_error_exit();
    }
    
    GeneratorValue* gen = AS_GENERATOR(args[0]);
    if (gen->is_exhausted) return val_nil();
    
    // Initialize generator environment on first call
    if (!gen->is_started) {
        gen->gen_env = env_create(gen->closure);
        gen->is_started = 1;
    }

    if (gen->has_resume_target && gen->current_stmt == NULL) {
        gen->is_exhausted = 1;
        return val_nil();
    }

    g_generator_resume_target = gen->has_resume_target ? (Stmt*)gen->current_stmt : NULL;
    ExecResult result = interpret((Stmt*)gen->body, gen->gen_env);
    g_generator_resume_target = NULL;
    
    if (result.is_yielding) {
        gen->current_stmt = result.next_stmt;
        gen->has_resume_target = 1;
        return result.value;
    }
    
    if (result.is_returning) {
        gen->is_exhausted = 1;
        return result.value;
    }
    
    if (result.is_throwing) {
        gen->is_exhausted = 1;
        fprintf(stderr, "Exception in generator\n");
        sage_error_exit();
    }
    
    // Generator completed without yielding or returning
    gen->is_exhausted = 1;
    gen->has_resume_target = 0;
    return val_nil();
}

// ============================================================================
// Phase 9: FFI Functions (requires dlfcn.h - disabled with SAGE_NO_FFI)
// ============================================================================

#ifndef SAGE_NO_FFI

// ffi_open("libname.so") -> CLib handle
static Value ffi_open_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_STRING(args[0])) {
        fprintf(stderr, "ffi_open() expects 1 string argument (library path).\n");
        return val_nil();
    }
    const char* lib_name = AS_STRING(args[0]);
    void* handle = dlopen(lib_name, RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "ffi_open: %s\n", dlerror());
        return val_nil();
    }
    return val_clib(handle, lib_name);
}

// ffi_close(lib) -> nil
static Value ffi_close_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_CLIB(args[0])) {
        fprintf(stderr, "ffi_close() expects 1 clib argument.\n");
        return val_nil();
    }
    CLibValue* lib = AS_CLIB(args[0]);
    if (lib->handle) {
        dlclose(lib->handle);
        lib->handle = NULL;
    }
    return val_nil();
}

// ffi_call(lib, "func_name", "return_type", [args...])
// Supported return types: "double", "int", "void", "string"
// Args are automatically marshaled from Sage values
static Value ffi_call_native(int argCount, Value* args) {
    if (argCount < 3 || argCount > 4) {
        fprintf(stderr, "ffi_call() expects 3-4 arguments: (lib, func_name, return_type, [args]).\n");
        return val_nil();
    }
    if (!IS_CLIB(args[0])) {
        fprintf(stderr, "ffi_call(): first argument must be a clib handle.\n");
        return val_nil();
    }
    if (!IS_STRING(args[1])) {
        fprintf(stderr, "ffi_call(): second argument must be function name string.\n");
        return val_nil();
    }
    if (!IS_STRING(args[2])) {
        fprintf(stderr, "ffi_call(): third argument must be return type string.\n");
        return val_nil();
    }

    CLibValue* lib = AS_CLIB(args[0]);
    if (!lib->handle) {
        fprintf(stderr, "ffi_call(): library handle is closed.\n");
        return val_nil();
    }

    const char* func_name = AS_STRING(args[1]);
    const char* ret_type = AS_STRING(args[2]);

    // Look up symbol
    dlerror(); // Clear errors
    void* sym = dlsym(lib->handle, func_name);
    char* error = dlerror();
    if (error) {
        fprintf(stderr, "ffi_call: %s\n", error);
        return val_nil();
    }

    // Get args array
    int call_argc = 0;
    ArrayValue* call_args = NULL;
    if (argCount == 4) {
        if (!IS_ARRAY(args[3])) {
            fprintf(stderr, "ffi_call(): fourth argument must be an array of arguments.\n");
            return val_nil();
        }
        call_args = AS_ARRAY(args[3]);
        call_argc = call_args->count;
    }

    if (call_argc > 3) {
        fprintf(stderr, "ffi_call(): maximum 3 arguments supported (got %d).\n", call_argc);
        return val_nil();
    }

    // POSIX guarantees dlsym void* converts to function pointers.
    // Suppress -Wpedantic for these necessary casts.
    #pragma GCC diagnostic push
    #pragma GCC diagnostic ignored "-Wpedantic"

    if (strcmp(ret_type, "double") == 0) {
        if (call_argc == 0) {
            double (*fn)(void) = (double (*)(void))sym;
            return val_number(fn());
        } else if (call_argc == 1 && IS_NUMBER(call_args->elements[0])) {
            double (*fn)(double) = (double (*)(double))sym;
            return val_number(fn(AS_NUMBER(call_args->elements[0])));
        } else if (call_argc == 2 && IS_NUMBER(call_args->elements[0]) && IS_NUMBER(call_args->elements[1])) {
            double (*fn)(double, double) = (double (*)(double, double))sym;
            return val_number(fn(AS_NUMBER(call_args->elements[0]), AS_NUMBER(call_args->elements[1])));
        } else if (call_argc == 3 && IS_NUMBER(call_args->elements[0]) && IS_NUMBER(call_args->elements[1]) && IS_NUMBER(call_args->elements[2])) {
            double (*fn)(double, double, double) = (double (*)(double, double, double))sym;
            return val_number(fn(AS_NUMBER(call_args->elements[0]), AS_NUMBER(call_args->elements[1]), AS_NUMBER(call_args->elements[2])));
        }
        fprintf(stderr, "ffi_call: unsupported argument types for double return.\n");
        return val_nil();
    }

    if (strcmp(ret_type, "int") == 0) {
        if (call_argc == 0) {
            int (*fn)(void) = (int (*)(void))sym;
            return val_number((double)fn());
        } else if (call_argc == 1 && IS_NUMBER(call_args->elements[0])) {
            int (*fn)(int) = (int (*)(int))sym;
            return val_number((double)fn((int)AS_NUMBER(call_args->elements[0])));
        } else if (call_argc == 1 && IS_STRING(call_args->elements[0])) {
            int (*fn)(const char*) = (int (*)(const char*))sym;
            return val_number((double)fn(AS_STRING(call_args->elements[0])));
        } else if (call_argc == 2 && IS_NUMBER(call_args->elements[0]) && IS_NUMBER(call_args->elements[1])) {
            int (*fn)(int, int) = (int (*)(int, int))sym;
            return val_number((double)fn((int)AS_NUMBER(call_args->elements[0]), (int)AS_NUMBER(call_args->elements[1])));
        }
        fprintf(stderr, "ffi_call: unsupported argument types for int return.\n");
        return val_nil();
    }

    if (strcmp(ret_type, "long") == 0) {
        if (call_argc == 1 && IS_NUMBER(call_args->elements[0])) {
            long (*fn)(long) = (long (*)(long))sym;
            return val_number((double)fn((long)AS_NUMBER(call_args->elements[0])));
        } else if (call_argc == 1 && IS_STRING(call_args->elements[0])) {
            long (*fn)(const char*) = (long (*)(const char*))sym;
            return val_number((double)fn(AS_STRING(call_args->elements[0])));
        } else if (call_argc == 2 && IS_NUMBER(call_args->elements[0]) && IS_NUMBER(call_args->elements[1])) {
            long (*fn)(long, long) = (long (*)(long, long))sym;
            return val_number((double)fn((long)AS_NUMBER(call_args->elements[0]), (long)AS_NUMBER(call_args->elements[1])));
        }
        fprintf(stderr, "ffi_call: unsupported argument types for long return.\n");
        return val_nil();
    }

    if (strcmp(ret_type, "string") == 0) {
        if (call_argc == 0) {
            const char* (*fn)(void) = (const char* (*)(void))sym;
            const char* result = fn();
            return result ? val_string(result) : val_nil();
        } else if (call_argc == 1 && IS_STRING(call_args->elements[0])) {
            const char* (*fn)(const char*) = (const char* (*)(const char*))sym;
            const char* result = fn(AS_STRING(call_args->elements[0]));
            return result ? val_string(result) : val_nil();
        }
        fprintf(stderr, "ffi_call: unsupported argument types for string return.\n");
        return val_nil();
    }

    if (strcmp(ret_type, "void") == 0) {
        if (call_argc == 0) {
            void (*fn)(void) = (void (*)(void))sym;
            fn();
            return val_nil();
        } else if (call_argc == 1 && IS_NUMBER(call_args->elements[0])) {
            void (*fn)(int) = (void (*)(int))sym;
            fn((int)AS_NUMBER(call_args->elements[0]));
            return val_nil();
        } else if (call_argc == 1 && IS_STRING(call_args->elements[0])) {
            void (*fn)(const char*) = (void (*)(const char*))sym;
            fn(AS_STRING(call_args->elements[0]));
            return val_nil();
        }
        fprintf(stderr, "ffi_call: unsupported argument types for void return.\n");
        return val_nil();
    }

    #pragma GCC diagnostic pop

    fprintf(stderr, "ffi_call: unknown return type '%s'. Use 'double', 'int', 'long', 'string', or 'void'.\n", ret_type);
    return val_nil();
}

// ffi_sym(lib, "symbol_name") -> true/false (check if symbol exists)
static Value ffi_sym_native(int argCount, Value* args) {
    if (argCount != 2 || !IS_CLIB(args[0]) || !IS_STRING(args[1])) {
        fprintf(stderr, "ffi_sym() expects (clib, string).\n");
        return val_bool(0);
    }
    CLibValue* lib = AS_CLIB(args[0]);
    if (!lib->handle) return val_bool(0);

    dlerror();
    dlsym(lib->handle, AS_STRING(args[1]));
    return val_bool(dlerror() == NULL);
}

#endif // SAGE_NO_FFI

// ========== Phase 9: Raw Memory Operations ==========

// mem_alloc(size) -> pointer
static Value mem_alloc_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_NUMBER(args[0])) {
        fprintf(stderr, "mem_alloc() expects (number).\n");
        return val_nil();
    }
    size_t size = (size_t)AS_NUMBER(args[0]);
    if (size == 0 || size > 1024 * 1024 * 64) { // Cap at 64MB
        fprintf(stderr, "mem_alloc(): invalid size (0 < size <= 64MB).\n");
        return val_nil();
    }
    void* ptr = calloc(1, size); // Zero-initialized
    if (!ptr) {
        fprintf(stderr, "mem_alloc(): allocation failed.\n");
        return val_nil();
    }
    return val_pointer(ptr, size, 1);
}

// mem_free(ptr) -> nil
static Value mem_free_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_POINTER(args[0])) {
        fprintf(stderr, "mem_free() expects (pointer).\n");
        return val_nil();
    }
    PointerValue* p = AS_POINTER(args[0]);
    if (p->ptr && p->owned) {
        free(p->ptr);
        p->ptr = NULL;
        p->size = 0;
        p->owned = 0;
    }
    return val_nil();
}

// mem_read(ptr, offset, type) -> value
// type: "byte", "int", "double", "string"
static Value mem_read_native(int argCount, Value* args) {
    if (argCount != 3 || !IS_POINTER(args[0]) || !IS_NUMBER(args[1]) || !IS_STRING(args[2])) {
        fprintf(stderr, "mem_read() expects (pointer, offset, type_string).\n");
        return val_nil();
    }
    PointerValue* p = AS_POINTER(args[0]);
    if (!p->ptr) {
        fprintf(stderr, "mem_read(): null pointer.\n");
        return val_nil();
    }
    double offset_d = AS_NUMBER(args[1]);
    if (offset_d < 0) {
        fprintf(stderr, "mem_read(): offset cannot be negative.\n");
        return val_nil();
    }
    size_t offset = (size_t)offset_d;
    const char* type = AS_STRING(args[2]);

    // Bounds checking for owned memory
    if (p->size > 0) {
        size_t needed = 0;
        if (strcmp(type, "byte") == 0) needed = 1;
        else if (strcmp(type, "int") == 0) needed = sizeof(int);
        else if (strcmp(type, "double") == 0) needed = sizeof(double);
        else if (strcmp(type, "string") == 0) needed = 1; // at least 1 byte
        if (offset + needed > p->size) {
            fprintf(stderr, "mem_read(): offset %zu + %zu bytes exceeds allocation size %zu.\n",
                    offset, needed, p->size);
            return val_nil();
        }
    }

    unsigned char* base = (unsigned char*)p->ptr + offset;

    if (strcmp(type, "byte") == 0) {
        return val_number((double)*base);
    } else if (strcmp(type, "int") == 0) {
        int val;
        memcpy(&val, base, sizeof(int));
        return val_number((double)val);
    } else if (strcmp(type, "double") == 0) {
        double val;
        memcpy(&val, base, sizeof(double));
        return val_number(val);
    } else if (strcmp(type, "string") == 0) {
        return val_string((const char*)base);
    } else {
        fprintf(stderr, "mem_read(): unknown type '%s' (use byte/int/double/string).\n", type);
        return val_nil();
    }
}

// mem_write(ptr, offset, type, value) -> nil
static Value mem_write_native(int argCount, Value* args) {
    if (argCount != 4 || !IS_POINTER(args[0]) || !IS_NUMBER(args[1]) || !IS_STRING(args[2])) {
        fprintf(stderr, "mem_write() expects (pointer, offset, type_string, value).\n");
        return val_nil();
    }
    PointerValue* p = AS_POINTER(args[0]);
    if (!p->ptr) {
        fprintf(stderr, "mem_write(): null pointer.\n");
        return val_nil();
    }
    double offset_d = AS_NUMBER(args[1]);
    if (offset_d < 0) {
        fprintf(stderr, "mem_write(): offset cannot be negative.\n");
        return val_nil();
    }
    size_t offset = (size_t)offset_d;
    const char* type = AS_STRING(args[2]);

    // Bounds checking for owned memory
    if (p->size > 0) {
        size_t needed = 0;
        if (strcmp(type, "byte") == 0) needed = 1;
        else if (strcmp(type, "int") == 0) needed = sizeof(int);
        else if (strcmp(type, "double") == 0) needed = sizeof(double);
        if (needed > 0 && offset + needed > p->size) {
            fprintf(stderr, "mem_write(): offset %zu + %zu bytes exceeds allocation size %zu.\n",
                    offset, needed, p->size);
            return val_nil();
        }
    }

    unsigned char* base = (unsigned char*)p->ptr + offset;

    if (strcmp(type, "byte") == 0) {
        if (!IS_NUMBER(args[3])) {
            fprintf(stderr, "mem_write(): byte value must be a number.\n");
            return val_nil();
        }
        *base = (unsigned char)AS_NUMBER(args[3]);
    } else if (strcmp(type, "int") == 0) {
        if (!IS_NUMBER(args[3])) {
            fprintf(stderr, "mem_write(): int value must be a number.\n");
            return val_nil();
        }
        int val = (int)AS_NUMBER(args[3]);
        memcpy(base, &val, sizeof(int));
    } else if (strcmp(type, "double") == 0) {
        if (!IS_NUMBER(args[3])) {
            fprintf(stderr, "mem_write(): double value must be a number.\n");
            return val_nil();
        }
        double val = AS_NUMBER(args[3]);
        memcpy(base, &val, sizeof(double));
    } else {
        fprintf(stderr, "mem_write(): unknown type '%s' (use byte/int/double).\n", type);
    }
    return val_nil();
}

// mem_size(ptr) -> number
static Value mem_size_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_POINTER(args[0])) {
        fprintf(stderr, "mem_size() expects (pointer).\n");
        return val_nil();
    }
    return val_number((double)AS_POINTER(args[0])->size);
}

// addressof(value) -> number (address as integer, for inspection only)
static Value addressof_native(int argCount, Value* args) {
    if (argCount != 1) {
        fprintf(stderr, "addressof() expects (value).\n");
        return val_nil();
    }
    // Return address of the underlying data
    void* addr = NULL;
    switch (args[0].type) {
        case VAL_STRING:   addr = (void*)AS_STRING(args[0]); break;
        case VAL_ARRAY:    addr = (void*)AS_ARRAY(args[0]); break;
        case VAL_DICT:     addr = (void*)AS_DICT(args[0]); break;
        case VAL_POINTER:  addr = AS_POINTER(args[0])->ptr; break;
        case VAL_INSTANCE: addr = (void*)args[0].as.instance; break;
        default:           addr = (void*)&args[0]; break;
    }
    return val_number((double)(uintptr_t)addr);
}

// ========== Phase 9: C Struct Interop ==========

// Helper: get size and alignment for a C type string
static int struct_type_info(const char* type, size_t* out_size, size_t* out_align) {
    if (strcmp(type, "char") == 0 || strcmp(type, "byte") == 0) {
        *out_size = 1; *out_align = 1;
    } else if (strcmp(type, "short") == 0) {
        *out_size = sizeof(short); *out_align = sizeof(short);
    } else if (strcmp(type, "int") == 0) {
        *out_size = sizeof(int); *out_align = sizeof(int);
    } else if (strcmp(type, "long") == 0) {
        *out_size = sizeof(long); *out_align = sizeof(long);
    } else if (strcmp(type, "float") == 0) {
        *out_size = sizeof(float); *out_align = sizeof(float);
    } else if (strcmp(type, "double") == 0) {
        *out_size = sizeof(double); *out_align = sizeof(double);
    } else if (strcmp(type, "ptr") == 0) {
        *out_size = sizeof(void*); *out_align = sizeof(void*);
    } else {
        return -1;
    }
    return 0;
}

// Helper: align offset to alignment boundary
static size_t align_to(size_t offset, size_t alignment) {
    return (offset + alignment - 1) & ~(alignment - 1);
}

// struct_def(fields) -> dict
// fields: array of [name, type] pairs
// Returns a dict with field metadata:
//   "__size__" -> total struct size (number)
//   "__align__" -> struct alignment (number)
//   "field_name" -> [offset, size, type] (tuple)
static Value struct_def_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_ARRAY(args[0])) {
        fprintf(stderr, "struct_def() expects (array of [name, type] pairs).\n");
        return val_nil();
    }

    ArrayValue* fields = AS_ARRAY(args[0]);
    Value result = val_dict();
    size_t offset = 0;
    size_t max_align = 1;

    for (int i = 0; i < fields->count; i++) {
        Value field = fields->elements[i];
        if (!IS_ARRAY(field)) {
            fprintf(stderr, "struct_def(): each field must be [name, type].\n");
            return val_nil();
        }
        ArrayValue* pair = AS_ARRAY(field);
        if (pair->count != 2 || !IS_STRING(pair->elements[0]) || !IS_STRING(pair->elements[1])) {
            fprintf(stderr, "struct_def(): each field must be [name_string, type_string].\n");
            return val_nil();
        }

        const char* name = AS_STRING(pair->elements[0]);
        const char* type = AS_STRING(pair->elements[1]);

        size_t fsize, falign;
        if (struct_type_info(type, &fsize, &falign) != 0) {
            fprintf(stderr, "struct_def(): unknown type '%s'.\n", type);
            return val_nil();
        }

        // Align offset
        offset = align_to(offset, falign);
        if (falign > max_align) max_align = falign;

        // Store field info as tuple: (offset, size, type_string)
        Value tuple_elems[3];
        tuple_elems[0] = val_number((double)offset);
        tuple_elems[1] = val_number((double)fsize);
        tuple_elems[2] = val_string(type);
        dict_set(&result, name, val_tuple(tuple_elems, 3));

        offset += fsize;
    }

    // Align total size to struct alignment
    offset = align_to(offset, max_align);

    dict_set(&result, "__size__", val_number((double)offset));
    dict_set(&result, "__align__", val_number((double)max_align));

    return result;
}

// struct_new(def) -> pointer
// Allocates zeroed memory for the struct
static Value struct_new_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_DICT(args[0])) {
        fprintf(stderr, "struct_new() expects (struct_def dict).\n");
        return val_nil();
    }

    Value size_val = dict_get(&args[0], "__size__");
    if (!IS_NUMBER(size_val)) {
        fprintf(stderr, "struct_new(): invalid struct definition (missing __size__).\n");
        return val_nil();
    }

    size_t size = (size_t)AS_NUMBER(size_val);
    void* ptr = calloc(1, size);
    if (!ptr) {
        fprintf(stderr, "struct_new(): allocation failed.\n");
        return val_nil();
    }
    return val_pointer(ptr, size, 1);
}

// struct_get(ptr, def, field_name) -> value
static Value struct_get_native(int argCount, Value* args) {
    if (argCount != 3 || !IS_POINTER(args[0]) || !IS_DICT(args[1]) || !IS_STRING(args[2])) {
        fprintf(stderr, "struct_get() expects (pointer, struct_def, field_name).\n");
        return val_nil();
    }

    PointerValue* p = AS_POINTER(args[0]);
    if (!p->ptr) {
        fprintf(stderr, "struct_get(): null pointer.\n");
        return val_nil();
    }

    Value field_info = dict_get(&args[1], AS_STRING(args[2]));
    if (!IS_TUPLE(field_info) || field_info.as.tuple->count != 3) {
        fprintf(stderr, "struct_get(): unknown field '%s'.\n", AS_STRING(args[2]));
        return val_nil();
    }

    size_t offset = (size_t)AS_NUMBER(field_info.as.tuple->elements[0]);
    const char* type = AS_STRING(field_info.as.tuple->elements[2]);
    unsigned char* base = (unsigned char*)p->ptr + offset;

    if (strcmp(type, "char") == 0 || strcmp(type, "byte") == 0) {
        return val_number((double)*base);
    } else if (strcmp(type, "short") == 0) {
        short v; memcpy(&v, base, sizeof(short));
        return val_number((double)v);
    } else if (strcmp(type, "int") == 0) {
        int v; memcpy(&v, base, sizeof(int));
        return val_number((double)v);
    } else if (strcmp(type, "long") == 0) {
        long v; memcpy(&v, base, sizeof(long));
        return val_number((double)v);
    } else if (strcmp(type, "float") == 0) {
        float v; memcpy(&v, base, sizeof(float));
        return val_number((double)v);
    } else if (strcmp(type, "double") == 0) {
        double v; memcpy(&v, base, sizeof(double));
        return val_number(v);
    } else if (strcmp(type, "ptr") == 0) {
        void* v; memcpy(&v, base, sizeof(void*));
        return val_pointer(v, 0, 0); // Non-owned external pointer
    }
    return val_nil();
}

// struct_set(ptr, def, field_name, value) -> nil
static Value struct_set_native(int argCount, Value* args) {
    if (argCount != 4 || !IS_POINTER(args[0]) || !IS_DICT(args[1]) || !IS_STRING(args[2])) {
        fprintf(stderr, "struct_set() expects (pointer, struct_def, field_name, value).\n");
        return val_nil();
    }

    PointerValue* p = AS_POINTER(args[0]);
    if (!p->ptr) {
        fprintf(stderr, "struct_set(): null pointer.\n");
        return val_nil();
    }

    Value field_info = dict_get(&args[1], AS_STRING(args[2]));
    if (!IS_TUPLE(field_info) || field_info.as.tuple->count != 3) {
        fprintf(stderr, "struct_set(): unknown field '%s'.\n", AS_STRING(args[2]));
        return val_nil();
    }

    size_t offset = (size_t)AS_NUMBER(field_info.as.tuple->elements[0]);
    const char* type = AS_STRING(field_info.as.tuple->elements[2]);
    unsigned char* base = (unsigned char*)p->ptr + offset;

    if (!IS_NUMBER(args[3]) && strcmp(type, "ptr") != 0) {
        fprintf(stderr, "struct_set(): value must be a number for type '%s'.\n", type);
        return val_nil();
    }

    if (strcmp(type, "char") == 0 || strcmp(type, "byte") == 0) {
        *base = (unsigned char)AS_NUMBER(args[3]);
    } else if (strcmp(type, "short") == 0) {
        short v = (short)AS_NUMBER(args[3]);
        memcpy(base, &v, sizeof(short));
    } else if (strcmp(type, "int") == 0) {
        int v = (int)AS_NUMBER(args[3]);
        memcpy(base, &v, sizeof(int));
    } else if (strcmp(type, "long") == 0) {
        long v = (long)AS_NUMBER(args[3]);
        memcpy(base, &v, sizeof(long));
    } else if (strcmp(type, "float") == 0) {
        float v = (float)AS_NUMBER(args[3]);
        memcpy(base, &v, sizeof(float));
    } else if (strcmp(type, "double") == 0) {
        double v = AS_NUMBER(args[3]);
        memcpy(base, &v, sizeof(double));
    } else if (strcmp(type, "ptr") == 0) {
        if (!IS_POINTER(args[3])) {
            fprintf(stderr, "struct_set(): value must be a pointer for type 'ptr'.\n");
            return val_nil();
        }
        void* v = AS_POINTER(args[3])->ptr;
        memcpy(base, &v, sizeof(void*));
    }
    return val_nil();
}

// struct_size(def) -> number
static Value struct_size_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_DICT(args[0])) {
        fprintf(stderr, "struct_size() expects (struct_def dict).\n");
        return val_nil();
    }
    Value size_val = dict_get(&args[0], "__size__");
    if (!IS_NUMBER(size_val)) return val_nil();
    return size_val;
}

// ========== Phase 9: Inline Assembly ==========

// Helper: process \n and \t escape sequences in assembly code strings
static char* asm_process_escapes(const char* raw) {
    size_t len = strlen(raw);
    char* out = SAGE_ALLOC(len + 1);
    size_t j = 0;
    for (size_t i = 0; i < len; i++) {
        if (raw[i] == '\\' && i + 1 < len) {
            if (raw[i + 1] == 'n') { out[j++] = '\n'; i++; continue; }
            if (raw[i + 1] == 't') { out[j++] = '\t'; i++; continue; }
        }
        out[j++] = raw[i];
    }
    out[j] = '\0';
    return out;
}

// Helper: detect host architecture and return assembler flags
static const char* asm_detect_arch(void) {
#if defined(__x86_64__) || defined(_M_X64)
    return "x86_64";
#elif defined(__aarch64__) || defined(_M_ARM64)
    return "aarch64";
#elif defined(__riscv) && __riscv_xlen == 64
    return "rv64";
#else
    return "unknown";
#endif
}

// Validate a path contains no shell metacharacters (prevents injection via system())
static int is_safe_path(const char* path) {
    for (const char* p = path; *p; p++) {
        // Allow only alphanumeric, /, ., -, _, ~
        if (!isalnum((unsigned char)*p) && *p != '/' && *p != '.' &&
            *p != '-' && *p != '_' && *p != '~') {
            return 0;
        }
    }
    return 1;
}

// Helper: get assembler command for architecture
// For native arch, uses system `as`. For cross, tries arch-specific cross-assembler.
static int asm_get_commands(const char* arch, const char* asm_path,
                            const char* obj_path, const char* so_path,
                            char* as_cmd, size_t as_sz,
                            char* ld_cmd, size_t ld_sz) {
    // Validate all paths to prevent shell injection
    if (!is_safe_path(asm_path) || !is_safe_path(obj_path) || !is_safe_path(so_path)) {
        fprintf(stderr, "asm: path contains unsafe characters.\n");
        return -1;
    }
    const char* host_arch = asm_detect_arch();
    int cross = (strcmp(arch, host_arch) != 0);

    if (strcmp(arch, "x86_64") == 0) {
        if (cross) {
            snprintf(as_cmd, as_sz, "x86_64-linux-gnu-as -o %s %s 2>/dev/null", obj_path, asm_path);
            snprintf(ld_cmd, ld_sz, "x86_64-linux-gnu-gcc -shared -o %s %s 2>/dev/null", so_path, obj_path);
        } else {
            snprintf(as_cmd, as_sz, "as --64 -o %s %s 2>/dev/null", obj_path, asm_path);
            snprintf(ld_cmd, ld_sz, "gcc -shared -o %s %s 2>/dev/null", so_path, obj_path);
        }
    } else if (strcmp(arch, "aarch64") == 0) {
        if (cross) {
            snprintf(as_cmd, as_sz, "aarch64-linux-gnu-as -o %s %s 2>/dev/null", obj_path, asm_path);
            snprintf(ld_cmd, ld_sz, "aarch64-linux-gnu-gcc -shared -o %s %s 2>/dev/null", so_path, obj_path);
        } else {
            snprintf(as_cmd, as_sz, "as -o %s %s 2>/dev/null", obj_path, asm_path);
            snprintf(ld_cmd, ld_sz, "gcc -shared -o %s %s 2>/dev/null", so_path, obj_path);
        }
    } else if (strcmp(arch, "rv64") == 0) {
        if (cross) {
            snprintf(as_cmd, as_sz, "riscv64-linux-gnu-as -o %s %s 2>/dev/null", obj_path, asm_path);
            snprintf(ld_cmd, ld_sz, "riscv64-linux-gnu-gcc -shared -o %s %s 2>/dev/null", so_path, obj_path);
        } else {
            snprintf(as_cmd, as_sz, "as -o %s %s 2>/dev/null", obj_path, asm_path);
            snprintf(ld_cmd, ld_sz, "gcc -shared -o %s %s 2>/dev/null", so_path, obj_path);
        }
    } else {
        return -1; // Unknown arch
    }
    return cross ? 1 : 0;
}

// Helper: write the assembly source file with proper function wrapper
static int asm_write_source(const char* path, const char* code, const char* arch) {
    FILE* f = fopen(path, "w");
    if (!f) return -1;

    fprintf(f, ".text\n");
    fprintf(f, ".globl sage_asm_fn\n");

    // Architecture-specific directives
    if (strcmp(arch, "x86_64") == 0 || strcmp(arch, "aarch64") == 0 || strcmp(arch, "rv64") == 0) {
        fprintf(f, ".type sage_asm_fn, @function\n");
    }

    fprintf(f, "sage_asm_fn:\n");
    fprintf(f, "%s\n", code);

    // Architecture-specific return instruction
    if (strcmp(arch, "x86_64") == 0) {
        fprintf(f, "    ret\n");
    } else if (strcmp(arch, "aarch64") == 0) {
        fprintf(f, "    ret\n");
    } else if (strcmp(arch, "rv64") == 0) {
        fprintf(f, "    ret\n"); // RISC-V pseudo-instruction (jalr x0, x1, 0)
    }

    fprintf(f, ".size sage_asm_fn, .-sage_asm_fn\n");
    fclose(f);
    return 0;
}

#ifndef SAGE_NO_FFI
// asm_exec(code, ret_type, ...args) -> value
// Compiles assembly to a temp shared library, calls it, returns result.
// code: string of assembly instructions (\n for newlines)
// ret_type: "int", "double", or "void"
// args: up to 4 numeric arguments
// Uses host architecture by default. For cross-compilation, see asm_compile().
static Value asm_exec_native(int argCount, Value* args) {
    if (argCount < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) {
        fprintf(stderr, "asm_exec() expects (code_string, ret_type, ...args).\n");
        return val_nil();
    }

    char* code = asm_process_escapes(AS_STRING(args[0]));
    const char* ret_type = AS_STRING(args[1]);
    int num_args = argCount - 2;
    const char* arch = asm_detect_arch();
    Value result = val_nil();

    if (num_args > 4) {
        fprintf(stderr, "asm_exec(): max 4 arguments supported.\n");
        free(code);
        return val_nil();
    }

    for (int i = 0; i < num_args; i++) {
        if (!IS_NUMBER(args[i + 2])) {
            fprintf(stderr, "asm_exec(): argument %d must be a number.\n", i);
            free(code);
            return val_nil();
        }
    }

    // Generate secure temp file names using mkstemp
    char asm_path[] = "/tmp/sage_asm_XXXXXX.s";
    char obj_path[] = "/tmp/sage_asm_XXXXXX.o";
    char so_path[]  = "/tmp/sage_asm_XXXXXX.so";
    int asm_fd = mkstemps(asm_path, 2);
    int obj_fd = mkstemps(obj_path, 2);
    int so_fd  = mkstemps(so_path, 3);
    if (asm_fd >= 0) close(asm_fd);
    if (obj_fd >= 0) close(obj_fd);
    if (so_fd >= 0)  close(so_fd);

    // Write assembly source
    if (asm_write_source(asm_path, code, arch) != 0) {
        fprintf(stderr, "asm_exec(): failed to create temp file.\n");
        free(code);
        return val_nil();
    }
    free(code);

    // Get assembler/linker commands
    char as_cmd[512], ld_cmd[512];
    if (asm_get_commands(arch, asm_path, obj_path, so_path,
                         as_cmd, sizeof(as_cmd), ld_cmd, sizeof(ld_cmd)) < 0) {
        fprintf(stderr, "asm_exec(): unsupported architecture '%s'.\n", arch);
        unlink(asm_path);
        return val_nil();
    }

    // Assemble
    if (system(as_cmd) != 0) {
        fprintf(stderr, "asm_exec(): assembly failed for %s.\n", arch);
        unlink(asm_path);
        return val_nil();
    }

    // Link as shared library
    if (system(ld_cmd) != 0) {
        fprintf(stderr, "asm_exec(): linking failed.\n");
        unlink(asm_path);
        unlink(obj_path);
        return val_nil();
    }

    // Load and call
    void* handle = dlopen(so_path, RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "asm_exec(): dlopen failed: %s\n", dlerror());
        goto cleanup_files;
    }

    void* sym = dlsym(handle, "sage_asm_fn");
    if (!sym) {
        fprintf(stderr, "asm_exec(): symbol lookup failed.\n");
        dlclose(handle);
        goto cleanup_files;
    }

    // Call function via appropriate signature
    int use_double = (strcmp(ret_type, "double") == 0);

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
    if (use_double) {
        double dargs[4] = {0};
        for (int i = 0; i < num_args; i++) dargs[i] = AS_NUMBER(args[i + 2]);

        double (*fn0)(void) = (double (*)(void))sym;
        double (*fn1)(double) = (double (*)(double))sym;
        double (*fn2)(double, double) = (double (*)(double, double))sym;
        double (*fn3)(double, double, double) = (double (*)(double, double, double))sym;
        double (*fn4)(double, double, double, double) = (double (*)(double, double, double, double))sym;

        double dres;
        switch (num_args) {
            case 0: dres = fn0(); break;
            case 1: dres = fn1(dargs[0]); break;
            case 2: dres = fn2(dargs[0], dargs[1]); break;
            case 3: dres = fn3(dargs[0], dargs[1], dargs[2]); break;
            case 4: dres = fn4(dargs[0], dargs[1], dargs[2], dargs[3]); break;
            default: dres = 0; break;
        }
        result = val_number(dres);
    } else if (strcmp(ret_type, "void") == 0) {
        long long iargs[4] = {0};
        for (int i = 0; i < num_args; i++) iargs[i] = (long long)AS_NUMBER(args[i + 2]);

        void (*fn0)(void) = (void (*)(void))sym;
        void (*fn1)(long long) = (void (*)(long long))sym;
        void (*fn2)(long long, long long) = (void (*)(long long, long long))sym;

        switch (num_args) {
            case 0: fn0(); break;
            case 1: fn1(iargs[0]); break;
            case 2: fn2(iargs[0], iargs[1]); break;
            default: fn0(); break;
        }
    } else {
        // "int" / "long" - integer return
        long long iargs[4] = {0};
        for (int i = 0; i < num_args; i++) iargs[i] = (long long)AS_NUMBER(args[i + 2]);

        long long (*fn0)(void) = (long long (*)(void))sym;
        long long (*fn1)(long long) = (long long (*)(long long))sym;
        long long (*fn2)(long long, long long) = (long long (*)(long long, long long))sym;
        long long (*fn3)(long long, long long, long long) = (long long (*)(long long, long long, long long))sym;
        long long (*fn4)(long long, long long, long long, long long) = (long long (*)(long long, long long, long long, long long))sym;

        long long ires;
        switch (num_args) {
            case 0: ires = fn0(); break;
            case 1: ires = fn1(iargs[0]); break;
            case 2: ires = fn2(iargs[0], iargs[1]); break;
            case 3: ires = fn3(iargs[0], iargs[1], iargs[2]); break;
            case 4: ires = fn4(iargs[0], iargs[1], iargs[2], iargs[3]); break;
            default: ires = 0; break;
        }
        result = val_number((double)ires);
    }
#pragma GCC diagnostic pop

    dlclose(handle);

cleanup_files:
    unlink(asm_path);
    unlink(obj_path);
    unlink(so_path);

    return result;
}
#endif // SAGE_NO_FFI

// asm_compile(code, arch, output_path) -> bool
// Cross-compile assembly for a target architecture without executing.
// arch: "x86_64", "aarch64", or "rv64"
// output_path: path to write the .o object file
static Value asm_compile_native(int argCount, Value* args) {
    if (argCount != 3 || !IS_STRING(args[0]) || !IS_STRING(args[1]) || !IS_STRING(args[2])) {
        fprintf(stderr, "asm_compile() expects (code_string, arch, output_path).\n");
        return val_bool(0);
    }

    char* code = asm_process_escapes(AS_STRING(args[0]));
    const char* arch = AS_STRING(args[1]);
    const char* output_path = AS_STRING(args[2]);

    // Write assembly source with secure temp file
    char asm_path[] = "/tmp/sage_xasm_XXXXXX.s";
    int asm_fd = mkstemps(asm_path, 2);
    if (asm_fd >= 0) close(asm_fd);

    if (asm_write_source(asm_path, code, arch) != 0) {
        fprintf(stderr, "asm_compile(): failed to create temp file.\n");
        free(code);
        return val_bool(0);
    }
    free(code);

    // Get assembler command (we only need the assembler, not linker)
    char as_cmd[512], ld_cmd[512];
    if (asm_get_commands(arch, asm_path, output_path, "/dev/null",
                         as_cmd, sizeof(as_cmd), ld_cmd, sizeof(ld_cmd)) < 0) {
        fprintf(stderr, "asm_compile(): unsupported architecture '%s'.\n", arch);
        unlink(asm_path);
        return val_bool(0);
    }

    // Assemble to object file (output_path is already in as_cmd as obj_path)
    int ok = (system(as_cmd) == 0);
    unlink(asm_path);

    if (!ok) {
        fprintf(stderr, "asm_compile(): assembly failed for %s. Is the cross-assembler installed?\n", arch);
    }
    return val_bool(ok);
}

// asm_arch() -> string
// Returns the host architecture name
static Value asm_arch_native(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_string(asm_detect_arch());
}

void init_stdlib(Env* env) {
    // Core functions
    env_define(env, "clock", 5, val_native(clock_native));
    env_define(env, "input", 5, val_native(input_native));
    env_define(env, "tonumber", 8, val_native(tonumber_native));
    env_define(env, "str", 3, val_native(str_native));
    env_define(env, "len", 3, val_native(len_native));
    
    // Array functions
    env_define(env, "push", 4, val_native(push_native));
    env_define(env, "append", 6, val_native(push_native));
    env_define(env, "build_quad_verts", 16, val_native(build_quad_verts_native));
    env_define(env, "array_extend", 12, val_native(array_extend_native));
    env_define(env, "build_line_quads", 16, val_native(build_line_quads_native));
    env_define(env, "pop", 3, val_native(pop_native));
    env_define(env, "range", 5, val_native(range_native));
    env_define(env, "slice", 5, val_native(slice_native));
    
    // String functions
    env_define(env, "split", 5, val_native(split_native));
    env_define(env, "join", 4, val_native(join_native));
    env_define(env, "replace", 7, val_native(replace_native));
    env_define(env, "upper", 5, val_native(upper_native));
    env_define(env, "lower", 5, val_native(lower_native));
    env_define(env, "strip", 5, val_native(strip_native));
    env_define(env, "type", 4, val_native(type_native));
    env_define(env, "chr", 3, val_native(chr_native));
    env_define(env, "ord", 3, val_native(ord_native));
    env_define(env, "startswith", 10, val_native(startswith_native));
    env_define(env, "endswith", 8, val_native(endswith_native));
    env_define(env, "contains", 8, val_native(contains_native));
    env_define(env, "indexof", 7, val_native(indexof_native));

    // Dictionary functions
    env_define(env, "dict_keys", 9, val_native(dict_keys_native));
    env_define(env, "dict_values", 11, val_native(dict_values_native));
    env_define(env, "dict_has", 8, val_native(dict_has_native));
    env_define(env, "dict_delete", 11, val_native(dict_delete_native));
    
    // GC functions
    env_define(env, "gc_collect", 10, val_native(gc_collect_native));
    env_define(env, "gc_stats", 8, val_native(gc_stats_native));
    env_define(env, "gc_collections", 14, val_native(gc_collections_native));
    env_define(env, "gc_enable", 9, val_native(gc_enable_native));
    env_define(env, "gc_disable", 10, val_native(gc_disable_native));
    
    // PHASE 7: Generator function
    env_define(env, "next", 4, val_native(native_next));

#ifndef SAGE_NO_FFI
    // Phase 9: FFI functions
    env_define(env, "ffi_open", 8, val_native(ffi_open_native));
    env_define(env, "ffi_close", 9, val_native(ffi_close_native));
    env_define(env, "ffi_call", 8, val_native(ffi_call_native));
    env_define(env, "ffi_sym", 7, val_native(ffi_sym_native));
#endif

    // Phase 9: Memory operations
    env_define(env, "mem_alloc", 9, val_native(mem_alloc_native));
    env_define(env, "mem_free", 8, val_native(mem_free_native));
    env_define(env, "mem_read", 8, val_native(mem_read_native));
    env_define(env, "mem_write", 9, val_native(mem_write_native));
    env_define(env, "mem_size", 8, val_native(mem_size_native));
    env_define(env, "addressof", 9, val_native(addressof_native));

    // Phase 9: C struct interop
    env_define(env, "struct_def", 10, val_native(struct_def_native));
    env_define(env, "struct_new", 10, val_native(struct_new_native));
    env_define(env, "struct_get", 10, val_native(struct_get_native));
    env_define(env, "struct_set", 10, val_native(struct_set_native));
    env_define(env, "struct_size", 11, val_native(struct_size_native));

    // Phase 9: Inline assembly
#ifndef SAGE_NO_FFI
    env_define(env, "asm_exec", 8, val_native(asm_exec_native));
#endif
    env_define(env, "asm_compile", 11, val_native(asm_compile_native));
    env_define(env, "asm_arch", 8, val_native(asm_arch_native));
}

// --- Helper: Truthiness ---
static int is_truthy(Value v) {
    if (IS_NIL(v)) return 0;
    if (IS_BOOL(v)) return AS_BOOL(v);
    return 1; 
}

// PHASE 7: Helper to detect if a statement block contains yield
static int contains_yield(Stmt* body) {
    Stmt* current = body;
    while (current != NULL) {
        if (current->type == STMT_YIELD) return 1;
        if (current->type == STMT_BLOCK && contains_yield(current->as.block.statements)) return 1;
        if (current->type == STMT_IF) {
            if (contains_yield(current->as.if_stmt.then_branch)) return 1;
            if (current->as.if_stmt.else_branch && contains_yield(current->as.if_stmt.else_branch)) return 1;
        }
        if (current->type == STMT_WHILE && contains_yield(current->as.while_stmt.body)) return 1;
        if (current->type == STMT_FOR && contains_yield(current->as.for_stmt.body)) return 1;
        current = current->next;
    }
    return 0;
}

// --- Forward Declaration ---
static ExecResult eval_expr(Expr* expr, Env* env);
static ExecResult eval_expr_impl(Expr* expr, Env* env);
static ExecResult interpret_inner(Stmt* stmt, Env* env);

// --- Evaluator ---

static ExecResult eval_binary(BinaryExpr* b, Env* env) {
    ExecResult left_result = eval_expr(b->left, env);
    if (left_result.is_throwing) return left_result;
    Value left = left_result.value;

    if (b->op.type == TOKEN_NOT) {
        return EVAL_RESULT(val_bool(!is_truthy(left)));
    }

    // Phase 9: Bitwise NOT (~x)
    if (b->op.type == TOKEN_TILDE) {
        if (!IS_NUMBER(left)) {
            fprintf(stderr, "Runtime Error: Bitwise NOT operand must be a number.\n");
            return EVAL_RESULT(val_nil());
        }
        return EVAL_RESULT(val_number((double)(~(long long)AS_NUMBER(left))));
    }

    if (b->op.type == TOKEN_OR) {
        if (is_truthy(left)) {
            return EVAL_RESULT(val_bool(1));
        }
        ExecResult right_result = eval_expr(b->right, env);
        if (right_result.is_throwing) return right_result;
        return EVAL_RESULT(val_bool(is_truthy(right_result.value)));
    }

    if (b->op.type == TOKEN_AND) {
        if (!is_truthy(left)) {
            return EVAL_RESULT(val_bool(0));
        }
        ExecResult right_result = eval_expr(b->right, env);
        if (right_result.is_throwing) return right_result;
        return EVAL_RESULT(val_bool(is_truthy(right_result.value)));
    }

    ExecResult right_result = eval_expr(b->right, env);
    if (right_result.is_throwing) return right_result;
    Value right = right_result.value;

    if (b->op.type == TOKEN_EQ || b->op.type == TOKEN_NEQ) {
        int equal = values_equal(left, right);
        if (b->op.type == TOKEN_EQ) return EVAL_RESULT(val_bool(equal));
        if (b->op.type == TOKEN_NEQ) return EVAL_RESULT(val_bool(!equal));
    }

    if (b->op.type == TOKEN_GT || b->op.type == TOKEN_LT || b->op.type == TOKEN_GTE || b->op.type == TOKEN_LTE) {
        if (IS_NUMBER(left) && IS_NUMBER(right)) {
            double l = AS_NUMBER(left);
            double r = AS_NUMBER(right);
            if (b->op.type == TOKEN_GT) return EVAL_RESULT(val_bool(l > r));
            if (b->op.type == TOKEN_LT) return EVAL_RESULT(val_bool(l < r));
            if (b->op.type == TOKEN_GTE) return EVAL_RESULT(val_bool(l >= r));
            if (b->op.type == TOKEN_LTE) return EVAL_RESULT(val_bool(l <= r));
        }
        if (IS_STRING(left) && IS_STRING(right)) {
            int cmp = strcmp(AS_STRING(left), AS_STRING(right));
            if (b->op.type == TOKEN_GT) return EVAL_RESULT(val_bool(cmp > 0));
            if (b->op.type == TOKEN_LT) return EVAL_RESULT(val_bool(cmp < 0));
            if (b->op.type == TOKEN_GTE) return EVAL_RESULT(val_bool(cmp >= 0));
            if (b->op.type == TOKEN_LTE) return EVAL_RESULT(val_bool(cmp <= 0));
        }
        fprintf(stderr, "Runtime Error: Operands must be numbers or strings.\n");
        return EVAL_RESULT(val_nil());
    }

    switch (b->op.type) {
        case TOKEN_PLUS:
            if (IS_NUMBER(left) && IS_NUMBER(right)) {
                return EVAL_RESULT(val_number(AS_NUMBER(left) + AS_NUMBER(right)));
            }
            if (IS_STRING(left) && IS_STRING(right)) {
                char* s1 = AS_STRING(left);
                char* s2 = AS_STRING(right);
                size_t len1 = strlen(s1);
                size_t len2 = strlen(s2);
                char* result = SAGE_ALLOC(len1 + len2 + 1);
                memcpy(result, s1, len1);
                memcpy(result + len1, s2, len2 + 1);
                return EVAL_RESULT(val_string_take(result));
            }
            fprintf(stderr, "Runtime Error: Operands must be numbers or strings.\n");
            return EVAL_RESULT(val_nil());

        case TOKEN_MINUS:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number(AS_NUMBER(left) - AS_NUMBER(right)));

        case TOKEN_STAR:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number(AS_NUMBER(left) * AS_NUMBER(right)));

        case TOKEN_SLASH:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            if (AS_NUMBER(right) == 0) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number(AS_NUMBER(left) / AS_NUMBER(right)));

        case TOKEN_PERCENT:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            if (AS_NUMBER(right) == 0) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number(fmod(AS_NUMBER(left), AS_NUMBER(right))));

        // Phase 9: Bitwise operators
        case TOKEN_AMP:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number((double)((long long)AS_NUMBER(left) & (long long)AS_NUMBER(right))));

        case TOKEN_PIPE:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number((double)((long long)AS_NUMBER(left) | (long long)AS_NUMBER(right))));

        case TOKEN_CARET:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number((double)((long long)AS_NUMBER(left) ^ (long long)AS_NUMBER(right))));

        case TOKEN_LSHIFT: {
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            long long shift = (long long)AS_NUMBER(right);
            if (shift < 0 || shift >= 64) return EVAL_RESULT(val_number(0.0));
            return EVAL_RESULT(val_number((double)((long long)AS_NUMBER(left) << shift)));
        }

        case TOKEN_RSHIFT: {
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            long long shift = (long long)AS_NUMBER(right);
            if (shift < 0 || shift >= 64) return EVAL_RESULT(val_number(0.0));
            return EVAL_RESULT(val_number((double)((long long)AS_NUMBER(left) >> shift)));
        }

        default:
            return EVAL_RESULT(val_nil());
    }
}

static ExecResult eval_expr(Expr* expr, Env* env) {
    if (++g_recursion_depth > MAX_RECURSION_DEPTH) {
        g_recursion_depth--;
        fprintf(stderr, "Runtime Error: Maximum recursion depth exceeded (%d).\n", MAX_RECURSION_DEPTH);
        return EVAL_EXCEPTION(val_exception("Maximum recursion depth exceeded"));
    }
    ExecResult result = eval_expr_impl(expr, env);
    g_recursion_depth--;
    return result;
}

static ExecResult eval_expr_impl(Expr* expr, Env* env) {
    switch (expr->type) {
        case EXPR_NUMBER: return EVAL_RESULT(val_number(expr->as.number.value));
        case EXPR_STRING: return EVAL_RESULT(val_string(expr->as.string.value));
        case EXPR_BOOL:   return EVAL_RESULT(val_bool(expr->as.boolean.value));
        case EXPR_NIL:    return EVAL_RESULT(val_nil());
        
        case EXPR_ARRAY: {
            gc_pin();
            Value arr = val_array();
            for (int i = 0; i < expr->as.array.count; i++) {
                ExecResult elem_result = eval_expr(expr->as.array.elements[i], env);
                if (elem_result.is_throwing) {
                    gc_unpin();
                    return elem_result;
                }
                array_push(&arr, elem_result.value);
            }
            gc_unpin();
            return EVAL_RESULT(arr);
        }

        case EXPR_DICT: {
            gc_pin();
            Value dict = val_dict();
            for (int i = 0; i < expr->as.dict.count; i++) {
                ExecResult val_result = eval_expr(expr->as.dict.values[i], env);
                if (val_result.is_throwing) {
                    gc_unpin();
                    return val_result;
                }
                dict_set(&dict, expr->as.dict.keys[i], val_result.value);
            }
            gc_unpin();
            return EVAL_RESULT(dict);
        }

        case EXPR_TUPLE: {
            gc_pin();
            Value* elements = SAGE_ALLOC(sizeof(Value) * expr->as.tuple.count);
            for (int i = 0; i < expr->as.tuple.count; i++) {
                ExecResult elem_result = eval_expr(expr->as.tuple.elements[i], env);
                if (elem_result.is_throwing) {
                    free(elements);
                    gc_unpin();
                    return elem_result;
                }
                elements[i] = elem_result.value;
            }
            Value tuple = val_tuple(elements, expr->as.tuple.count);
            free(elements);
            gc_unpin();
            return EVAL_RESULT(tuple);
        }

        case EXPR_INDEX: {
            ExecResult arr_result = eval_expr(expr->as.index.array, env);
            if (arr_result.is_throwing) return arr_result;
            Value arr = arr_result.value;
            
            ExecResult idx_result = eval_expr(expr->as.index.index, env);
            if (idx_result.is_throwing) return idx_result;
            Value idx = idx_result.value;
            
            if (arr.type == VAL_ARRAY && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                return EVAL_RESULT(array_get(&arr, index));
            }
            
            if (arr.type == VAL_TUPLE && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                return EVAL_RESULT(tuple_get(&arr, index));
            }
            
            if (arr.type == VAL_STRING && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                char* str = AS_STRING(arr);
                int slen = (int)strlen(str);
                if (index < 0) index += slen;
                if (index < 0 || index >= slen) {
                    fprintf(stderr, "Runtime Error: String index out of bounds.\n");
                    return EVAL_RESULT(val_nil());
                }
                char* ch = SAGE_ALLOC(2);
                ch[0] = str[index];
                ch[1] = '\0';
                return EVAL_RESULT(val_string(ch));
            }

            if (arr.type == VAL_DICT && IS_STRING(idx)) {
                return EVAL_RESULT(dict_get(&arr, AS_STRING(idx)));
            }

            fprintf(stderr, "Runtime Error: Invalid indexing operation.\n");
            return EVAL_RESULT(val_nil());
        }

        case EXPR_INDEX_SET: {
            ExecResult arr_result = eval_expr(expr->as.index_set.array, env);
            if (arr_result.is_throwing) return arr_result;
            Value arr = arr_result.value;

            ExecResult idx_result = eval_expr(expr->as.index_set.index, env);
            if (idx_result.is_throwing) return idx_result;
            Value idx = idx_result.value;

            ExecResult val_result = eval_expr(expr->as.index_set.value, env);
            if (val_result.is_throwing) return val_result;
            Value value = val_result.value;

            if (arr.type == VAL_ARRAY && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                array_set(&arr, index, value);
                return EVAL_RESULT(value);
            }

            if (arr.type == VAL_DICT && IS_STRING(idx)) {
                dict_set(&arr, AS_STRING(idx), value);
                return EVAL_RESULT(value);
            }

            fprintf(stderr, "Runtime Error: Invalid index assignment.\n");
            return EVAL_RESULT(val_nil());
        }

        case EXPR_SLICE: {
            ExecResult arr_result = eval_expr(expr->as.slice.array, env);
            if (arr_result.is_throwing) return arr_result;
            Value arr = arr_result.value;
            
            if (arr.type != VAL_ARRAY) {
                fprintf(stderr, "Runtime Error: Can only slice arrays.\n");
                return EVAL_RESULT(val_nil());
            }
            
            int start = 0;
            int end = arr.as.array->count;
            
            if (expr->as.slice.start != NULL) {
                ExecResult start_result = eval_expr(expr->as.slice.start, env);
                if (start_result.is_throwing) return start_result;
                if (!IS_NUMBER(start_result.value)) return EVAL_RESULT(val_nil());
                start = (int)AS_NUMBER(start_result.value);
            }
            
            if (expr->as.slice.end != NULL) {
                ExecResult end_result = eval_expr(expr->as.slice.end, env);
                if (end_result.is_throwing) return end_result;
                if (!IS_NUMBER(end_result.value)) return EVAL_RESULT(val_nil());
                end = (int)AS_NUMBER(end_result.value);
            }
            
            return EVAL_RESULT(array_slice(&arr, start, end));
        }

        case EXPR_GET: {
            ExecResult obj_result = eval_expr(expr->as.get.object, env);
            if (obj_result.is_throwing) return obj_result;
            Value object = obj_result.value;
            Token prop = expr->as.get.property;

            if (IS_INSTANCE(object)) {
                char* prop_name = SAGE_ALLOC(prop.length + 1);
                strncpy(prop_name, prop.start, prop.length);
                prop_name[prop.length] = '\0';

                Value result = instance_get_field(object.as.instance, prop_name);
                free(prop_name);
                return EVAL_RESULT(result);
            }

            if (IS_MODULE(object)) {
                int found = 0;
                Value result = module_get_attr(AS_MODULE(object), prop.start, prop.length, &found);
                if (!found) {
                    fprintf(stderr, "Runtime Error: Module '%s' has no attribute '%.*s'.\n",
                            AS_MODULE(object)->name, prop.length, prop.start);
                    return EVAL_RESULT(val_nil());
                }
                return EVAL_RESULT(result);
            }

            fprintf(stderr, "Runtime Error: Only instances and modules have properties.\n");
            return EVAL_RESULT(val_nil());
        }

        case EXPR_SET: {
            // Handle variable assignment (object is NULL)
            if (expr->as.set.object == NULL) {
                // Variable reassignment: x = value
                Token var_name = expr->as.set.property;
                ExecResult val_result = eval_expr(expr->as.set.value, env);
                if (val_result.is_throwing) return val_result;
                Value value = val_result.value;
                
                // Try to update the variable in the environment
                if (!env_assign(env, var_name.start, var_name.length, value)) {
                    fprintf(stderr, "Runtime Error: Undefined variable '%.*s'.\n", var_name.length, var_name.start);
                    return EVAL_RESULT(val_nil());
                }
                return EVAL_RESULT(value);
            }
            
            // Property assignment: obj.prop = value
            ExecResult obj_result = eval_expr(expr->as.set.object, env);
            if (obj_result.is_throwing) return obj_result;
            Value object = obj_result.value;
            
            if (!IS_INSTANCE(object)) {
                fprintf(stderr, "Runtime Error: Only instances have properties.\n");
                return EVAL_RESULT(val_nil());
            }
            
            ExecResult val_result = eval_expr(expr->as.set.value, env);
            if (val_result.is_throwing) return val_result;
            Value value = val_result.value;
            
            Token prop = expr->as.set.property;
            char* prop_name = SAGE_ALLOC(prop.length + 1);
            strncpy(prop_name, prop.start, prop.length);
            prop_name[prop.length] = '\0';
            
            instance_set_field(object.as.instance, prop_name, value);
            free(prop_name);
            return EVAL_RESULT(value);
        }

        case EXPR_AWAIT: {
            ExecResult inner = eval_expr(expr->as.await.expression, env);
            if (inner.is_throwing) return inner;
            Value v = inner.value;
            if (IS_THREAD(v)) {
                // Join the thread and return its result
                ThreadValue* tv = AS_THREAD(v);
                if (!tv->joined) {
                    sage_thread_t* handle = (sage_thread_t*)tv->handle;
                    sage_thread_join(*handle, NULL);
                    tv->joined = 1;
                }
                typedef struct { FunctionValue* func; int arg_count; Value* args; Value result; } SageThreadData;
                SageThreadData* td = (SageThreadData*)tv->data;
                return EVAL_RESULT(td->result);
            }
            // If not a thread, just return the value (already resolved)
            return EVAL_RESULT(v);
        }

        case EXPR_BINARY:
            return eval_binary(&expr->as.binary, env);

        case EXPR_VARIABLE: {
            Value val;
            Token t = expr->as.variable.name;
            if (env_get(env, t.start, t.length, &val)) {
                return EVAL_RESULT(val);
            }
            fprintf(stderr, "Runtime Error: Undefined variable '%.*s'.\n", t.length, t.start);
            return EVAL_RESULT(val_nil());
        }

        case EXPR_CALL: {
            Expr* callee_expr = expr->as.call.callee;

            if (callee_expr->type == EXPR_GET) {
                ExecResult obj_result = eval_expr(callee_expr->as.get.object, env);
                if (obj_result.is_throwing) return obj_result;
                Value object = obj_result.value;

                if (IS_INSTANCE(object)) {
                    Token method_token = callee_expr->as.get.property;
                    char* method_name = SAGE_ALLOC(method_token.length + 1);
                    strncpy(method_name, method_token.start, method_token.length);
                    method_name[method_token.length] = '\0';

                    Method* method = class_find_method(object.as.instance->class_def, method_name, method_token.length);
                    if (!method) {
                        fprintf(stderr, "Runtime Error: Undefined method '%s'.\n", method_name);
                        free(method_name);
                        return EVAL_RESULT(val_nil());
                    }

                    ProcStmt* method_stmt = (ProcStmt*)method->method_stmt;
                    Env* defining = object.as.instance->class_def->defining_env;
                    Env* method_env = env_create(defining ? defining : env);
                    env_define(method_env, "self", 4, object);
                    // Track which class owns this method (for super resolution)
                    ClassValue* owner = class_find_method_owner(object.as.instance->class_def, method_name, method_token.length);
                    if (owner) env_define(method_env, "__class__", 9, val_class(owner));

                    int param_start = (method_stmt->param_count > 0 &&
                                      strncmp(method_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;

                    for (int i = param_start; i < method_stmt->param_count; i++) {
                        if (i - param_start < expr->as.call.arg_count) {
                            ExecResult arg_result = eval_expr(expr->as.call.args[i - param_start], env);
                            if (arg_result.is_throwing) {
                                free(method_name);
                                return arg_result;
                            }
                            env_define(method_env, method_stmt->params[i].start,
                                       method_stmt->params[i].length, arg_result.value);
                        }
                    }

                    ExecResult res = interpret(method_stmt->body, method_env);
                    free(method_name);
                    if (res.is_throwing) return res;
                    return EVAL_RESULT(res.value);
                }
            }

            // super.method(args) — call parent class method
            if (callee_expr->type == EXPR_SUPER) {
                Token method_token = callee_expr->as.super_expr.method;
                // Get 'self' from environment to find the instance
                Value self_val;
                if (!env_get(env, "self", 4, &self_val) || !IS_INSTANCE(self_val)) {
                    fprintf(stderr, "Runtime Error: 'super' can only be used inside a method.\n");
                    return EVAL_RESULT(val_nil());
                }
                // Get __class__ from env (the class owning the current method)
                // If not set, fall back to instance's class
                Value class_ctx;
                ClassValue* current_class;
                if (env_get(env, "__class__", 9, &class_ctx) && class_ctx.type == VAL_CLASS) {
                    current_class = class_ctx.as.class_val;
                } else {
                    current_class = self_val.as.instance->class_def;
                }
                ClassValue* parent_class = current_class->parent;
                if (!parent_class) {
                    fprintf(stderr, "Runtime Error: Class has no parent class for 'super'.\n");
                    return EVAL_RESULT(val_nil());
                }
                char* method_name = SAGE_ALLOC(method_token.length + 1);
                strncpy(method_name, method_token.start, method_token.length);
                method_name[method_token.length] = '\0';

                Method* method = class_find_method(parent_class, method_name, method_token.length);
                if (!method) {
                    fprintf(stderr, "Runtime Error: Parent class has no method '%s'.\n", method_name);
                    free(method_name);
                    return EVAL_RESULT(val_nil());
                }

                ProcStmt* method_stmt = (ProcStmt*)method->method_stmt;
                Env* parent_defining = parent_class->defining_env;
                Env* method_env = env_create(parent_defining ? parent_defining : env);
                // Set __class__ to the parent class so nested super calls resolve correctly
                env_define(method_env, "__class__", 9, val_class(parent_class));

                // super calls: bind all params from explicit args (self is passed explicitly)
                for (int i = 0; i < method_stmt->param_count; i++) {
                    if (i < expr->as.call.arg_count) {
                        ExecResult arg_result = eval_expr(expr->as.call.args[i], env);
                        if (arg_result.is_throwing) {
                            free(method_name);
                            return arg_result;
                        }
                        env_define(method_env, method_stmt->params[i].start,
                                   method_stmt->params[i].length, arg_result.value);
                    }
                }

                ExecResult res = interpret(method_stmt->body, method_env);
                free(method_name);
                if (res.is_throwing) return res;
                return EVAL_RESULT(res.value);
            }

            ExecResult callee_result = eval_expr(callee_expr, env);
            if (callee_result.is_throwing) return callee_result;
            Value callee_value = callee_result.value;

            if (callee_value.type == VAL_NATIVE) {
                if (callee_value.as.native == NULL) {
                    fprintf(stderr, "Runtime Error: Attempted to call a null native function.\n");
                    return EVAL_RESULT(val_nil());
                }
                int count = expr->as.call.arg_count;
                if (count > 255) {
                    fprintf(stderr, "Runtime Error: Too many arguments (%d, max 255).\n", count);
                    return EVAL_RESULT(val_nil());
                }
                Value args[255];
                for (int i = 0; i < count; i++) {
                    ExecResult arg_result = eval_expr(expr->as.call.args[i], env);
                    if (arg_result.is_throwing) return arg_result;
                    args[i] = arg_result.value;
                }
                return EVAL_RESULT(callee_value.as.native(count, args));
            }

            if (callee_value.type == VAL_FUNCTION) {
                if (callee_value.as.function == NULL || callee_value.as.function->proc == NULL) {
                    fprintf(stderr, "Runtime Error: Attempted to call a null function.\n");
                    return EVAL_RESULT(val_nil());
                }
                ProcStmt* func = AS_FUNCTION(callee_value);
                if (expr->as.call.arg_count != func->param_count) {
                    fprintf(stderr, "Runtime Error: Arity mismatch.\n");
                    return EVAL_RESULT(val_nil());
                }

                // Pre-evaluate all arguments
                Value* eval_args = NULL;
                if (func->param_count > 0) {
                    eval_args = SAGE_ALLOC(sizeof(Value) * func->param_count);
                    for (int i = 0; i < func->param_count; i++) {
                        ExecResult arg_result = eval_expr(expr->as.call.args[i], env);
                        if (arg_result.is_throwing) { free(eval_args); return arg_result; }
                        eval_args[i] = arg_result.value;
                    }
                }

                if (callee_value.as.function->is_async) {
#if SAGE_PLATFORM_PICO
                    free(eval_args);
                    fprintf(stderr, "Runtime Error: async/await not supported on RP2040.\n");
                    return EVAL_RESULT(val_nil());
#else
                    // Async call: spawn thread, return thread handle
                    Value spawn_args[1 + func->param_count];
                    spawn_args[0] = callee_value;
                    for (int i = 0; i < func->param_count; i++) {
                        spawn_args[i + 1] = eval_args[i];
                    }
                    free(eval_args);
                    // Use thread_spawn_native from stdlib.c (declared as extern)
                    extern Value thread_spawn_native(int argCount, Value* args);
                    Value handle = thread_spawn_native(1 + func->param_count, spawn_args);
                    return EVAL_RESULT(handle);
#endif
                }

                Env* scope = env_create(callee_value.as.function->closure);
                for (int i = 0; i < func->param_count; i++) {
                    Token paramName = func->params[i];
                    env_define(scope, paramName.start, paramName.length, eval_args[i]);
                }
                free(eval_args);

                ExecResult res = interpret(func->body, scope);
                if (res.is_throwing) return res;
                return EVAL_RESULT(res.value);
            }

            if (callee_value.type == VAL_GENERATOR) {
                GeneratorValue* template = callee_value.as.generator;
                if (expr->as.call.arg_count != template->param_count) {
                    fprintf(stderr, "Runtime Error: Arity mismatch.\n");
                    return EVAL_RESULT(val_nil());
                }

                Env* gen_closure = env_create(template->closure);
                if (template->param_count > 0 && template->params != NULL) {
                    Token* params = (Token*)template->params;
                    for (int i = 0; i < template->param_count; i++) {
                        ExecResult arg_result = eval_expr(expr->as.call.args[i], env);
                        if (arg_result.is_throwing) return arg_result;
                        env_define(gen_closure, params[i].start, params[i].length, arg_result.value);
                    }
                }

                return EVAL_RESULT(val_generator(template->body, template->params,
                                                 template->param_count, gen_closure));
            }

            if (callee_value.type == VAL_CLASS) {
                ClassValue* class_def = callee_value.as.class_val;
                InstanceValue* instance = instance_create(class_def);
                Value inst_val = val_instance(instance);

                Method* init_method = class_find_method(class_def, "init", 4);
                if (init_method) {
                    ProcStmt* init_stmt = (ProcStmt*)init_method->method_stmt;
                    Env* def_env = class_def->defining_env;
                    Env* method_env = env_create(def_env ? def_env : env);
                    env_define(method_env, "self", 4, inst_val);
                    // Track class owning init for super resolution
                    ClassValue* init_owner = class_find_method_owner(class_def, "init", 4);
                    if (init_owner) env_define(method_env, "__class__", 9, val_class(init_owner));

                    int param_start = (init_stmt->param_count > 0 &&
                                      strncmp(init_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;

                    for (int i = param_start; i < init_stmt->param_count; i++) {
                        if (i - param_start < expr->as.call.arg_count) {
                            ExecResult arg_result = eval_expr(expr->as.call.args[i - param_start], env);
                            if (arg_result.is_throwing) return arg_result;
                            env_define(method_env, init_stmt->params[i].start,
                                       init_stmt->params[i].length, arg_result.value);
                        }
                    }

                    ExecResult init_res = interpret(init_stmt->body, method_env);
                    if (init_res.is_throwing) return init_res;
                }

                return EVAL_RESULT(inst_val);
            }

            // Debug: show what was attempted to be called
            if (expr->as.call.callee && expr->as.call.callee->type == EXPR_VARIABLE) {
                fprintf(stderr, "Runtime Error: '%.*s' is not callable (type=%d).\n",
                        expr->as.call.callee->as.variable.name.length,
                        expr->as.call.callee->as.variable.name.start,
                        callee_value.type);
            } else if (expr->as.call.callee && expr->as.call.callee->type == EXPR_GET) {
                fprintf(stderr, "Runtime Error: '.%.*s' is not callable (type=%d).\n",
                        expr->as.call.callee->as.get.property.length,
                        expr->as.call.callee->as.get.property.start,
                        callee_value.type);
            } else {
                fprintf(stderr, "Runtime Error: Value is not callable (type=%d).\n", callee_value.type);
            }
            return EVAL_RESULT(val_nil());
        }

        default:
            return EVAL_RESULT(val_nil());
    }
}

ExecResult interpret(Stmt* stmt, Env* env) {
    if (++g_recursion_depth > MAX_RECURSION_DEPTH) {
        g_recursion_depth--;
        fprintf(stderr, "Runtime Error: Maximum recursion depth exceeded (%d).\n", MAX_RECURSION_DEPTH);
        return EVAL_EXCEPTION(val_exception("Maximum recursion depth exceeded"));
    }
    Env* previous_gc_root = g_gc_root_env;
    g_gc_root_env = env;
    ExecResult result = interpret_inner(stmt, env);
    g_gc_root_env = previous_gc_root;
    g_recursion_depth--;
    return result;
}

static ExecResult interpret_inner(Stmt* stmt, Env* env) {
    static int first_call = 1;
    if (first_call && stmt != NULL) {
        g_global_env = env;
        first_call = 0;
    }
    if (!stmt) return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };

    if (g_generator_resume_target != NULL && stmt != g_generator_resume_target &&
        !stmt_contains_target(stmt, g_generator_resume_target)) {
        return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
    }

    if (stmt == g_generator_resume_target) {
        g_generator_resume_target = NULL;
    }

    switch (stmt->type) {
        case STMT_PRINT: {
            ExecResult result = eval_expr(stmt->as.print.expression, env);
            if (result.is_throwing) return result;
            print_value(result.value);
            printf("\n");
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_LET: {
            Value val = val_nil();
            if (stmt->as.let.initializer != NULL) {
                ExecResult result = eval_expr(stmt->as.let.initializer, env);
                if (result.is_throwing) return result;
                val = result.value;
            }
            Token t = stmt->as.let.name;
            env_define(env, t.start, t.length, val);
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_EXPRESSION: {
            ExecResult result = eval_expr(stmt->as.expression, env);
            if (result.is_throwing) return result;
            // Return actual value (used by REPL to display expression results)
            return (ExecResult){ result.value, 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_BLOCK: {
            Stmt* current = stmt->as.block.statements;
            // Collect deferred statements (LIFO order)
            Stmt* deferred[64];
            int defer_count = 0;
            ExecResult block_result = { val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
            int exiting = 0;

            while (current != NULL) {
                if (current->type == STMT_DEFER) {
                    // Collect defer — don't execute yet
                    if (defer_count < 64) {
                        deferred[defer_count++] = current->as.defer.statement;
                    }
                    current = current->next;
                    continue;
                }
                ExecResult res = interpret(current, env);
                if (res.is_yielding) {
                    if (res.next_stmt == NULL) {
                        res.next_stmt = current->next;
                    }
                    // Run deferred before yielding
                    for (int di = defer_count - 1; di >= 0; di--) {
                        interpret(deferred[di], env);
                    }
                    return res;
                }
                if (res.is_returning || res.is_breaking || res.is_continuing || res.is_throwing) {
                    block_result = res;
                    exiting = 1;
                    break;
                }
                current = current->next;
            }
            // Run deferred statements in LIFO order
            for (int di = defer_count - 1; di >= 0; di--) {
                interpret(deferred[di], env);
            }
            return block_result;
        }

        case STMT_IF: {
            ExecResult cond_result = eval_expr(stmt->as.if_stmt.condition, env);
            if (cond_result.is_throwing) return cond_result;
            
            if (is_truthy(cond_result.value)) {
                return interpret(stmt->as.if_stmt.then_branch, env);
            } else if (stmt->as.if_stmt.else_branch != NULL) {
                return interpret(stmt->as.if_stmt.else_branch, env);
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_WHILE: {
            int iterations = 0;
            while (1) {
                if (++iterations > MAX_LOOP_ITERATIONS) {
                    fprintf(stderr, "Runtime Error: While loop exceeded maximum iterations (%d).\n", MAX_LOOP_ITERATIONS);
                    return EVAL_EXCEPTION(val_exception("While loop exceeded maximum iterations"));
                }
                ExecResult cond_result = eval_expr(stmt->as.while_stmt.condition, env);
                if (cond_result.is_throwing) return cond_result;
                if (!is_truthy(cond_result.value)) break;

                ExecResult res = interpret(stmt->as.while_stmt.body, env);
                if (res.is_returning || res.is_throwing) return res;

                if (res.is_yielding) {
                    if (res.next_stmt == NULL) {
                        res.next_stmt = stmt;
                    }
                    return res;
                }

                if (res.is_breaking) break;
                if (res.is_continuing) continue;
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_FOR: {
            ExecResult iter_result = eval_expr(stmt->as.for_stmt.iterable, env);
            if (iter_result.is_throwing) return iter_result;
            Value iterable = iter_result.value;
            
            if (iterable.type != VAL_ARRAY) {
                fprintf(stderr, "Runtime Error: for loop iterable must be an array.\n");
                return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
            }

            Env* loop_env = env_create(env);
            Token var = stmt->as.for_stmt.variable;

            ArrayValue* arr = iterable.as.array;
            for (int i = 0; i < arr->count; i++) {
                env_define(loop_env, var.start, var.length, arr->elements[i]);

                ExecResult res = interpret(stmt->as.for_stmt.body, loop_env);
                if (res.is_returning || res.is_throwing) return res;
                
                if (res.is_yielding) {
                    if (res.next_stmt == NULL) {
                        res.next_stmt = stmt;
                    }
                    return res;
                }
                
                if (res.is_breaking) break;
                if (res.is_continuing) continue;
            }

            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_BREAK:
            return (ExecResult){ val_nil(), 0, 1, 0, 0, val_nil(), 0, NULL };

        case STMT_CONTINUE:
            return (ExecResult){ val_nil(), 0, 0, 1, 0, val_nil(), 0, NULL };

        // PHASE 8: Modified STMT_PROC to add functions to environment
        case STMT_PROC: {
            Token name = stmt->as.proc.name;
            int is_generator = contains_yield(stmt->as.proc.body);

            Value func_val;
            if (is_generator) {
                func_val = val_generator(stmt->as.proc.body, stmt->as.proc.params,
                                        stmt->as.proc.param_count, env);
            } else {
                func_val = val_function(&stmt->as.proc, env);
            }

            env_define(env, name.start, name.length, func_val);
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_ASYNC_PROC: {
            Token name = stmt->as.async_proc.name;
            Value func_val = val_function(&stmt->as.async_proc, env);
            func_val.as.function->is_async = 1;
            env_define(env, name.start, name.length, func_val);
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_CLASS: {
            ClassValue* parent = NULL;
            if (stmt->as.class_stmt.has_parent) {
                Value parent_val;
                Token parent_name = stmt->as.class_stmt.parent;
                if (env_get(env, parent_name.start, parent_name.length, &parent_val)) {
                    if (parent_val.type == VAL_CLASS) {
                        parent = parent_val.as.class_val;
                    } else {
                        fprintf(stderr, "Runtime Error: Parent must be a class.\n");
                        return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
                    }
                } else {
                    fprintf(stderr, "Runtime Error: Undefined parent class.\n");
                    return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
                }
            }
            
            Token name = stmt->as.class_stmt.name;
            ClassValue* class_val = class_create(name.start, name.length, parent);
            class_val->defining_env = env; // Capture defining environment for method scoping

            Stmt* method = stmt->as.class_stmt.methods;
            while (method != NULL) {
                if (method->type == STMT_PROC) {
                    ProcStmt* proc = &method->as.proc;
                    class_add_method(class_val, proc->name.start, proc->name.length, (void*)proc);
                }
                method = method->next;
            }
            
            Value class_value = val_class(class_val);
            env_define(env, name.start, name.length, class_value);
            
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_RETURN: {
            Value val = val_nil();
            if (stmt->as.ret.value) {
                ExecResult result = eval_expr(stmt->as.ret.value, env);
                if (result.is_throwing) return result;
                val = result.value;
            }
            return (ExecResult){ val, 1, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_TRY: {
            ExecResult try_result = interpret(stmt->as.try_stmt.try_block, env);
            
            if (try_result.is_throwing) {
                for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                    CatchClause* catch_clause = stmt->as.try_stmt.catches[i];
                    Env* catch_env = env_create(env);
                    Token var = catch_clause->exception_var;
                    
                    Value exc_msg;
                    if (IS_EXCEPTION(try_result.exception_value)) {
                        exc_msg = val_string(try_result.exception_value.as.exception->message);
                    } else {
                        exc_msg = try_result.exception_value;
                    }
                    env_define(catch_env, var.start, var.length, exc_msg);
                    
                    ExecResult catch_result = interpret(catch_clause->body, catch_env);
                    if (!catch_result.is_throwing) {
                        try_result = catch_result;
                        break;
                    }
                    try_result = catch_result;
                }
            }
            
            if (stmt->as.try_stmt.finally_block != NULL) {
                ExecResult finally_result = interpret(stmt->as.try_stmt.finally_block, env);
                // Finally control flow overrides try/catch (matches Python/Java semantics)
                if (finally_result.is_throwing) return finally_result;
                if (finally_result.is_returning) return finally_result;
                if (finally_result.is_breaking) return finally_result;
                if (finally_result.is_continuing) return finally_result;
            }

            return try_result;
        }

        case STMT_RAISE: {
            ExecResult exc_result = eval_expr(stmt->as.raise.exception, env);
            if (exc_result.is_throwing) return exc_result;
            
            Value exc_val = exc_result.value;
            if (IS_STRING(exc_val)) {
                exc_val = val_exception(AS_STRING(exc_val));
            } else if (IS_NUMBER(exc_val)) {
                char buf[64];
                snprintf(buf, sizeof(buf), "%.14g", AS_NUMBER(exc_val));
                exc_val = val_exception(buf);
            } else if (IS_BOOL(exc_val)) {
                exc_val = val_exception(AS_BOOL(exc_val) ? "true" : "false");
            } else if (IS_NIL(exc_val)) {
                exc_val = val_exception("nil");
            } else if (!IS_EXCEPTION(exc_val)) {
                exc_val = val_exception("Unknown error");
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 1, exc_val, 0, NULL };
        }

        // PHASE 7: Yield statement execution
        case STMT_YIELD: {
            Value yield_value = val_nil();
            if (stmt->as.yield_stmt.value != NULL) {
                ExecResult result = eval_expr(stmt->as.yield_stmt.value, env);
                if (result.is_throwing) return result;
                yield_value = result.value;
            }
            
            ExecResult result = {0};
            result.value = yield_value;
            result.is_yielding = 1;
            result.next_stmt = stmt->next;
            return result;
        }

        // PHASE 8: Import statement execution
        case STMT_IMPORT: {
            char* module_name = stmt->as.import.module_name;
            char** items = stmt->as.import.items;
            int item_count = stmt->as.import.item_count;
            char* alias = stmt->as.import.alias;
            int import_all_flag = stmt->as.import.import_all;
            
            // Handle different import types
            if (import_all_flag && !alias) {
                // import module_name (no alias)
                if (!import_all(env, module_name)) {
                    fprintf(stderr, "Error: Failed to import module '%s'\n", module_name);
                    return (ExecResult){ val_nil(), 0, 0, 0, 1, val_exception("Import error"), 0, NULL };
                }
            } else if (import_all_flag && alias) {
                // import module_name as alias
                if (!import_as(env, module_name, alias)) {
                    fprintf(stderr, "Error: Failed to import module '%s' as '%s'\n", module_name, alias);
                    return (ExecResult){ val_nil(), 0, 0, 0, 1, val_exception("Import error"), 0, NULL };
                }
            } else {
                // from module_name import item1, item2, ...
                ImportItem* import_items = SAGE_ALLOC(sizeof(ImportItem) * item_count);
                for (int i = 0; i < item_count; i++) {
                    import_items[i].name = items[i];
                    import_items[i].alias = stmt->as.import.item_aliases[i];  // ✅ FIX: Use parsed alias
                }

                if (!import_from(env, module_name, import_items, item_count)) {
                    fprintf(stderr, "Error: Failed to import from module '%s'\n", module_name);
                    free(import_items);
                    return (ExecResult){ val_nil(), 0, 0, 0, 1, val_exception("Import error"), 0, NULL };
                }

                free(import_items);
            }

            
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_MATCH: {
            ExecResult val_res = eval_expr(stmt->as.match_stmt.value, env);
            if (val_res.is_throwing) return val_res;
            Value match_val = val_res.value;

            // Try each case clause
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                CaseClause* clause = stmt->as.match_stmt.cases[i];
                ExecResult pat_res = eval_expr(clause->pattern, env);
                if (pat_res.is_throwing) return pat_res;
                if (values_equal(match_val, pat_res.value)) {
                    return interpret(clause->body, env);
                }
            }
            // No case matched — run default if present
            if (stmt->as.match_stmt.default_case != NULL) {
                return interpret(stmt->as.match_stmt.default_case, env);
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_DEFER:
            // Defer is handled at the block level — collect and run on scope exit.
            // When encountered standalone, just execute immediately (fallback).
            return interpret(stmt->as.defer.statement, env);
    }
    return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
}
