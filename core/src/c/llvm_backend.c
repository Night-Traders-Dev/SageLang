#define _DEFAULT_SOURCE
#include "llvm_backend.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ast.h"
#include "gc.h"
#include "graphics.h"
#include "lexer.h"
#include "parser.h"
#include "pass.h"

// Native C modules that don't have .sage files (handled at runtime)
static int is_native_module(const char *name) {
    const char *natives[] = {"_math",    "math",      "_io",       "io",
                             "thread",    "_thread",   "sys",      "_sys",
                             "socket",    "tcp",       "http",     "ssl",
                             "fat",       "gpu",       "graphics", "ml_native",
                             "compiler",  "vm_native", "vm",       "ffi",
                             "net",       "string",
                             NULL};
    for (int i = 0; natives[i] != NULL; i++) {
        if (strcmp(name, natives[i]) == 0)
            return 1;
    }
    return 0;
}

// ============================================================================
// LLVM IR Text Generation Backend
//
// Emits LLVM IR text (.ll files) that can be compiled with llc + cc.
// Uses the same tagged-union SageValue model as the C backend.
// Runtime functions are declared as external and linked separately.
// ============================================================================

// Forward declaration
extern Stmt* parse_program(const char* source);
static char* token_to_str(Token tok);
static int llvm_resolve_gpu_constant(const char* name, double* out_value);

// ============================================================================
// LLVM Compiler State
// ============================================================================

typedef enum {
    IMPORT_CONST_INVALID = 0,
    IMPORT_CONST_NUMBER,
    IMPORT_CONST_BOOL,
    IMPORT_CONST_STRING,
    IMPORT_CONST_NIL
} ImportConstType;

typedef struct {
    ImportConstType type;
    double number_value;
    int bool_value;
    char* string_value;
} ImportConstValue;

typedef struct {
    char* name;
    ImportConstValue value;
} ImportedConst;

typedef struct {
    char* name;
    char* path;
    char* source;
    Stmt* ast;
} LLVMImportedModule;

typedef struct {
    char* module_name;
    char* member_name;
    char* global_name;
} LLVMImportedGlobal;

typedef struct {
    char* name;
    char** param_names;
    Expr** defaults;
    int param_count;
    int required_count;
} LLVMProcSignature;

typedef struct {
    char* name;
    char** field_names;
    int field_count;
} LLVMStructInfo;

typedef struct {
    char* name;
    char** variant_names;
    int variant_count;
} LLVMEnumInfo;

typedef struct {
    char** items;
    int count;
    int capacity;
} LLVMNameSet;

typedef struct LLVMScopeInfo LLVMScopeInfo;

typedef struct {
    char* binding_name;
    char* module_name;
    char* member_name;
    LLVMScopeInfo* proc_scope;
    char* global_name;
} LLVMImportedValue;

typedef struct {
    char* name;
    char* parent_name;
    ClassStmt* declaration;
} LLVMClassInfo;

typedef struct {
    char* variable;
    char* class_name;
} LLVMValueClassInfo;

typedef struct {
    Stmt* statement;
    LLVMScopeInfo* owner;
    char* symbol;
    char** captures;
    int capture_count;
    char* class_name;
    char* parent_name;
} LLVMTryCallback;

struct LLVMScopeInfo {
    Stmt* declaration;
    ProcStmt* proc;
    LLVMScopeInfo* parent;
    LLVMScopeInfo* first_child;
    LLVMScopeInfo* next_sibling;
    char* symbol;
    char* adapter_symbol;
    LLVMNameSet bound_names;
    LLVMNameSet free_names;
    char** captures;
    int capture_count;
    int capture_capacity;
    int is_nested;
    char* module_name;
    char* signature_name;
};

typedef struct {
    FILE* out;
    const char* input_path;
    int failed;
    int next_reg;       // SSA register counter
    int next_label;     // basic block label counter
    int next_str;       // string constant counter
    // String literal pool
    char** strings;
    int string_count;
    int string_cap;
    // Procedure names
    char** proc_names;
    int proc_count;
    int proc_cap;
    // Global variable names
    char** global_names;
    int global_count;
    int global_cap;
    // Loop label stack for break/continue
    int loop_cond_labels[1024];
    int loop_end_labels[1024];
    int loop_depth;
    // Track whether the current basic block has been terminated (ret/br)
    int block_terminated;
    int deferred_return_active;
    int deferred_return_label;
    int deferred_mode_slot;
    int deferred_return_slot;
    int deferred_exception_slot;
    // Class context for super resolution
    char* current_class_name;
    char* parent_class_name;
    // Imported module tracking (for GPU/graphics support)
    char** imported_modules;
    char** imported_module_names;
    int imported_module_count;
    int imported_module_cap;
    LLVMImportedModule* source_modules;
    int source_module_count;
    int source_module_cap;
    LLVMImportedGlobal* imported_globals;
    int imported_global_count;
    int imported_global_cap;
    LLVMImportedValue* imported_values;
    int imported_value_count;
    int imported_value_cap;
    const char* current_module_name;
    // Imported constants from "from module import CONST [as alias]"
    ImportedConst* imported_consts;
    int imported_const_count;
    int imported_const_cap;
    LLVMProcSignature* proc_signatures;
    int proc_signature_count;
    int proc_signature_cap;
    LLVMStructInfo* struct_infos;
    int struct_info_count;
    int struct_info_cap;
    LLVMEnumInfo* enum_infos;
    int enum_info_count;
    int enum_info_cap;
    LLVMClassInfo* class_infos;
    int class_info_count;
    int class_info_cap;
    LLVMValueClassInfo* value_classes;
    int value_class_count;
    int value_class_cap;
    LLVMScopeInfo* main_scope;
    LLVMScopeInfo** scopes;
    int scope_count;
    int scope_capacity;
    int next_nested_id;
    LLVMScopeInfo* current_scope;
    LLVMTryCallback* current_try_callback;
    LLVMTryCallback* try_callbacks;
    int try_callback_count;
    int try_callback_capacity;
    int next_try_id;
} LLVMCompiler;

static void llc_add_global_once(LLVMCompiler* lc, const char* name);

static int llc_has_module(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->imported_module_count; i++) {
        if (strcmp(lc->imported_modules[i], name) == 0) return 1;
    }
    return 0;
}

static const char* llc_module_name_for_binding(const LLVMCompiler* lc, const char* binding) {
    for (int i = 0; i < lc->imported_module_count; i++) {
        if (strcmp(lc->imported_modules[i], binding) == 0) {
            return lc->imported_module_names[i];
        }
    }
    return NULL;
}

static void llc_add_module_binding(LLVMCompiler* lc, const char* module_name,
                                   const char* binding) {
    if (module_name == NULL || binding == NULL) return;
    for (int i = 0; i < lc->imported_module_count; i++) {
        if (strcmp(lc->imported_modules[i], binding) == 0) {
            return;
        }
    }
    if (lc->imported_module_count >= lc->imported_module_cap) {
        lc->imported_module_cap = lc->imported_module_cap ? lc->imported_module_cap * 2 : 8;
        lc->imported_modules = SAGE_REALLOC(lc->imported_modules,
            sizeof(char*) * (size_t)lc->imported_module_cap);
        lc->imported_module_names = SAGE_REALLOC(lc->imported_module_names,
            sizeof(char*) * (size_t)lc->imported_module_cap);
    }
    lc->imported_modules[lc->imported_module_count] = SAGE_STRDUP(binding);
    lc->imported_module_names[lc->imported_module_count] = SAGE_STRDUP(module_name);
    lc->imported_module_count++;
}

static LLVMImportedModule* llc_find_source_module(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->source_module_count; i++) {
        if (strcmp(lc->source_modules[i].name, name) == 0) {
            return &lc->source_modules[i];
        }
    }
    return NULL;
}

static LLVMImportedGlobal* llc_find_imported_global(LLVMCompiler* lc,
                                                    const char* module_name,
                                                    const char* member_name) {
    for (int i = 0; i < lc->imported_global_count; i++) {
        if (strcmp(lc->imported_globals[i].module_name, module_name) == 0 &&
            strcmp(lc->imported_globals[i].member_name, member_name) == 0) {
            return &lc->imported_globals[i];
        }
    }
    return NULL;
}

static void llvm_append_symbol_part(char* out, size_t capacity, const char* name) {
    size_t index = 0;
    for (size_t i = 0; name != NULL && name[i] != '\0' && index + 1 < capacity; i++) {
        unsigned char ch = (unsigned char)name[i];
        out[index++] = (isalnum(ch) || ch == '_') ? (char)ch : '_';
    }
    out[index] = '\0';
}

static void llc_add_imported_global(LLVMCompiler* lc, const char* module_name,
                                    const char* member_name) {
    if (module_name == NULL || member_name == NULL ||
        llc_find_imported_global(lc, module_name, member_name) != NULL) {
        return;
    }
    if (lc->imported_global_count >= lc->imported_global_cap) {
        lc->imported_global_cap = lc->imported_global_cap ? lc->imported_global_cap * 2 : 8;
        lc->imported_globals = SAGE_REALLOC(
            lc->imported_globals,
            sizeof(LLVMImportedGlobal) * (size_t)lc->imported_global_cap);
    }
    LLVMImportedModule* module = llc_find_source_module(lc, module_name);
    int module_index = module != NULL ? (int)(module - lc->source_modules) : 0;
    char member[256];
    llvm_append_symbol_part(member, sizeof(member), member_name);
    size_t size = strlen(member) + 48;
    char* global_name = SAGE_ALLOC(size);
    snprintf(global_name, size, "sage_modglob_%d_%s", module_index, member);
    llc_add_global_once(lc, global_name);

    LLVMImportedGlobal* global = &lc->imported_globals[lc->imported_global_count++];
    global->module_name = SAGE_STRDUP(module_name);
    global->member_name = SAGE_STRDUP(member_name);
    global->global_name = global_name;
}

static LLVMImportedValue* llc_find_imported_value(LLVMCompiler* lc,
                                                   const char* binding_name,
                                                   const char* module_name,
                                                   const char* member_name) {
    for (int i = 0; i < lc->imported_value_count; i++) {
        LLVMImportedValue* value = &lc->imported_values[i];
        if (binding_name != NULL && strcmp(value->binding_name, binding_name) != 0) continue;
        if (binding_name == NULL && strcmp(value->module_name, module_name) != 0) continue;
        if (strcmp(value->member_name, member_name) == 0) return value;
    }
    return NULL;
}

static LLVMImportedValue* llc_find_imported_binding_value(LLVMCompiler* lc,
                                                           const char* binding_name) {
    if (binding_name == NULL) return NULL;
    for (int i = 0; i < lc->imported_value_count; i++) {
        if (strcmp(lc->imported_values[i].binding_name, binding_name) == 0) {
            return &lc->imported_values[i];
        }
    }
    return NULL;
}

static void llc_add_imported_value(LLVMCompiler* lc, const char* binding_name,
                                   const char* module_name, const char* member_name,
                                   LLVMScopeInfo* proc_scope, const char* global_name) {
    if (binding_name == NULL || module_name == NULL || member_name == NULL) return;
    LLVMImportedValue* existing = llc_find_imported_value(
        lc, binding_name, module_name, member_name);
    if (existing != NULL) {
        if (existing->proc_scope == NULL) existing->proc_scope = proc_scope;
        if (existing->global_name == NULL && global_name != NULL) {
            existing->global_name = SAGE_STRDUP(global_name);
        }
        return;
    }
    if (lc->imported_value_count >= lc->imported_value_cap) {
        lc->imported_value_cap = lc->imported_value_cap ? lc->imported_value_cap * 2 : 16;
        lc->imported_values = SAGE_REALLOC(
            lc->imported_values,
            sizeof(LLVMImportedValue) * (size_t)lc->imported_value_cap);
    }
    LLVMImportedValue* value = &lc->imported_values[lc->imported_value_count++];
    value->binding_name = SAGE_STRDUP(binding_name);
    value->module_name = SAGE_STRDUP(module_name);
    value->member_name = SAGE_STRDUP(member_name);
    value->proc_scope = proc_scope;
    value->global_name = global_name != NULL ? SAGE_STRDUP(global_name) : NULL;
}

static ImportConstValue import_const_invalid(void) {
    ImportConstValue v;
    memset(&v, 0, sizeof(v));
    v.type = IMPORT_CONST_INVALID;
    return v;
}

static ImportConstValue import_const_number(double value) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_NUMBER;
    v.number_value = value;
    return v;
}

static ImportConstValue import_const_bool(int value) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_BOOL;
    v.bool_value = value ? 1 : 0;
    return v;
}

static ImportConstValue import_const_string(const char* value) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_STRING;
    v.string_value = SAGE_STRDUP(value);
    return v;
}

static ImportConstValue import_const_nil(void) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_NIL;
    return v;
}

static void import_const_value_free(ImportConstValue* value) {
    if (value == NULL) return;
    if (value->type == IMPORT_CONST_STRING) {
        free(value->string_value);
    }
    value->string_value = NULL;
    value->type = IMPORT_CONST_INVALID;
}

static ImportConstValue import_const_value_clone(const ImportConstValue* value) {
    if (value == NULL) return import_const_invalid();
    switch (value->type) {
        case IMPORT_CONST_NUMBER:
            return import_const_number(value->number_value);
        case IMPORT_CONST_BOOL:
            return import_const_bool(value->bool_value);
        case IMPORT_CONST_STRING:
            return import_const_string(value->string_value ? value->string_value : "");
        case IMPORT_CONST_NIL:
            return import_const_nil();
        default:
            return import_const_invalid();
    }
}

static ImportedConst* llc_find_imported_const(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->imported_const_count; i++) {
        if (strcmp(lc->imported_consts[i].name, name) == 0) {
            return &lc->imported_consts[i];
        }
    }
    return NULL;
}

static void llc_set_imported_const(LLVMCompiler* lc, const char* name, const ImportConstValue* value) {
    if (name == NULL || value == NULL || value->type == IMPORT_CONST_INVALID) return;

    ImportedConst* existing = llc_find_imported_const(lc, name);
    if (existing != NULL) {
        import_const_value_free(&existing->value);
        existing->value = import_const_value_clone(value);
        return;
    }

    if (lc->imported_const_count >= lc->imported_const_cap) {
        lc->imported_const_cap = lc->imported_const_cap ? lc->imported_const_cap * 2 : 16;
        lc->imported_consts = SAGE_REALLOC(
            lc->imported_consts,
            sizeof(ImportedConst) * (size_t)lc->imported_const_cap
        );
    }
    lc->imported_consts[lc->imported_const_count].name = SAGE_STRDUP(name);
    lc->imported_consts[lc->imported_const_count].value = import_const_value_clone(value);
    lc->imported_const_count++;
}

static int llc_new_reg(LLVMCompiler* lc) {
    return lc->next_reg++;
}

static int llc_new_label(LLVMCompiler* lc) {
    return lc->next_label++;
}

static int llc_add_string(LLVMCompiler* lc, const char* str) {
    if (lc->string_count >= lc->string_cap) {
        lc->string_cap = lc->string_cap ? lc->string_cap * 2 : 16;
        lc->strings = SAGE_REALLOC(lc->strings, sizeof(char*) * (size_t)lc->string_cap);
    }
    lc->strings[lc->string_count] = SAGE_STRDUP(str);
    return lc->string_count++;
}

static void llc_add_proc(LLVMCompiler* lc, const char* name) {
    if (lc->proc_count >= lc->proc_cap) {
        lc->proc_cap = lc->proc_cap ? lc->proc_cap * 2 : 16;
        lc->proc_names = SAGE_REALLOC(lc->proc_names, sizeof(char*) * (size_t)lc->proc_cap);
    }
    lc->proc_names[lc->proc_count++] = SAGE_STRDUP(name);
}

static void llc_add_global(LLVMCompiler* lc, const char* name) {
    if (lc->global_count >= lc->global_cap) {
        lc->global_cap = lc->global_cap ? lc->global_cap * 2 : 16;
        lc->global_names = SAGE_REALLOC(lc->global_names, sizeof(char*) * (size_t)lc->global_cap);
    }
    lc->global_names[lc->global_count++] = SAGE_STRDUP(name);
}

static int llc_has_global(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->global_count; i++) {
        if (strcmp(lc->global_names[i], name) == 0) return 1;
    }
    return 0;
}

static void llc_add_global_once(LLVMCompiler* lc, const char* name) {
    if (!llc_has_global(lc, name)) llc_add_global(lc, name);
}

static LLVMProcSignature* llc_find_proc_signature(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->proc_signature_count; i++) {
        if (strcmp(lc->proc_signatures[i].name, name) == 0) {
            return &lc->proc_signatures[i];
        }
    }
    return NULL;
}

static void llc_add_proc_signature(LLVMCompiler* lc, const char* name, ProcStmt* proc) {
    if (name == NULL || proc == NULL || llc_find_proc_signature(lc, name) != NULL) return;

    if (lc->proc_signature_count >= lc->proc_signature_cap) {
        lc->proc_signature_cap = lc->proc_signature_cap ? lc->proc_signature_cap * 2 : 16;
        lc->proc_signatures = SAGE_REALLOC(
            lc->proc_signatures,
            sizeof(LLVMProcSignature) * (size_t)lc->proc_signature_cap
        );
    }

    LLVMProcSignature* sig = &lc->proc_signatures[lc->proc_signature_count++];
    memset(sig, 0, sizeof(*sig));
    sig->name = SAGE_STRDUP(name);
    sig->param_count = proc->param_count > 0 ? proc->param_count : 0;
    sig->required_count = proc->required_count;
    if (sig->required_count < 0 || sig->required_count > sig->param_count) {
        sig->required_count = sig->param_count;
    }
    if (sig->param_count > 0) {
        sig->param_names = SAGE_ALLOC(sizeof(char*) * (size_t)sig->param_count);
        sig->defaults = SAGE_ALLOC(sizeof(Expr*) * (size_t)sig->param_count);
        for (int i = 0; i < sig->param_count; i++) {
            if (proc->params != NULL && proc->params[i].start != NULL) {
                sig->param_names[i] = token_to_str(proc->params[i]);
            } else {
                sig->param_names[i] = SAGE_STRDUP("");
            }
            sig->defaults[i] = proc->defaults != NULL ? proc->defaults[i] : NULL;
        }
    }
}

static LLVMStructInfo* llc_find_struct_info(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->struct_info_count; i++) {
        if (strcmp(lc->struct_infos[i].name, name) == 0) return &lc->struct_infos[i];
    }
    return NULL;
}

static void llc_add_struct_info(LLVMCompiler* lc, const char* name, StructStmt* stmt) {
    if (name == NULL || stmt == NULL || llc_find_struct_info(lc, name) != NULL) return;
    if (lc->struct_info_count >= lc->struct_info_cap) {
        lc->struct_info_cap = lc->struct_info_cap ? lc->struct_info_cap * 2 : 8;
        lc->struct_infos = SAGE_REALLOC(
            lc->struct_infos,
            sizeof(LLVMStructInfo) * (size_t)lc->struct_info_cap
        );
    }
    LLVMStructInfo* info = &lc->struct_infos[lc->struct_info_count++];
    memset(info, 0, sizeof(*info));
    info->name = SAGE_STRDUP(name);
    info->field_count = stmt->field_count > 0 ? stmt->field_count : 0;
    if (info->field_count > 0) {
        info->field_names = SAGE_ALLOC(sizeof(char*) * (size_t)info->field_count);
        for (int i = 0; i < info->field_count; i++) {
            if (stmt->field_names != NULL && stmt->field_names[i].start != NULL) {
                info->field_names[i] = token_to_str(stmt->field_names[i]);
            } else {
                info->field_names[i] = SAGE_STRDUP("");
            }
        }
    }
}

static LLVMEnumInfo* llc_find_enum_info(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->enum_info_count; i++) {
        if (strcmp(lc->enum_infos[i].name, name) == 0) return &lc->enum_infos[i];
    }
    return NULL;
}

static void llc_add_enum_info(LLVMCompiler* lc, const char* name, EnumStmt* stmt) {
    if (name == NULL || stmt == NULL || llc_find_enum_info(lc, name) != NULL) return;
    if (lc->enum_info_count >= lc->enum_info_cap) {
        lc->enum_info_cap = lc->enum_info_cap ? lc->enum_info_cap * 2 : 8;
        lc->enum_infos = SAGE_REALLOC(
            lc->enum_infos,
            sizeof(LLVMEnumInfo) * (size_t)lc->enum_info_cap
        );
    }
    LLVMEnumInfo* info = &lc->enum_infos[lc->enum_info_count++];
    memset(info, 0, sizeof(*info));
    info->name = SAGE_STRDUP(name);
    info->variant_count = stmt->variant_count > 0 ? stmt->variant_count : 0;
    if (info->variant_count > 0) {
        info->variant_names = SAGE_ALLOC(sizeof(char*) * (size_t)info->variant_count);
        for (int i = 0; i < info->variant_count; i++) {
            if (stmt->variant_names != NULL && stmt->variant_names[i].start != NULL) {
                info->variant_names[i] = token_to_str(stmt->variant_names[i]);
            } else {
                info->variant_names[i] = SAGE_STRDUP("");
            }
        }
    }
}

static LLVMClassInfo* llc_find_class_info(LLVMCompiler* lc, const char* name) {
    if (name == NULL) return NULL;
    for (int i = 0; i < lc->class_info_count; i++) {
        if (strcmp(lc->class_infos[i].name, name) == 0) return &lc->class_infos[i];
    }
    return NULL;
}

static void llc_add_class_info(LLVMCompiler* lc, ClassStmt* stmt) {
    if (stmt == NULL || stmt->name.start == NULL) return;
    char* name = token_to_str(stmt->name);
    if (llc_find_class_info(lc, name) != NULL) {
        free(name);
        return;
    }
    if (lc->class_info_count >= lc->class_info_cap) {
        lc->class_info_cap = lc->class_info_cap ? lc->class_info_cap * 2 : 8;
        lc->class_infos = SAGE_REALLOC(lc->class_infos,
            sizeof(LLVMClassInfo) * (size_t)lc->class_info_cap);
    }
    LLVMClassInfo* info = &lc->class_infos[lc->class_info_count++];
    memset(info, 0, sizeof(*info));
    info->name = name;
    info->declaration = stmt;
    if (stmt->has_parent && stmt->parent.start != NULL) {
        info->parent_name = token_to_str(stmt->parent);
    }
}

static void llc_add_value_class(LLVMCompiler* lc, const char* variable,
                                  const char* class_name) {
    if (variable == NULL || class_name == NULL) return;
    for (int i = 0; i < lc->value_class_count; i++) {
        if (strcmp(lc->value_classes[i].variable, variable) == 0) {
            free(lc->value_classes[i].class_name);
            lc->value_classes[i].class_name = SAGE_STRDUP(class_name);
            return;
        }
    }
    if (lc->value_class_count >= lc->value_class_cap) {
        lc->value_class_cap = lc->value_class_cap ? lc->value_class_cap * 2 : 8;
        lc->value_classes = SAGE_REALLOC(
            lc->value_classes,
            sizeof(LLVMValueClassInfo) * (size_t)lc->value_class_cap);
    }
    lc->value_classes[lc->value_class_count].variable = SAGE_STRDUP(variable);
    lc->value_classes[lc->value_class_count].class_name = SAGE_STRDUP(class_name);
    lc->value_class_count++;
}

static const char* llc_find_value_class(LLVMCompiler* lc, const char* variable) {
    if (variable == NULL) return NULL;
    for (int i = 0; i < lc->value_class_count; i++) {
        if (strcmp(lc->value_classes[i].variable, variable) == 0) {
            return lc->value_classes[i].class_name;
        }
    }
    return NULL;
}

static int llvm_name_set_has(const LLVMNameSet* set, const char* name) {
    if (set == NULL || name == NULL) return 0;
    for (int i = 0; i < set->count; i++) {
        if (strcmp(set->items[i], name) == 0) return 1;
    }
    return 0;
}

static void llvm_name_set_add(LLVMNameSet* set, const char* name) {
    if (set == NULL || name == NULL || name[0] == '\0' || llvm_name_set_has(set, name)) return;
    if (set->count >= set->capacity) {
        set->capacity = set->capacity ? set->capacity * 2 : 16;
        set->items = SAGE_REALLOC(set->items, sizeof(char*) * (size_t)set->capacity);
    }
    set->items[set->count++] = SAGE_STRDUP(name);
}

static void llvm_name_set_free(LLVMNameSet* set) {
    if (set == NULL) return;
    for (int i = 0; i < set->count; i++) free(set->items[i]);
    free(set->items);
    memset(set, 0, sizeof(*set));
}

static LLVMScopeInfo* llc_find_scope(LLVMCompiler* lc, Stmt* declaration) {
    for (int i = 0; i < lc->scope_count; i++) {
        if (lc->scopes[i]->declaration == declaration) return lc->scopes[i];
    }
    return NULL;
}

static LLVMScopeInfo* llc_find_top_scope_by_name(LLVMCompiler* lc, const char* name) {
    if (name == NULL) return NULL;
    size_t length = strlen(name);
    const char* module_name = lc->current_scope != NULL &&
                             lc->current_scope->module_name != NULL
        ? lc->current_scope->module_name : lc->current_module_name;
    LLVMScopeInfo* fallback = NULL;
    for (int i = 0; i < lc->scope_count; i++) {
        LLVMScopeInfo* scope = lc->scopes[i];
        if (scope->is_nested || scope->proc == NULL) continue;
        Token token = scope->proc->name;
        if ((size_t)token.length != length ||
            strncmp(token.start, name, length) != 0) {
            continue;
        }
        if (module_name != NULL && scope->module_name != NULL &&
            strcmp(scope->module_name, module_name) == 0) {
            return scope;
        }
        if (fallback == NULL) fallback = scope;
    }
    return fallback;
}

static LLVMScopeInfo* llc_find_scope_by_qualified_name(LLVMCompiler* lc,
                                                        const char* name) {
    if (name == NULL) return NULL;
    size_t length = strlen(name);
    for (int i = 0; i < lc->scope_count; i++) {
        LLVMScopeInfo* scope = lc->scopes[i];
        if (scope->is_nested || scope->proc == NULL) continue;
        const char* prefix = "sage_fn_";
        size_t prefix_length = strlen(prefix);
        if (strncmp(scope->symbol, prefix, prefix_length) == 0 &&
            strlen(scope->symbol) == prefix_length + length &&
            strcmp(scope->symbol + prefix_length, name) == 0) {
            return scope;
        }
    }
    return NULL;
}

static LLVMScopeInfo* llc_add_scope(LLVMCompiler* lc, Stmt* declaration,
                                    LLVMScopeInfo* parent, const char* symbol,
                                    int is_nested) {
    LLVMScopeInfo* existing = llc_find_scope(lc, declaration);
    if (existing != NULL) return existing;
    if (lc->scope_count >= lc->scope_capacity) {
        lc->scope_capacity = lc->scope_capacity ? lc->scope_capacity * 2 : 16;
        lc->scopes = SAGE_REALLOC(lc->scopes,
            sizeof(LLVMScopeInfo*) * (size_t)lc->scope_capacity);
    }
    LLVMScopeInfo* scope = SAGE_ALLOC(sizeof(LLVMScopeInfo));
    memset(scope, 0, sizeof(*scope));
    scope->declaration = declaration;
    scope->proc = declaration != NULL && declaration->type == STMT_PROC
        ? &declaration->as.proc : NULL;
    scope->parent = parent;
    scope->symbol = SAGE_STRDUP(symbol != NULL ? symbol : "");
    size_t adapter_size = strlen(scope->symbol) + 16;
    scope->adapter_symbol = SAGE_ALLOC(adapter_size);
    snprintf(scope->adapter_symbol, adapter_size, "sage_call_%s", scope->symbol);
    scope->is_nested = is_nested;
    if (parent != NULL && parent->module_name != NULL) {
        scope->module_name = SAGE_STRDUP(parent->module_name);
    }
    if (parent != NULL) {
        scope->next_sibling = parent->first_child;
        parent->first_child = scope;
    }
    lc->scopes[lc->scope_count++] = scope;
    return scope;
}

static void llc_add_scope_capture(LLVMScopeInfo* scope, const char* name) {
    for (int i = 0; i < scope->capture_count; i++) {
        if (strcmp(scope->captures[i], name) == 0) return;
    }
    if (scope->capture_count >= scope->capture_capacity) {
        scope->capture_capacity = scope->capture_capacity ? scope->capture_capacity * 2 : 8;
        scope->captures = SAGE_REALLOC(scope->captures,
            sizeof(char*) * (size_t)scope->capture_capacity);
    }
    scope->captures[scope->capture_count++] = SAGE_STRDUP(name);
}

static void llc_free(LLVMCompiler* lc) {
    for (int i = 0; i < lc->string_count; i++) free(lc->strings[i]);
    free(lc->strings);
    for (int i = 0; i < lc->proc_count; i++) free(lc->proc_names[i]);
    free(lc->proc_names);
    for (int i = 0; i < lc->global_count; i++) free(lc->global_names[i]);
    free(lc->global_names);
    for (int i = 0; i < lc->imported_module_count; i++) {
        free(lc->imported_modules[i]);
        free(lc->imported_module_names[i]);
    }
    free(lc->imported_modules);
    free(lc->imported_module_names);
    for (int i = 0; i < lc->source_module_count; i++) {
        free(lc->source_modules[i].name);
        free(lc->source_modules[i].path);
        free_stmt(lc->source_modules[i].ast);
        free(lc->source_modules[i].source);
    }
    free(lc->source_modules);
    for (int i = 0; i < lc->imported_global_count; i++) {
        free(lc->imported_globals[i].module_name);
        free(lc->imported_globals[i].member_name);
        free(lc->imported_globals[i].global_name);
    }
    free(lc->imported_globals);
    for (int i = 0; i < lc->imported_value_count; i++) {
        free(lc->imported_values[i].binding_name);
        free(lc->imported_values[i].module_name);
        free(lc->imported_values[i].member_name);
        free(lc->imported_values[i].global_name);
    }
    free(lc->imported_values);
    for (int i = 0; i < lc->imported_const_count; i++) {
        free(lc->imported_consts[i].name);
        import_const_value_free(&lc->imported_consts[i].value);
    }
    free(lc->imported_consts);
    for (int i = 0; i < lc->proc_signature_count; i++) {
        free(lc->proc_signatures[i].name);
        for (int j = 0; j < lc->proc_signatures[i].param_count; j++) {
            free(lc->proc_signatures[i].param_names[j]);
        }
        free(lc->proc_signatures[i].param_names);
        free(lc->proc_signatures[i].defaults);
    }
    free(lc->proc_signatures);
    for (int i = 0; i < lc->struct_info_count; i++) {
        free(lc->struct_infos[i].name);
        for (int j = 0; j < lc->struct_infos[i].field_count; j++) {
            free(lc->struct_infos[i].field_names[j]);
        }
        free(lc->struct_infos[i].field_names);
    }
    free(lc->struct_infos);
    for (int i = 0; i < lc->enum_info_count; i++) {
        free(lc->enum_infos[i].name);
        for (int j = 0; j < lc->enum_infos[i].variant_count; j++) {
            free(lc->enum_infos[i].variant_names[j]);
        }
        free(lc->enum_infos[i].variant_names);
    }
    free(lc->enum_infos);
    for (int i = 0; i < lc->class_info_count; i++) {
        free(lc->class_infos[i].name);
        free(lc->class_infos[i].parent_name);
    }
    free(lc->class_infos);
    for (int i = 0; i < lc->value_class_count; i++) {
        free(lc->value_classes[i].variable);
        free(lc->value_classes[i].class_name);
    }
    free(lc->value_classes);
    for (int i = 0; i < lc->try_callback_count; i++) {
        LLVMTryCallback* callback = &lc->try_callbacks[i];
        free(callback->symbol);
        for (int j = 0; j < callback->capture_count; j++) free(callback->captures[j]);
        free(callback->captures);
        free(callback->class_name);
        free(callback->parent_name);
    }
    free(lc->try_callbacks);
    for (int i = 0; i < lc->scope_count; i++) {
        LLVMScopeInfo* scope = lc->scopes[i];
        free(scope->symbol);
        free(scope->adapter_symbol);
        llvm_name_set_free(&scope->bound_names);
        llvm_name_set_free(&scope->free_names);
        for (int j = 0; j < scope->capture_count; j++) free(scope->captures[j]);
        free(scope->captures);
        free(scope->module_name);
        free(scope->signature_name);
        free(scope);
    }
    free(lc->scopes);
}

// ============================================================================
// LLVM IR Output Helpers
// ============================================================================

static void ll_emit(LLVMCompiler* lc, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(lc->out, fmt, args);
    va_end(args);
}

static void ll_line(LLVMCompiler* lc, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fputs("  ", lc->out);
    vfprintf(lc->out, fmt, args);
    fputc('\n', lc->out);
    va_end(args);
}

// ============================================================================
// Token to string helper
// ============================================================================

static char* token_to_str(Token tok) {
    char* s = SAGE_ALLOC((size_t)tok.length + 1);
    memcpy(s, tok.start, (size_t)tok.length);
    s[tok.length] = '\0';
    return s;
}

typedef struct {
    char* name;
    ImportConstValue value;
} ModuleConst;

static int import_const_truthy(const ImportConstValue* value) {
    if (value == NULL) return 0;
    switch (value->type) {
        case IMPORT_CONST_NIL:
            return 0;
        case IMPORT_CONST_BOOL:
            return value->bool_value ? 1 : 0;
        case IMPORT_CONST_NUMBER:
            return value->number_value != 0.0;
        case IMPORT_CONST_STRING:
            return value->string_value != NULL && value->string_value[0] != '\0';
        default:
            return 0;
    }
}

static int import_const_number_to_i64(const ImportConstValue* value, long long* out) {
    if (value == NULL || out == NULL) return 0;
    if (value->type != IMPORT_CONST_NUMBER) return 0;
    *out = (long long)value->number_value;
    return 1;
}

static int module_const_find_index(ModuleConst* consts, int count, const char* name) {
    for (int i = 0; i < count; i++) {
        if (strcmp(consts[i].name, name) == 0) return i;
    }
    return -1;
}

static ModuleConst* module_const_find(ModuleConst* consts, int count, const char* name) {
    int idx = module_const_find_index(consts, count, name);
    if (idx >= 0) return &consts[idx];
    return NULL;
}

static void module_const_set(ModuleConst** consts, int* count, int* cap,
                             const char* name, const ImportConstValue* value) {
    if (consts == NULL || count == NULL || cap == NULL || name == NULL || value == NULL) return;
    if (value->type == IMPORT_CONST_INVALID) return;

    int idx = module_const_find_index(*consts, *count, name);
    if (idx >= 0) {
        import_const_value_free(&(*consts)[idx].value);
        (*consts)[idx].value = import_const_value_clone(value);
        return;
    }

    if (*count >= *cap) {
        *cap = *cap ? *cap * 2 : 16;
        *consts = SAGE_REALLOC(*consts, sizeof(ModuleConst) * (size_t)*cap);
    }
    (*consts)[*count].name = SAGE_STRDUP(name);
    (*consts)[*count].value = import_const_value_clone(value);
    (*count)++;
}

static void module_const_free_all(ModuleConst* consts, int count) {
    for (int i = 0; i < count; i++) {
        free(consts[i].name);
        import_const_value_free(&consts[i].value);
    }
    free(consts);
}

static char* llvm_read_file_contents(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long size = ftell(f);
    if (size < 0 || size > 100L * 1024L * 1024L) {
        fclose(f);
        return NULL;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }
    char* buf = SAGE_ALLOC((size_t)size + 1);
    size_t nread = fread(buf, 1, (size_t)size, f);
    buf[nread] = '\0';
    fclose(f);
    return buf;
}

static char* resolve_module_path_for_llvm(const LLVMCompiler* lc, const char* module_name) {
    if (module_name == NULL || module_name[0] == '\0') return NULL;

    // Keep module-name validation aligned with the runtime resolver.
    for (const char* p = module_name; *p != '\0'; p++) {
        if (!((*p >= 'a' && *p <= 'z') ||
              (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') ||
              *p == '_' || *p == '.')) {
            return NULL;
        }
    }
    if (strstr(module_name, "..") != NULL) return NULL;

    char dir[PATH_MAX];
    if (lc->input_path != NULL) {
        strncpy(dir, lc->input_path, sizeof(dir) - 1);
        dir[sizeof(dir) - 1] = '\0';
        char* slash = strrchr(dir, '/');
        if (slash) *(slash + 1) = '\0';
        else strcpy(dir, "./");
    } else {
        strcpy(dir, "./");
    }

    // Convert dots to slashes in module name
    size_t mlen = strlen(module_name);
    char path_name[PATH_MAX];
    if (mlen >= sizeof(path_name)) return NULL;
    for (size_t i = 0; i < mlen; i++) {
        path_name[i] = (module_name[i] == '.') ? '/' : module_name[i];
    }
    path_name[mlen] = '\0';

    char path[PATH_MAX];
    // Search relative to source file directory
    const char* search[] = { "", "lib/", "modules/" };
    size_t dir_len = strlen(dir);
    size_t pn_len = strlen(path_name);
    for (int i = 0; i < 3; i++) {
        size_t s_len = strlen(search[i]);
        if (dir_len + s_len + pn_len + 6 < sizeof(path)) {
            snprintf(path, sizeof(path), "%s%s%s.sage", dir, search[i], path_name);
            if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
            if (dir_len + s_len + pn_len + 15 < sizeof(path)) {
                snprintf(path, sizeof(path), "%s%s%s/__init__.sage", dir, search[i], path_name);
                if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
            }
        }
    }
    // Search relative to CWD
    for (int i = 0; i < 3; i++) {
        size_t s_len = strlen(search[i]);
        if (s_len + pn_len + 8 < sizeof(path)) {
            snprintf(path, sizeof(path), "./%s%s.sage", search[i], path_name);
            if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
            if (s_len + pn_len + 16 < sizeof(path)) {
                snprintf(path, sizeof(path), "./%s%s/__init__.sage", search[i], path_name);
                if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
            }
        }
    }
    // Search installed library path
#ifndef SAGE_LIB_DIR
#define SAGE_LIB_DIR "/usr/local/share/sage/lib"
#endif
    if (strlen(SAGE_LIB_DIR) + pn_len + 7 < sizeof(path)) {
        snprintf(path, sizeof(path), "%s/%s.sage", SAGE_LIB_DIR, path_name);
        if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
    }
    // Search SAGE_PATH
    const char* sage_path = getenv("SAGE_PATH");
    if (sage_path != NULL) {
        char env_buf[4096];
        size_t elen = strlen(sage_path);
        if (elen < sizeof(env_buf)) {
            memcpy(env_buf, sage_path, elen + 1);
            char* start = env_buf;
            for (char* p = env_buf; ; p++) {
                if (*p == ':' || *p == '\0') {
                    char ec = *p;
                    *p = '\0';
                    if (p > start) {
                        if (strlen(start) + pn_len + 7 < sizeof(path)) {
                            snprintf(path, sizeof(path), "%s/%s.sage", start, path_name);
                            if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
                        }
                    }
                    if (ec == '\0') break;
                    start = p + 1;
                }
            }
        }
    }
    return NULL;
}

static Stmt* llvm_parse_program_with_path(const char* source, const char* input_path) {
    init_lexer(source, input_path);
    parser_init();

    Stmt* head = NULL;
    Stmt* tail = NULL;
    while (1) {
        Stmt* stmt = parse();
        if (stmt == NULL) break;
        if (head == NULL) {
            head = stmt;
        } else {
            tail->next = stmt;
        }
        tail = stmt;
    }
    return head;
}

static ImportConstValue llvm_eval_const_expr(Expr* expr, ModuleConst* consts, int const_count) {
    if (expr == NULL) return import_const_invalid();

    switch (expr->type) {
        case EXPR_NUMBER:
            return import_const_number(expr->as.number.value);
        case EXPR_STRING:
            return import_const_string(expr->as.string.value);
        case EXPR_BOOL:
            return import_const_bool(expr->as.boolean.value);
        case EXPR_NIL:
            return import_const_nil();
        case EXPR_VARIABLE: {
            char* name = token_to_str(expr->as.variable.name);
            ModuleConst* hit = module_const_find(consts, const_count, name);
            free(name);
            if (hit == NULL) return import_const_invalid();
            return import_const_value_clone(&hit->value);
        }
        case EXPR_BINARY: {
            Token op = expr->as.binary.op;
            ImportConstValue left = llvm_eval_const_expr(expr->as.binary.left, consts, const_count);
            ImportConstValue right = llvm_eval_const_expr(expr->as.binary.right, consts, const_count);
            ImportConstValue result = import_const_invalid();

            if (op.type == TOKEN_NOT) {
                if (left.type != IMPORT_CONST_INVALID) {
                    result = import_const_bool(!import_const_truthy(&left));
                }
                import_const_value_free(&left);
                import_const_value_free(&right);
                return result;
            }

            if (op.type == TOKEN_PLUS) {
                if (left.type == IMPORT_CONST_NUMBER && right.type == IMPORT_CONST_NUMBER) {
                    result = import_const_number(left.number_value + right.number_value);
                } else if (left.type == IMPORT_CONST_STRING && right.type == IMPORT_CONST_STRING) {
                    size_t llen = strlen(left.string_value);
                    size_t rlen = strlen(right.string_value);
                    char* joined = SAGE_ALLOC(llen + rlen + 1);
                    memcpy(joined, left.string_value, llen);
                    memcpy(joined + llen, right.string_value, rlen + 1);
                    result = import_const_string(joined);
                    free(joined);
                }
            } else if (op.type == TOKEN_MINUS &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_number(left.number_value - right.number_value);
            } else if (op.type == TOKEN_STAR &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_number(left.number_value * right.number_value);
            } else if (op.type == TOKEN_SLASH &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER &&
                       right.number_value != 0.0) {
                result = import_const_number(left.number_value / right.number_value);
            } else if (op.type == TOKEN_PERCENT &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER &&
                       right.number_value != 0.0) {
                result = import_const_number(fmod(left.number_value, right.number_value));
            } else if (op.type == TOKEN_EQ) {
                int equal = 0;
                if (left.type == right.type) {
                    if (left.type == IMPORT_CONST_NUMBER) equal = left.number_value == right.number_value;
                    else if (left.type == IMPORT_CONST_BOOL) equal = left.bool_value == right.bool_value;
                    else if (left.type == IMPORT_CONST_STRING) equal = strcmp(left.string_value, right.string_value) == 0;
                    else if (left.type == IMPORT_CONST_NIL) equal = 1;
                }
                result = import_const_bool(equal);
            } else if (op.type == TOKEN_NEQ) {
                int equal = 0;
                if (left.type == right.type) {
                    if (left.type == IMPORT_CONST_NUMBER) equal = left.number_value == right.number_value;
                    else if (left.type == IMPORT_CONST_BOOL) equal = left.bool_value == right.bool_value;
                    else if (left.type == IMPORT_CONST_STRING) equal = strcmp(left.string_value, right.string_value) == 0;
                    else if (left.type == IMPORT_CONST_NIL) equal = 1;
                }
                result = import_const_bool(!equal);
            } else if (op.type == TOKEN_LT &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value < right.number_value);
            } else if (op.type == TOKEN_GT &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value > right.number_value);
            } else if (op.type == TOKEN_LTE &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value <= right.number_value);
            } else if (op.type == TOKEN_GTE &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value >= right.number_value);
            } else if (op.type == TOKEN_AND) {
                result = import_const_bool(import_const_truthy(&left) && import_const_truthy(&right));
            } else if (op.type == TOKEN_OR) {
                result = import_const_bool(import_const_truthy(&left) || import_const_truthy(&right));
            } else if (op.type == TOKEN_AMP || op.type == TOKEN_PIPE ||
                       op.type == TOKEN_CARET || op.type == TOKEN_LSHIFT ||
                       op.type == TOKEN_RSHIFT) {
                long long li = 0;
                long long ri = 0;
                if (import_const_number_to_i64(&left, &li) && import_const_number_to_i64(&right, &ri)) {
                    if (op.type == TOKEN_AMP) result = import_const_number((double)(li & ri));
                    if (op.type == TOKEN_PIPE) result = import_const_number((double)(li | ri));
                    if (op.type == TOKEN_CARET) result = import_const_number((double)(li ^ ri));
                    if (op.type == TOKEN_LSHIFT) result = import_const_number((double)((unsigned long long)li << ri));
                    if (op.type == TOKEN_RSHIFT) result = import_const_number((double)((unsigned long long)li >> ri));
                }
            }

            import_const_value_free(&left);
            import_const_value_free(&right);
            return result;
        }
        default:
            return import_const_invalid();
    }
}

static void llvm_process_import_constants(LLVMCompiler* lc, ImportStmt* import_stmt) {
    if (import_stmt == NULL || import_stmt->item_count <= 0) return;
    if (import_stmt->module_name == NULL) return;

    // Native module constants — only GPU supports compile-time constants.
    // For non-GPU native modules (tcp, json, sys, etc.), imported items are
    // runtime-resolved functions, not constants — skip without error.
    if (strcmp(import_stmt->module_name, "gpu") != 0 && is_native_module(import_stmt->module_name)) {
        return;
    }

    // Native GPU constants are resolved from the static table.
    if (strcmp(import_stmt->module_name, "gpu") == 0) {
        for (int i = 0; i < import_stmt->item_count; i++) {
            const char* item_name = import_stmt->items[i];
            const char* bind_name = item_name;
            if (import_stmt->item_aliases != NULL && import_stmt->item_aliases[i] != NULL) {
                bind_name = import_stmt->item_aliases[i];
            }
            double value = 0.0;
            if (llvm_resolve_gpu_constant(item_name, &value)) {
                ImportConstValue const_value = import_const_number(value);
                llc_set_imported_const(lc, bind_name, &const_value);
                import_const_value_free(&const_value);
            } else {
                fprintf(stderr,
                        "LLVM backend: unresolved imported constant '%s' from module '%s'\n",
                        item_name, import_stmt->module_name);
                lc->failed = 1;
            }
        }
        return;
    }

    char* module_path = resolve_module_path_for_llvm(lc, import_stmt->module_name);
    if (module_path == NULL) {
        return;
    }

    char* source = llvm_read_file_contents(module_path);
    if (source == NULL) {
        free(module_path);
        return;
    }

    Stmt* module_ast = llvm_parse_program_with_path(source, module_path);

    ModuleConst* consts = NULL;
    int const_count = 0;
    int const_cap = 0;

    for (Stmt* s = module_ast; s != NULL; s = s->next) {
        if (s->type == STMT_LET) {
            char* name = token_to_str(s->as.let.name);
            ImportConstValue value = llvm_eval_const_expr(s->as.let.initializer, consts, const_count);
            if (value.type != IMPORT_CONST_INVALID) {
                module_const_set(&consts, &const_count, &const_cap, name, &value);
            }
            import_const_value_free(&value);
            free(name);
        }
    }

    for (int i = 0; i < import_stmt->item_count; i++) {
        const char* item_name = import_stmt->items[i];
        const char* bind_name = item_name;
        if (import_stmt->item_aliases != NULL && import_stmt->item_aliases[i] != NULL) {
            bind_name = import_stmt->item_aliases[i];
        }
        ModuleConst* hit = module_const_find(consts, const_count, item_name);
        if (hit != NULL) {
            llc_set_imported_const(lc, bind_name, &hit->value);
        }
        // Items that aren't compile-time constants (e.g. functions, procs)
        // will be resolved at runtime through the module object.
    }

    module_const_free_all(consts, const_count);
    free_stmt(module_ast);
    free(source);
    free(module_path);
}

// ============================================================================
// Escape string for LLVM IR string constant
// ============================================================================

static void emit_escaped_string(FILE* out, const char* str) {
    for (const char* p = str; *p; p++) {
        if (*p == '\\') { fputs("\\5C", out); }
        else if (*p == '"') { fputs("\\22", out); }
        else if (*p == '\n') { fputs("\\0A", out); }
        else if (*p == '\r') { fputs("\\0D", out); }
        else if (*p == '\t') { fputs("\\09", out); }
        else if ((unsigned char)*p < 32) { fprintf(out, "\\%02X", (unsigned char)*p); }
        else { fputc(*p, out); }
    }
}

// ============================================================================
// Type Definitions and Runtime Declarations
// ============================================================================

static void emit_type_definitions(LLVMCompiler* lc) {
    ll_emit(lc, "; SageLang LLVM IR - generated by sage compiler\n");
    ll_emit(lc, "target datalayout = \"e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128\"\n");
    ll_emit(lc, "target triple = \"x86_64-pc-linux-gnu\"\n\n");

    // SageValue — must match clang's ABI lowering of:
    //   struct { int32_t type; union { double; void*; int32_t; } as; }
    // clang lowers this to { i32, i64 } for SysV x86_64 ABI.
    ll_emit(lc, "%%SageValue = type { i32, i64 }\n\n");

    // Runtime function declarations
    ll_emit(lc, "; Runtime function declarations\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_number(double)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bool(i32)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_string(i8*)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_nil()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_add(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_sub(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mul(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_div(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mod(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_eq(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_neq(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_lt(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gt(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_lte(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gte(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_and(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_or(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_not(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_neg(%%SageValue)\n");
    ll_emit(lc, "declare void @sage_rt_print(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_str(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_len(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_tonumber(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_new(i32)\n");
    ll_emit(lc, "declare void @sage_rt_array_set(%%SageValue, i32, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_push(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_pop(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_extend(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_reverse(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_contains(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_index_of(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_index(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_is_truthy(%%SageValue)\n");
    ll_emit(lc, "declare i32 @sage_rt_get_bool(%%SageValue)\n");
    // Dict operations
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_new()\n");
    ll_emit(lc, "declare void @sage_rt_dict_set(%%SageValue, i8*, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_get(%%SageValue, i8*)\n");
    // Tuple
    ll_emit(lc, "declare %%SageValue @sage_rt_tuple_new(i32)\n");
    ll_emit(lc, "declare void @sage_rt_tuple_set(%%SageValue, i32, %%SageValue)\n");
    // Slice
    ll_emit(lc, "declare %%SageValue @sage_rt_slice(%%SageValue, %%SageValue, %%SageValue)\n");
    // Property access
    ll_emit(lc, "declare %%SageValue @sage_rt_get_attr(%%SageValue, i8*)\n");
    ll_emit(lc, "declare void @sage_rt_set_attr(%%SageValue, i8*, %%SageValue)\n");
    // Array iteration
    ll_emit(lc, "declare i32 @sage_rt_array_len(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_range(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_range2(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_range3(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare i32 @sage_rt_get_updated_idx(%%SageValue, i32)\n");
    // Index set
    ll_emit(lc, "declare void @sage_rt_index_set(%%SageValue, %%SageValue, %%SageValue)\n");
    // Dict query operations
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_keys(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_values(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_has(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_delete(%%SageValue, %%SageValue)\n");
    // Type query
    ll_emit(lc, "declare %%SageValue @sage_rt_type(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_chr(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_ord(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_asm_arch()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_upper(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_lower(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_strip(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_split(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_join(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_replace(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mem_alloc(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mem_free(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mem_read(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mem_write(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mem_size(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_struct_def(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_struct_new(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_struct_get(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_struct_set(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_struct_size(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_input(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_readfile(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_writefile(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_readbytes(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_writebytes(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_appendbytes(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_exists(%%SageValue)\n");
    // ML native runtime
    ll_emit(lc, "declare %%SageValue @sage_rt_load_weights(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_forward_pass(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_matmul(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_rms_norm(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_silu(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_scale(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_cross_entropy(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    // Dynamic function calls
    ll_emit(lc, "declare %%SageValue @sage_rt_make_function(i8*, i32, i32)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_make_closure(i8*, i32, %%SageValue*, i32, i32)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_closure_get(%%SageValue, i32)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_call_dynamic(%%SageValue, %%SageValue*, i32, i64)\n");
    ll_emit(lc, "declare void @sage_rt_register_class(i8*, i8*)\n");
    ll_emit(lc, "declare void @sage_rt_register_method(i8*, i8*, i8*, i32, i32, i32)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_construct_class(i8*, %%SageValue*, i32, i64)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_call_method(%%SageValue, i8*, %%SageValue*, i32, i64)\n");
    ll_emit(lc, "declare i8* @sage_rt_try_enter()\n");
    ll_emit(lc, "declare i32 @sage_rt_try_run(i8*, i8*, %%SageValue**)\n");
    ll_emit(lc, "declare void @sage_rt_try_leave(i8*)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_exception_value()\n");
    ll_emit(lc, "declare void @sage_rt_raise(%%SageValue) noreturn\n");
    ll_emit(lc, "declare void @sage_rt_try_return(%%SageValue) noreturn\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_try_return_value()\n");
    // Abort (for raise)
    ll_emit(lc, "declare void @abort() noreturn\n");
    // Bitwise operations
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_and(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_or(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_xor(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_not(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_shl(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_shr(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "\n");

    // GPU runtime declarations (linked from gpu_api + llvm_runtime)
    ll_emit(lc, "; GPU runtime declarations\n");
    // Core lifecycle
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_has_vulkan()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_has_opengl()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init_opengl(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_shutdown()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_device_name()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_device_limits()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_last_error()\n");
    // Buffers
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_buffer(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_buffer_upload(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_buffer_download(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_buffer_size(%%SageValue)\n");
    // Images
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_image(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_image_3d(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_image(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_image_dims(%%SageValue)\n");
    // Samplers
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_sampler(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_sampler_advanced(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_sampler(%%SageValue)\n");
    // Shaders
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_shader(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_shader_glsl(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_reload_shader(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_shader(%%SageValue)\n");
    // Descriptors
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_descriptor_layout(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_descriptor_pool(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_allocate_descriptor_set(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_allocate_descriptor_sets(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_descriptor(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_descriptor_image(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_descriptor_range(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    // Pipelines
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_pipeline_layout(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_compute_pipeline(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_graphics_pipeline(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_pipeline(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_pipeline_cache()\n");
    // Render pass / Framebuffer
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_render_pass(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_render_pass_mrt(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_render_pass(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_framebuffer(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_framebuffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_depth_buffer(%%SageValue, %%SageValue, %%SageValue)\n");
    // Commands
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_command_pool(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_command_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_secondary_command_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_begin_commands(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_begin_secondary(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_end_commands(%%SageValue)\n");
    // Command recording
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_compute_pipeline(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_graphics_pipeline(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_descriptor_set(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_dispatch(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_dispatch_indirect(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_push_constants(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_begin_render_pass(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_end_render_pass(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw_indexed(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw_indirect(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw_indexed_indirect(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_vertex_buffer(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_vertex_buffers(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_index_buffer(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_set_viewport(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_set_scissor(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_pipeline_barrier(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_image_barrier(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_copy_buffer(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_copy_buffer_to_image(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_execute_commands(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_queue_transfer_barrier(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    // Sync
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_fence(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_wait_fence(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_reset_fence(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_fence(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_semaphore()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_semaphore(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_submit(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_submit_compute(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_submit_with_sync(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_queue_wait_idle()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_device_wait_idle()\n");
    // Window / Swapchain
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_window(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_window()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_window_should_close()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_poll_events()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init_windowed(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init_opengl_windowed(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_shutdown_windowed()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_swapchain_image_count()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_swapchain_format()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_swapchain_extent()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_acquire_next_image(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_present(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_swapchain_framebuffers(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_swapchain_framebuffers_depth(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_recreate_swapchain()\n");
    // Input
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_pressed(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_down(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_just_pressed(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_just_released(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_pos()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_button(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_just_pressed(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_just_released(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_delta()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_scroll_delta()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_set_cursor_mode(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_get_time()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_window_size()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_set_title(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_window_resized()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_input()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_text_input_available()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_text_input_read()\n");
    // Textures / Upload
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_texture(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_texture_dims(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_generate_mipmaps(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_cubemap(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_upload_device_local(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_upload_bytes(%%SageValue, %%SageValue)\n");
    // Uniform buffers
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_uniform_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_uniform(%%SageValue, %%SageValue)\n");
    // Offscreen / Screenshot
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_offscreen_target(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_screenshot(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_save_screenshot(%%SageValue)\n");
    // Font
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_font(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_atlas(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_set_atlas(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_text_verts(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_measure(%%SageValue, %%SageValue, %%SageValue)\n");
    // glTF
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_gltf(%%SageValue)\n");
    // Queue families
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_graphics_family()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_compute_family()\n");
    // Platform
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_set_platform(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_get_platform()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_detected_platform()\n");
    ll_emit(lc, "\n");
}

// ============================================================================
// GPU Module Constant Resolution
// ============================================================================

typedef struct { const char* name; double value; } GPUConstant;

static const GPUConstant g_gpu_constants[] = {
    // Buffer usage
    {"BUFFER_STORAGE", 0x01}, {"BUFFER_UNIFORM", 0x02}, {"BUFFER_VERTEX", 0x04},
    {"BUFFER_INDEX", 0x08}, {"BUFFER_STAGING", 0x10}, {"BUFFER_INDIRECT", 0x20},
    {"BUFFER_TRANSFER_SRC", 0x40}, {"BUFFER_TRANSFER_DST", 0x80},
    // Memory
    {"MEMORY_DEVICE_LOCAL", 0x01}, {"MEMORY_HOST_VISIBLE", 0x02}, {"MEMORY_HOST_COHERENT", 0x04},
    // Formats
    {"FORMAT_RGBA8", 0}, {"FORMAT_RGBA16F", 1}, {"FORMAT_RGBA32F", 2},
    {"FORMAT_R32F", 3}, {"FORMAT_RG32F", 4}, {"FORMAT_DEPTH32F", 5},
    {"FORMAT_DEPTH24_S8", 6}, {"FORMAT_R8", 7}, {"FORMAT_RG8", 8},
    {"FORMAT_BGRA8", 9}, {"FORMAT_R32U", 10}, {"FORMAT_RG16F", 11},
    {"FORMAT_R16F", 12}, {"FORMAT_SWAPCHAIN", 99},
    // Image usage
    {"IMAGE_SAMPLED", 0x01}, {"IMAGE_STORAGE", 0x02}, {"IMAGE_COLOR_ATTACH", 0x04},
    {"IMAGE_DEPTH_ATTACH", 0x08}, {"IMAGE_TRANSFER_SRC", 0x10}, {"IMAGE_TRANSFER_DST", 0x20},
    {"IMAGE_INPUT_ATTACH", 0x40},
    // Image types
    {"IMAGE_1D", 0}, {"IMAGE_2D", 1}, {"IMAGE_3D", 2}, {"IMAGE_CUBE", 3},
    // Filter
    {"FILTER_NEAREST", 0}, {"FILTER_LINEAR", 1},
    // Address
    {"ADDRESS_REPEAT", 0}, {"ADDRESS_MIRRORED_REPEAT", 1},
    {"ADDRESS_CLAMP_EDGE", 2}, {"ADDRESS_CLAMP_BORDER", 3},
    // Descriptor types
    {"DESC_STORAGE_BUFFER", 0}, {"DESC_UNIFORM_BUFFER", 1}, {"DESC_SAMPLED_IMAGE", 2},
    {"DESC_STORAGE_IMAGE", 3}, {"DESC_SAMPLER", 4}, {"DESC_COMBINED_SAMPLER", 5},
    // Shader stages
    {"STAGE_VERTEX", 0x01}, {"STAGE_FRAGMENT", 0x02}, {"STAGE_COMPUTE", 0x04},
    {"STAGE_GEOMETRY", 0x08}, {"STAGE_ALL", 0x3F},
    // Topology
    {"TOPO_POINT_LIST", 0}, {"TOPO_LINE_LIST", 1}, {"TOPO_LINE_STRIP", 2},
    {"TOPO_TRIANGLE_LIST", 3}, {"TOPO_TRIANGLE_STRIP", 4}, {"TOPO_TRIANGLE_FAN", 5},
    // Polygon mode
    {"POLY_FILL", 0}, {"POLY_LINE", 1}, {"POLY_POINT", 2},
    // Cull mode
    {"CULL_NONE", 0}, {"CULL_FRONT", 1}, {"CULL_BACK", 2},
    // Front face
    {"FRONT_CCW", 0}, {"FRONT_CW", 1},
    // Blend
    {"BLEND_ZERO", 0}, {"BLEND_ONE", 1}, {"BLEND_SRC_ALPHA", 2},
    {"BLEND_ONE_MINUS_SRC_ALPHA", 3},
    {"BLEND_OP_ADD", 0}, {"BLEND_OP_SUBTRACT", 1}, {"BLEND_OP_MIN", 2}, {"BLEND_OP_MAX", 3},
    // Compare
    {"COMPARE_NEVER", 0}, {"COMPARE_LESS", 1}, {"COMPARE_LEQUAL", 3},
    {"COMPARE_GREATER", 4}, {"COMPARE_ALWAYS", 7},
    // Load/Store
    {"LOAD_CLEAR", 0}, {"LOAD_LOAD", 1}, {"LOAD_DONTCARE", 2},
    {"STORE_STORE", 0}, {"STORE_DONTCARE", 1},
    // Layout
    {"LAYOUT_UNDEFINED", 0}, {"LAYOUT_GENERAL", 1}, {"LAYOUT_COLOR_ATTACH", 2},
    {"LAYOUT_DEPTH_ATTACH", 3}, {"LAYOUT_SHADER_READ", 4},
    {"LAYOUT_TRANSFER_SRC", 5}, {"LAYOUT_TRANSFER_DST", 6}, {"LAYOUT_PRESENT", 7},
    // Pipeline stages
    {"PIPE_TOP", 0x0001}, {"PIPE_VERTEX_INPUT", 0x0004}, {"PIPE_VERTEX_SHADER", 0x0008},
    {"PIPE_FRAGMENT", 0x0010}, {"PIPE_COLOR_OUTPUT", 0x0080},
    {"PIPE_COMPUTE", 0x0100}, {"PIPE_TRANSFER", 0x0200},
    {"PIPE_BOTTOM", 0x0400}, {"PIPE_ALL_COMMANDS", 0x2000},
    // Access
    {"ACCESS_NONE", 0}, {"ACCESS_SHADER_READ", 0x0001}, {"ACCESS_SHADER_WRITE", 0x0002},
    {"ACCESS_TRANSFER_READ", 0x0040}, {"ACCESS_TRANSFER_WRITE", 0x0080},
    {"ACCESS_HOST_READ", 0x0100}, {"ACCESS_HOST_WRITE", 0x0200},
    {"ACCESS_MEMORY_READ", 0x0400}, {"ACCESS_MEMORY_WRITE", 0x0800},
    // Vertex input
    {"INPUT_RATE_VERTEX", 0}, {"INPUT_RATE_INSTANCE", 1},
    {"ATTR_FLOAT", 0}, {"ATTR_VEC2", 1}, {"ATTR_VEC3", 2}, {"ATTR_VEC4", 3},
    {"ATTR_INT", 4}, {"ATTR_UINT", 8},
    // Key constants
    {"KEY_W", 87}, {"KEY_A", 65}, {"KEY_S", 83}, {"KEY_D", 68},
    {"KEY_Q", 81}, {"KEY_E", 69}, {"KEY_R", 82}, {"KEY_F", 70},
    {"KEY_SPACE", 32}, {"KEY_ESCAPE", 256}, {"KEY_ENTER", 257},
    {"KEY_TAB", 258}, {"KEY_BACKSPACE", 259},
    {"KEY_UP", 265}, {"KEY_DOWN", 264}, {"KEY_LEFT", 263}, {"KEY_RIGHT", 262},
    {"KEY_LEFT_SHIFT", 340}, {"KEY_LEFT_CONTROL", 341}, {"KEY_LEFT_ALT", 342},
    {"KEY_RIGHT_SHIFT", 344}, {"KEY_RIGHT_CONTROL", 345},
    {"KEY_F1", 290}, {"KEY_F2", 291}, {"KEY_F3", 292}, {"KEY_F4", 293},
    {"KEY_F5", 294}, {"KEY_F6", 295}, {"KEY_F7", 296},
    {"KEY_1", 49}, {"KEY_2", 50}, {"KEY_3", 51}, {"KEY_4", 52},
    {"KEY_MINUS", 45}, {"KEY_EQUAL", 61},
    // Cursor modes
    {"CURSOR_NORMAL", 0x00034001}, {"CURSOR_HIDDEN", 0x00034002},
    {"CURSOR_DISABLED", 0x00034003},
    // Sentinel
    {NULL, 0}
};

static int llvm_resolve_gpu_constant(const char* name, double* out_value) {
    for (int i = 0; g_gpu_constants[i].name != NULL; i++) {
        if (strcmp(g_gpu_constants[i].name, name) == 0) {
            *out_value = g_gpu_constants[i].value;
            return 1;
        }
    }
    return 0;
}

// Try to emit a GPU module method call. Returns the result register, or -1 if not a known GPU method.
static int llvm_try_emit_gpu_call(LLVMCompiler* lc, const char* method, int* arg_regs, int arg_count) {
    (void)arg_count;
    int r = llc_new_reg(lc);

    // Macro for emitting calls with variable args
    #define GPU_CALL_0(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "()", r); return r;
    #define GPU_CALL_1(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d)", r, arg_regs[0]); return r;
    #define GPU_CALL_2(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]); return r;
    #define GPU_CALL_3(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2]); return r;
    #define GPU_CALL_4(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3]); return r;
    #define GPU_CALL_5(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4]); return r;
    #define GPU_CALL_6(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4], arg_regs[5]); return r;

    // For calls with 7-8 args, emit inline
    #define GPU_CALL_7(fn) do { \
        fprintf(lc->out, "  %%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)\n", \
            r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4], arg_regs[5], arg_regs[6]); \
        return r; } while(0)
    #define GPU_CALL_8(fn) do { \
        fprintf(lc->out, "  %%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)\n", \
            r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4], arg_regs[5], arg_regs[6], arg_regs[7]); \
        return r; } while(0)

    // Core lifecycle
    if (strcmp(method, "has_vulkan") == 0) { GPU_CALL_0("has_vulkan"); }
    if (strcmp(method, "has_opengl") == 0) { GPU_CALL_0("has_opengl"); }
    if (strcmp(method, "initialize") == 0 || strcmp(method, "init") == 0) { GPU_CALL_2("init"); }
    if (strcmp(method, "init_opengl") == 0) { GPU_CALL_3("init_opengl"); }
    if (strcmp(method, "shutdown") == 0) { GPU_CALL_0("shutdown"); }
    if (strcmp(method, "device_name") == 0) { GPU_CALL_0("device_name"); }
    if (strcmp(method, "last_error") == 0) { GPU_CALL_0("last_error"); }
    // Buffers
    if (strcmp(method, "create_buffer") == 0) { GPU_CALL_3("create_buffer"); }
    if (strcmp(method, "destroy_buffer") == 0) { GPU_CALL_1("destroy_buffer"); }
    if (strcmp(method, "buffer_upload") == 0) { GPU_CALL_2("buffer_upload"); }
    if (strcmp(method, "buffer_download") == 0) { GPU_CALL_1("buffer_download"); }
    if (strcmp(method, "buffer_size") == 0) { GPU_CALL_1("buffer_size"); }
    // Images
    if (strcmp(method, "create_image") == 0) { GPU_CALL_5("create_image"); }
    if (strcmp(method, "create_image_3d") == 0) { GPU_CALL_5("create_image_3d"); }
    if (strcmp(method, "destroy_image") == 0) { GPU_CALL_1("destroy_image"); }
    if (strcmp(method, "image_dims") == 0) { GPU_CALL_1("image_dims"); }
    // Samplers
    if (strcmp(method, "create_sampler") == 0) { GPU_CALL_3("create_sampler"); }
    if (strcmp(method, "create_sampler_advanced") == 0) { GPU_CALL_6("create_sampler_advanced"); }
    if (strcmp(method, "destroy_sampler") == 0) { GPU_CALL_1("destroy_sampler"); }
    // Shaders
    if (strcmp(method, "load_shader") == 0) { GPU_CALL_2("load_shader"); }
    if (strcmp(method, "load_shader_glsl") == 0) { GPU_CALL_2("load_shader_glsl"); }
    if (strcmp(method, "reload_shader") == 0) { GPU_CALL_2("reload_shader"); }
    if (strcmp(method, "destroy_shader") == 0) { GPU_CALL_1("destroy_shader"); }
    // Descriptors
    if (strcmp(method, "create_descriptor_layout") == 0) { GPU_CALL_1("create_descriptor_layout"); }
    if (strcmp(method, "create_descriptor_pool") == 0) { GPU_CALL_2("create_descriptor_pool"); }
    if (strcmp(method, "allocate_descriptor_set") == 0) { GPU_CALL_2("allocate_descriptor_set"); }
    if (strcmp(method, "allocate_descriptor_sets") == 0) { GPU_CALL_3("allocate_descriptor_sets"); }
    if (strcmp(method, "update_descriptor") == 0) { GPU_CALL_4("update_descriptor"); }
    if (strcmp(method, "update_descriptor_image") == 0) { GPU_CALL_5("update_descriptor_image"); }
    if (strcmp(method, "update_descriptor_range") == 0) { GPU_CALL_4("update_descriptor_range"); }
    // Pipelines
    if (strcmp(method, "create_pipeline_layout") == 0) { GPU_CALL_3("create_pipeline_layout"); }
    if (strcmp(method, "create_compute_pipeline") == 0) { GPU_CALL_2("create_compute_pipeline"); }
    if (strcmp(method, "create_graphics_pipeline") == 0) { GPU_CALL_1("create_graphics_pipeline"); }
    if (strcmp(method, "destroy_pipeline") == 0) { GPU_CALL_1("destroy_pipeline"); }
    if (strcmp(method, "create_pipeline_cache") == 0) { GPU_CALL_0("create_pipeline_cache"); }
    // Render pass / Framebuffer
    if (strcmp(method, "create_render_pass") == 0) { GPU_CALL_2("create_render_pass"); }
    if (strcmp(method, "create_render_pass_mrt") == 0) { GPU_CALL_2("create_render_pass_mrt"); }
    if (strcmp(method, "destroy_render_pass") == 0) { GPU_CALL_1("destroy_render_pass"); }
    if (strcmp(method, "create_framebuffer") == 0) { GPU_CALL_4("create_framebuffer"); }
    if (strcmp(method, "destroy_framebuffer") == 0) { GPU_CALL_1("destroy_framebuffer"); }
    if (strcmp(method, "create_depth_buffer") == 0) { GPU_CALL_3("create_depth_buffer"); }
    // Commands
    if (strcmp(method, "create_command_pool") == 0) { GPU_CALL_1("create_command_pool"); }
    if (strcmp(method, "create_command_buffer") == 0) { GPU_CALL_1("create_command_buffer"); }
    if (strcmp(method, "create_secondary_command_buffer") == 0) { GPU_CALL_1("create_secondary_command_buffer"); }
    if (strcmp(method, "begin_commands") == 0) { GPU_CALL_1("begin_commands"); }
    if (strcmp(method, "begin_secondary") == 0) { GPU_CALL_4("begin_secondary"); }
    if (strcmp(method, "end_commands") == 0) { GPU_CALL_1("end_commands"); }
    // Command recording
    if (strcmp(method, "cmd_bind_compute_pipeline") == 0) { GPU_CALL_2("cmd_bind_compute_pipeline"); }
    if (strcmp(method, "cmd_bind_graphics_pipeline") == 0) { GPU_CALL_2("cmd_bind_graphics_pipeline"); }
    if (strcmp(method, "cmd_bind_descriptor_set") == 0) { GPU_CALL_4("cmd_bind_descriptor_set"); }
    if (strcmp(method, "cmd_dispatch") == 0) { GPU_CALL_4("cmd_dispatch"); }
    if (strcmp(method, "cmd_dispatch_indirect") == 0) { GPU_CALL_3("cmd_dispatch_indirect"); }
    if (strcmp(method, "cmd_push_constants") == 0) { GPU_CALL_4("cmd_push_constants"); }
    if (strcmp(method, "cmd_begin_render_pass") == 0) { GPU_CALL_6("cmd_begin_render_pass"); }
    if (strcmp(method, "cmd_end_render_pass") == 0) { GPU_CALL_1("cmd_end_render_pass"); }
    if (strcmp(method, "cmd_draw") == 0) { GPU_CALL_5("cmd_draw"); }
    if (strcmp(method, "cmd_draw_indexed") == 0) { GPU_CALL_6("cmd_draw_indexed"); }
    if (strcmp(method, "cmd_draw_indirect") == 0) { GPU_CALL_5("cmd_draw_indirect"); }
    if (strcmp(method, "cmd_draw_indexed_indirect") == 0) { GPU_CALL_5("cmd_draw_indexed_indirect"); }
    if (strcmp(method, "cmd_bind_vertex_buffer") == 0) { GPU_CALL_2("cmd_bind_vertex_buffer"); }
    if (strcmp(method, "cmd_bind_vertex_buffers") == 0) { GPU_CALL_2("cmd_bind_vertex_buffers"); }
    if (strcmp(method, "cmd_bind_index_buffer") == 0) { GPU_CALL_2("cmd_bind_index_buffer"); }
    if (strcmp(method, "cmd_set_viewport") == 0) { GPU_CALL_7("cmd_set_viewport"); }
    if (strcmp(method, "cmd_set_scissor") == 0) { GPU_CALL_5("cmd_set_scissor"); }
    if (strcmp(method, "cmd_pipeline_barrier") == 0) { GPU_CALL_5("cmd_pipeline_barrier"); }
    if (strcmp(method, "cmd_image_barrier") == 0) { GPU_CALL_8("cmd_image_barrier"); }
    if (strcmp(method, "cmd_copy_buffer") == 0) { GPU_CALL_4("cmd_copy_buffer"); }
    if (strcmp(method, "cmd_copy_buffer_to_image") == 0) { GPU_CALL_5("cmd_copy_buffer_to_image"); }
    if (strcmp(method, "cmd_execute_commands") == 0) { GPU_CALL_2("cmd_execute_commands"); }
    if (strcmp(method, "cmd_queue_transfer_barrier") == 0) { GPU_CALL_4("cmd_queue_transfer_barrier"); }
    // Sync
    if (strcmp(method, "create_fence") == 0) { GPU_CALL_1("create_fence"); }
    if (strcmp(method, "wait_fence") == 0) { GPU_CALL_2("wait_fence"); }
    if (strcmp(method, "reset_fence") == 0) { GPU_CALL_1("reset_fence"); }
    if (strcmp(method, "destroy_fence") == 0) { GPU_CALL_1("destroy_fence"); }
    if (strcmp(method, "create_semaphore") == 0) { GPU_CALL_0("create_semaphore"); }
    if (strcmp(method, "destroy_semaphore") == 0) { GPU_CALL_1("destroy_semaphore"); }
    if (strcmp(method, "submit") == 0) { GPU_CALL_2("submit"); }
    if (strcmp(method, "submit_compute") == 0) { GPU_CALL_2("submit_compute"); }
    if (strcmp(method, "submit_with_sync") == 0) { GPU_CALL_4("submit_with_sync"); }
    if (strcmp(method, "queue_wait_idle") == 0) { GPU_CALL_0("queue_wait_idle"); }
    if (strcmp(method, "device_wait_idle") == 0) { GPU_CALL_0("device_wait_idle"); }
    // Window / Swapchain
    if (strcmp(method, "create_window") == 0) { GPU_CALL_3("create_window"); }
    if (strcmp(method, "destroy_window") == 0) { GPU_CALL_0("destroy_window"); }
    if (strcmp(method, "window_should_close") == 0) { GPU_CALL_0("window_should_close"); }
    if (strcmp(method, "poll_events") == 0) { GPU_CALL_0("poll_events"); }
    if (strcmp(method, "init_windowed") == 0) { GPU_CALL_4("init_windowed"); }
    if (strcmp(method, "init_opengl_windowed") == 0) { GPU_CALL_5("init_opengl_windowed"); }
    if (strcmp(method, "shutdown_windowed") == 0) { GPU_CALL_0("shutdown_windowed"); }
    if (strcmp(method, "swapchain_image_count") == 0) { GPU_CALL_0("swapchain_image_count"); }
    if (strcmp(method, "swapchain_format") == 0) { GPU_CALL_0("swapchain_format"); }
    if (strcmp(method, "swapchain_extent") == 0) { GPU_CALL_0("swapchain_extent"); }
    if (strcmp(method, "acquire_next_image") == 0) { GPU_CALL_1("acquire_next_image"); }
    if (strcmp(method, "present") == 0) { GPU_CALL_2("present"); }
    if (strcmp(method, "create_swapchain_framebuffers") == 0) { GPU_CALL_1("create_swapchain_framebuffers"); }
    if (strcmp(method, "create_swapchain_framebuffers_depth") == 0) { GPU_CALL_2("create_swapchain_framebuffers_depth"); }
    if (strcmp(method, "recreate_swapchain") == 0) { GPU_CALL_0("recreate_swapchain"); }
    // Input
    if (strcmp(method, "key_pressed") == 0) { GPU_CALL_1("key_pressed"); }
    if (strcmp(method, "key_down") == 0) { GPU_CALL_1("key_down"); }
    if (strcmp(method, "key_just_pressed") == 0) { GPU_CALL_1("key_just_pressed"); }
    if (strcmp(method, "key_just_released") == 0) { GPU_CALL_1("key_just_released"); }
    if (strcmp(method, "mouse_pos") == 0) { GPU_CALL_0("mouse_pos"); }
    if (strcmp(method, "mouse_button") == 0) { GPU_CALL_1("mouse_button"); }
    if (strcmp(method, "mouse_just_pressed") == 0) { GPU_CALL_1("mouse_just_pressed"); }
    if (strcmp(method, "mouse_just_released") == 0) { GPU_CALL_1("mouse_just_released"); }
    if (strcmp(method, "mouse_delta") == 0) { GPU_CALL_0("mouse_delta"); }
    if (strcmp(method, "scroll_delta") == 0) { GPU_CALL_0("scroll_delta"); }
    if (strcmp(method, "set_cursor_mode") == 0) { GPU_CALL_1("set_cursor_mode"); }
    if (strcmp(method, "get_time") == 0) { GPU_CALL_0("get_time"); }
    if (strcmp(method, "window_size") == 0) { GPU_CALL_0("window_size"); }
    if (strcmp(method, "set_title") == 0) { GPU_CALL_1("set_title"); }
    if (strcmp(method, "window_resized") == 0) { GPU_CALL_0("window_resized"); }
    if (strcmp(method, "update_input") == 0) { GPU_CALL_0("update_input"); }
    if (strcmp(method, "text_input_available") == 0) { GPU_CALL_0("text_input_available"); }
    if (strcmp(method, "text_input_read") == 0) { GPU_CALL_0("text_input_read"); }
    // Textures / Upload
    if (strcmp(method, "load_texture") == 0) { GPU_CALL_4("load_texture"); }
    if (strcmp(method, "texture_dims") == 0) { GPU_CALL_1("texture_dims"); }
    if (strcmp(method, "generate_mipmaps") == 0) { GPU_CALL_1("generate_mipmaps"); }
    if (strcmp(method, "create_cubemap") == 0) { GPU_CALL_1("create_cubemap"); }
    if (strcmp(method, "upload_device_local") == 0) { GPU_CALL_2("upload_device_local"); }
    if (strcmp(method, "upload_bytes") == 0) { GPU_CALL_2("upload_bytes"); }
    // Uniform buffers
    if (strcmp(method, "create_uniform_buffer") == 0) { GPU_CALL_1("create_uniform_buffer"); }
    if (strcmp(method, "update_uniform") == 0) { GPU_CALL_2("update_uniform"); }
    // Offscreen / Screenshot
    if (strcmp(method, "create_offscreen_target") == 0) { GPU_CALL_4("create_offscreen_target"); }
    if (strcmp(method, "screenshot") == 0) { GPU_CALL_1("screenshot"); }
    if (strcmp(method, "save_screenshot") == 0) { GPU_CALL_1("save_screenshot"); }
    // Font
    if (strcmp(method, "load_font") == 0) { GPU_CALL_2("load_font"); }
    if (strcmp(method, "font_atlas") == 0) { GPU_CALL_1("font_atlas"); }
    if (strcmp(method, "font_set_atlas") == 0) { GPU_CALL_3("font_set_atlas"); }
    if (strcmp(method, "font_text_verts") == 0) { GPU_CALL_5("font_text_verts"); }
    if (strcmp(method, "font_measure") == 0) { GPU_CALL_3("font_measure"); }
    // glTF
    if (strcmp(method, "load_gltf") == 0) { GPU_CALL_1("load_gltf"); }
    // Queue families
    if (strcmp(method, "graphics_family") == 0) { GPU_CALL_0("graphics_family"); }
    if (strcmp(method, "compute_family") == 0) { GPU_CALL_0("compute_family"); }
    // Platform
    if (strcmp(method, "set_platform") == 0) { GPU_CALL_1("set_platform"); }
    if (strcmp(method, "get_platform") == 0) { GPU_CALL_0("get_platform"); }
    if (strcmp(method, "detected_platform") == 0) { GPU_CALL_0("detected_platform"); }
    // Device limits (takes 0 args, returns dict)
    if (strcmp(method, "device_limits") == 0) { GPU_CALL_0("device_limits"); }

    #undef GPU_CALL_0
    #undef GPU_CALL_1
    #undef GPU_CALL_2
    #undef GPU_CALL_3
    #undef GPU_CALL_4
    #undef GPU_CALL_5
    #undef GPU_CALL_6
    #undef GPU_CALL_7
    #undef GPU_CALL_8

    return -1;  // Not a known GPU method
}

// ============================================================================
// Collect top-level symbols
// ============================================================================

// Build a "ClassName_methodName" string for class methods
static char* class_method_name(const char* class_name, Token method_token) {
    char* method = token_to_str(method_token);
    size_t clen = strlen(class_name);
    size_t mlen = strlen(method);
    char* result = SAGE_ALLOC(clen + 1 + mlen + 1);
    memcpy(result, class_name, clen);
    result[clen] = '_';
    memcpy(result + clen + 1, method, mlen + 1);
    free(method);
    return result;
}

static void llvm_collect_expr_names(LLVMNameSet* names, Expr* expr) {
    if (expr == NULL) return;
    switch (expr->type) {
        case EXPR_VARIABLE: {
            char* name = token_to_str(expr->as.variable.name);
            llvm_name_set_add(names, name);
            free(name);
            break;
        }
        case EXPR_BINARY:
            llvm_collect_expr_names(names, expr->as.binary.left);
            llvm_collect_expr_names(names, expr->as.binary.right);
            break;
        case EXPR_CALL:
            llvm_collect_expr_names(names, expr->as.call.callee);
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                llvm_collect_expr_names(names, expr->as.call.args[i]);
            }
            break;
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                llvm_collect_expr_names(names, expr->as.array.elements[i]);
            }
            break;
        case EXPR_INDEX:
            llvm_collect_expr_names(names, expr->as.index.array);
            llvm_collect_expr_names(names, expr->as.index.index);
            break;
        case EXPR_INDEX_SET:
            llvm_collect_expr_names(names, expr->as.index_set.array);
            llvm_collect_expr_names(names, expr->as.index_set.index);
            llvm_collect_expr_names(names, expr->as.index_set.value);
            break;
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                llvm_collect_expr_names(names, expr->as.dict.values[i]);
            }
            break;
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                llvm_collect_expr_names(names, expr->as.tuple.elements[i]);
            }
            break;
        case EXPR_SLICE:
            llvm_collect_expr_names(names, expr->as.slice.array);
            llvm_collect_expr_names(names, expr->as.slice.start);
            llvm_collect_expr_names(names, expr->as.slice.end);
            break;
        case EXPR_GET:
            llvm_collect_expr_names(names, expr->as.get.object);
            break;
        case EXPR_SET:
            if (expr->as.set.object == NULL) {
                char* name = token_to_str(expr->as.set.property);
                llvm_name_set_add(names, name);
                free(name);
            } else {
                llvm_collect_expr_names(names, expr->as.set.object);
            }
            llvm_collect_expr_names(names, expr->as.set.value);
            break;
        case EXPR_AWAIT:
            llvm_collect_expr_names(names, expr->as.await.expression);
            break;
        case EXPR_COMPTIME:
            llvm_collect_expr_names(names, expr->as.comptime.expression);
            break;
        default:
            break;
    }
}

static void llvm_collect_stmt_names(LLVMNameSet* names, Stmt* stmt) {
    for (Stmt* s = stmt; s != NULL; s = s->next) {
        switch (s->type) {
            case STMT_PROC:
            case STMT_ASYNC_PROC:
            case STMT_CLASS:
                break;
            case STMT_PRINT:
                llvm_collect_expr_names(names, s->as.print.expression);
                break;
            case STMT_EXPRESSION:
                llvm_collect_expr_names(names, s->as.expression);
                break;
            case STMT_LET:
                llvm_collect_expr_names(names, s->as.let.initializer);
                break;
            case STMT_IF:
                llvm_collect_expr_names(names, s->as.if_stmt.condition);
                llvm_collect_stmt_names(names, s->as.if_stmt.then_branch);
                llvm_collect_stmt_names(names, s->as.if_stmt.else_branch);
                break;
            case STMT_BLOCK:
                llvm_collect_stmt_names(names, s->as.block.statements);
                break;
            case STMT_WHILE:
                llvm_collect_expr_names(names, s->as.while_stmt.condition);
                llvm_collect_stmt_names(names, s->as.while_stmt.body);
                break;
            case STMT_FOR:
                llvm_collect_expr_names(names, s->as.for_stmt.iterable);
                llvm_collect_stmt_names(names, s->as.for_stmt.body);
                break;
            case STMT_RETURN:
                llvm_collect_expr_names(names, s->as.ret.value);
                break;
            case STMT_MATCH:
                llvm_collect_expr_names(names, s->as.match_stmt.value);
                for (int i = 0; i < s->as.match_stmt.case_count; i++) {
                    CaseClause* clause = s->as.match_stmt.cases[i];
                    if (clause == NULL) continue;
                    llvm_collect_expr_names(names, clause->pattern);
                    llvm_collect_expr_names(names, clause->guard);
                    llvm_collect_stmt_names(names, clause->body);
                }
                llvm_collect_stmt_names(names, s->as.match_stmt.default_case);
                break;
            case STMT_TRY:
                llvm_collect_stmt_names(names, s->as.try_stmt.try_block);
                for (int i = 0; i < s->as.try_stmt.catch_count; i++) {
                    llvm_collect_stmt_names(names, s->as.try_stmt.catches[i]->body);
                }
                llvm_collect_stmt_names(names, s->as.try_stmt.finally_block);
                break;
            case STMT_RAISE:
                llvm_collect_expr_names(names, s->as.raise.exception);
                break;
            case STMT_DEFER:
                llvm_collect_stmt_names(names, s->as.defer.statement);
                break;
            case STMT_COMPTIME:
                llvm_collect_stmt_names(names, s->as.comptime.body);
                break;
            default:
                break;
        }
    }
}

static void llvm_collect_bound_names(LLVMNameSet* names, Stmt* stmt) {
    for (Stmt* s = stmt; s != NULL; s = s->next) {
        switch (s->type) {
            case STMT_LET: {
                char* name = token_to_str(s->as.let.name);
                llvm_name_set_add(names, name);
                free(name);
                break;
            }
            case STMT_PROC:
            case STMT_ASYNC_PROC: {
                Token token = s->type == STMT_PROC ? s->as.proc.name : s->as.async_proc.name;
                char* name = token_to_str(token);
                llvm_name_set_add(names, name);
                free(name);
                break;
            }
            case STMT_FOR: {
                char* name = token_to_str(s->as.for_stmt.variable);
                llvm_name_set_add(names, name);
                free(name);
                llvm_collect_bound_names(names, s->as.for_stmt.body);
                break;
            }
            case STMT_IF:
                llvm_collect_bound_names(names, s->as.if_stmt.then_branch);
                llvm_collect_bound_names(names, s->as.if_stmt.else_branch);
                break;
            case STMT_BLOCK:
                llvm_collect_bound_names(names, s->as.block.statements);
                break;
            case STMT_WHILE:
                llvm_collect_bound_names(names, s->as.while_stmt.body);
                break;
            case STMT_TRY:
                llvm_collect_bound_names(names, s->as.try_stmt.try_block);
                for (int i = 0; i < s->as.try_stmt.catch_count; i++) {
                    char* name = token_to_str(s->as.try_stmt.catches[i]->exception_var);
                    llvm_name_set_add(names, name);
                    free(name);
                    llvm_collect_bound_names(names, s->as.try_stmt.catches[i]->body);
                }
                llvm_collect_bound_names(names, s->as.try_stmt.finally_block);
                break;
            case STMT_MATCH:
                for (int i = 0; i < s->as.match_stmt.case_count; i++) {
                    CaseClause* clause = s->as.match_stmt.cases[i];
                    if (clause == NULL) continue;
                    if (clause->pattern != NULL && clause->pattern->type == EXPR_VARIABLE &&
                        !(clause->pattern->as.variable.name.length == 1 &&
                          clause->pattern->as.variable.name.start[0] == '_')) {
                        char* name = token_to_str(clause->pattern->as.variable.name);
                        llvm_name_set_add(names, name);
                        free(name);
                    }
                    llvm_collect_bound_names(names, clause->body);
                }
                llvm_collect_bound_names(names, s->as.match_stmt.default_case);
                break;
            case STMT_DEFER:
                llvm_collect_bound_names(names, s->as.defer.statement);
                break;
            case STMT_COMPTIME:
                llvm_collect_bound_names(names, s->as.comptime.body);
                break;
            default:
                break;
        }
    }
}

static void llvm_add_proc_bounds(LLVMScopeInfo* scope, ProcStmt* proc) {
    if (scope == NULL || proc == NULL) return;
    for (int i = 0; i < proc->param_count; i++) {
        char* name = token_to_str(proc->params[i]);
        llvm_name_set_add(&scope->bound_names, name);
        free(name);
    }
    llvm_collect_bound_names(&scope->bound_names, proc->body);
    if (proc->defaults != NULL) {
        for (int i = 0; i < proc->param_count; i++) {
            llvm_collect_expr_names(&scope->free_names, proc->defaults[i]);
        }
    }
    llvm_collect_stmt_names(&scope->free_names, proc->body);
}

static void llvm_discover_nested_statements(LLVMCompiler* lc, LLVMScopeInfo* owner,
                                            Stmt* stmt) {
    for (Stmt* s = stmt; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = token_to_str(s->as.proc.name);
            size_t size = strlen(name) + 64;
            char* symbol = SAGE_ALLOC(size);
            snprintf(symbol, size, "sage_fn_nested_%d_%s", lc->next_nested_id++, name);
            LLVMScopeInfo* child = llc_add_scope(lc, s, owner, symbol, 1);
            free(symbol);
            free(name);
            llvm_add_proc_bounds(child, &s->as.proc);
            llvm_discover_nested_statements(lc, child, s->as.proc.body);
            continue;
        }
        if (s->type == STMT_ASYNC_PROC) continue;
        if (s->type == STMT_IF) {
            llvm_discover_nested_statements(lc, owner, s->as.if_stmt.then_branch);
            llvm_discover_nested_statements(lc, owner, s->as.if_stmt.else_branch);
        } else if (s->type == STMT_BLOCK) {
            llvm_discover_nested_statements(lc, owner, s->as.block.statements);
        } else if (s->type == STMT_WHILE) {
            llvm_discover_nested_statements(lc, owner, s->as.while_stmt.body);
        } else if (s->type == STMT_FOR) {
            llvm_discover_nested_statements(lc, owner, s->as.for_stmt.body);
        } else if (s->type == STMT_TRY) {
            llvm_discover_nested_statements(lc, owner, s->as.try_stmt.try_block);
            for (int i = 0; i < s->as.try_stmt.catch_count; i++) {
                llvm_discover_nested_statements(lc, owner, s->as.try_stmt.catches[i]->body);
            }
            llvm_discover_nested_statements(lc, owner, s->as.try_stmt.finally_block);
        } else if (s->type == STMT_MATCH) {
            for (int i = 0; i < s->as.match_stmt.case_count; i++) {
                CaseClause* clause = s->as.match_stmt.cases[i];
                if (clause != NULL) llvm_discover_nested_statements(lc, owner, clause->body);
            }
            llvm_discover_nested_statements(lc, owner, s->as.match_stmt.default_case);
        } else if (s->type == STMT_DEFER) {
            llvm_discover_nested_statements(lc, owner, s->as.defer.statement);
        } else if (s->type == STMT_COMPTIME) {
            llvm_discover_nested_statements(lc, owner, s->as.comptime.body);
        }
    }
}

static int llvm_scope_has_ancestor_name(LLVMScopeInfo* scope, const char* name) {
    for (LLVMScopeInfo* parent = scope->parent; parent != NULL; parent = parent->parent) {
        if (llvm_name_set_has(&parent->bound_names, name)) return 1;
    }
    return 0;
}

static void llvm_finalize_scope_captures(LLVMCompiler* lc) {
    for (int i = 0; i < lc->scope_count; i++) {
        LLVMScopeInfo* scope = lc->scopes[i];
        if (!scope->is_nested) continue;
        for (int j = 0; j < scope->free_names.count; j++) {
            const char* name = scope->free_names.items[j];
            if (!llvm_name_set_has(&scope->bound_names, name) &&
                llvm_scope_has_ancestor_name(scope, name)) {
                llc_add_scope_capture(scope, name);
            }
        }
    }

    int changed = 1;
    while (changed) {
        changed = 0;
        for (int i = 0; i < lc->scope_count; i++) {
            LLVMScopeInfo* scope = lc->scopes[i];
            if (!scope->is_nested || scope->parent == NULL) continue;
            for (int j = 0; j < scope->capture_count; j++) {
                const char* name = scope->captures[j];
                if (llvm_name_set_has(&scope->parent->bound_names, name)) continue;
                int parent_has_capture = 0;
                for (int k = 0; k < scope->parent->capture_count; k++) {
                    if (strcmp(scope->parent->captures[k], name) == 0) {
                        parent_has_capture = 1;
                        break;
                    }
                }
                if (!parent_has_capture) {
                    llc_add_scope_capture(scope->parent, name);
                    changed = 1;
                }
            }
        }
    }
}

static void llvm_collect_proc_signatures(LLVMCompiler* lc, Stmt* program) {
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = token_to_str(s->as.proc.name);
            llc_add_proc_signature(lc, name, &s->as.proc);
            free(name);
        } else if (s->type == STMT_ASYNC_PROC) {
            char* name = token_to_str(s->as.async_proc.name);
            llc_add_proc_signature(lc, name, &s->as.async_proc);
            free(name);
        } else if (s->type == STMT_CLASS) {
            char* cname = token_to_str(s->as.class_stmt.name);
            for (Stmt* m = s->as.class_stmt.methods; m != NULL; m = m->next) {
                if (m->type == STMT_PROC) {
                    char* mname = class_method_name(cname, m->as.proc.name);
                    llc_add_proc_signature(lc, mname, &m->as.proc);
                    free(mname);
                }
            }
            free(cname);
        }
    }
}

static void llvm_collect_metadata(LLVMCompiler* lc, Stmt* program) {
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type == STMT_CLASS) llc_add_class_info(lc, &s->as.class_stmt);
    }
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type != STMT_LET || s->as.let.initializer == NULL ||
            s->as.let.initializer->type != EXPR_CALL ||
            s->as.let.initializer->as.call.callee == NULL ||
            s->as.let.initializer->as.call.callee->type != EXPR_VARIABLE) {
            continue;
        }
        char* variable = token_to_str(s->as.let.name);
        char* class_name = token_to_str(s->as.let.initializer->as.call.callee->as.variable.name);
        if (llc_find_class_info(lc, class_name) != NULL) {
            llc_add_value_class(lc, variable, class_name);
        }
        free(variable);
        free(class_name);
    }
    lc->main_scope = llc_add_scope(lc, NULL, NULL, "main", 0);
    llvm_collect_bound_names(&lc->main_scope->bound_names, program);
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = token_to_str(s->as.proc.name);
            size_t size = strlen(name) + 16;
            char* symbol = SAGE_ALLOC(size);
            snprintf(symbol, size, "sage_fn_%s", name);
            LLVMScopeInfo* scope = llc_add_scope(lc, s, NULL, symbol, 0);
            free(symbol);
            free(name);
            llvm_add_proc_bounds(scope, &s->as.proc);
            llvm_discover_nested_statements(lc, scope, s->as.proc.body);
        } else if (s->type == STMT_CLASS) {
            char* cname = token_to_str(s->as.class_stmt.name);
            for (Stmt* m = s->as.class_stmt.methods; m != NULL; m = m->next) {
                if (m->type != STMT_PROC) continue;
                char* mname = class_method_name(cname, m->as.proc.name);
                size_t size = strlen(mname) + 16;
                char* symbol = SAGE_ALLOC(size);
                snprintf(symbol, size, "sage_fn_%s", mname);
                LLVMScopeInfo* scope = llc_add_scope(lc, m, NULL, symbol, 0);
                free(symbol);
                free(mname);
                llvm_add_proc_bounds(scope, &m->as.proc);
                llvm_discover_nested_statements(lc, scope, m->as.proc.body);
            }
            free(cname);
        } else {
            Stmt* saved_next = s->next;
            s->next = NULL;
            llvm_discover_nested_statements(lc, lc->main_scope, s);
            s->next = saved_next;
        }
    }
    llvm_finalize_scope_captures(lc);
    llvm_collect_proc_signatures(lc, program);
}

static LLVMScopeInfo* llc_find_module_proc_scope(LLVMCompiler* lc,
                                                 const char* module_name,
                                                 const char* member_name) {
    if (module_name == NULL || member_name == NULL) return NULL;
    size_t length = strlen(member_name);
    for (int i = 0; i < lc->scope_count; i++) {
        LLVMScopeInfo* scope = lc->scopes[i];
        if (scope->is_nested || scope->proc == NULL || scope->module_name == NULL ||
            strcmp(scope->module_name, module_name) != 0) {
            continue;
        }
        Token token = scope->proc->name;
        if ((size_t)token.length == length &&
            strncmp(token.start, member_name, length) == 0) {
            return scope;
        }
    }
    return NULL;
}

static LLVMImportedModule* llvm_load_source_module(LLVMCompiler* lc,
                                                    const char* module_name) {
    LLVMImportedModule* existing = llc_find_source_module(lc, module_name);
    if (existing != NULL) return existing;

    char* module_path = resolve_module_path_for_llvm(lc, module_name);
    if (module_path == NULL) {
        fprintf(stderr, "LLVM backend: cannot resolve source module '%s'\n", module_name);
        lc->failed = 1;
        return NULL;
    }
    char* source = llvm_read_file_contents(module_path);
    if (source == NULL) {
        fprintf(stderr, "LLVM backend: cannot read source module '%s'\n", module_path);
        free(module_path);
        lc->failed = 1;
        return NULL;
    }

    if (lc->source_module_count >= lc->source_module_cap) {
        lc->source_module_cap = lc->source_module_cap ? lc->source_module_cap * 2 : 8;
        lc->source_modules = SAGE_REALLOC(
            lc->source_modules,
            sizeof(LLVMImportedModule) * (size_t)lc->source_module_cap);
    }
    LLVMImportedModule* module = &lc->source_modules[lc->source_module_count++];
    memset(module, 0, sizeof(*module));
    module->name = SAGE_STRDUP(module_name);
    module->path = module_path;
    module->source = source;
    module->ast = llvm_parse_program_with_path(source, module_path);
    int module_index = (int)(module - lc->source_modules);

    for (Stmt* stmt = module->ast; stmt != NULL; stmt = stmt->next) {
        if (stmt->type == STMT_LET) {
            char* member_name = token_to_str(stmt->as.let.name);
            llc_add_imported_global(lc, module_name, member_name);
            free(member_name);
            continue;
        }
        if (stmt->type == STMT_PROC) {
            char* member_name = token_to_str(stmt->as.proc.name);
            char member_symbol[256];
            llvm_append_symbol_part(member_symbol, sizeof(member_symbol), member_name);
            size_t symbol_size = strlen(member_symbol) + 48;
            char* symbol = SAGE_ALLOC(symbol_size);
            snprintf(symbol, symbol_size, "sage_modfn_%d_%s", module_index, member_symbol);
            size_t signature_size = strlen(member_symbol) + 48;
            char* signature_name = SAGE_ALLOC(signature_size);
            snprintf(signature_name, signature_size, "sage_modsig_%d_%s", module_index, member_symbol);

            LLVMScopeInfo* scope = llc_add_scope(lc, stmt, NULL, symbol, 0);
            scope->module_name = SAGE_STRDUP(module_name);
            scope->signature_name = signature_name;
            llvm_add_proc_bounds(scope, &stmt->as.proc);
            llvm_discover_nested_statements(lc, scope, stmt->as.proc.body);
            llc_add_proc_signature(lc, signature_name, &stmt->as.proc);
            llc_add_proc(lc, member_name);
            free(symbol);
            free(member_name);
            continue;
        }
        fprintf(stderr,
                "LLVM backend: unsupported top-level statement type %d in source module '%s'\n",
                stmt->type, module_name);
        lc->failed = 1;
    }
    return module;
}

static void llvm_register_source_import(LLVMCompiler* lc, ImportStmt* import_stmt) {
    if (import_stmt == NULL || import_stmt->module_name == NULL) return;
    const char* module_name = import_stmt->module_name;
    const char* binding = NULL;
    if (import_stmt->alias != NULL) {
        binding = import_stmt->alias;
    } else if (import_stmt->item_count == 0) {
        const char* dot = strrchr(module_name, '.');
        binding = dot != NULL ? dot + 1 : module_name;
    }
    if (binding != NULL) llc_add_module_binding(lc, module_name, binding);

    if (is_native_module(module_name)) return;
    LLVMImportedModule* module = llvm_load_source_module(lc, module_name);
    if (module == NULL) return;

    if (import_stmt->item_count == 0) return;

    for (int i = 0; i < import_stmt->item_count; i++) {
        const char* member_name = import_stmt->items[i];
        const char* item_binding = member_name;
        if (import_stmt->item_aliases != NULL && import_stmt->item_aliases[i] != NULL) {
            item_binding = import_stmt->item_aliases[i];
        }
        LLVMScopeInfo* proc_scope = llc_find_module_proc_scope(
            lc, module_name, member_name);
        LLVMImportedGlobal* global = llc_find_imported_global(
            lc, module_name, member_name);
        if (proc_scope == NULL && global == NULL) {
            fprintf(stderr, "LLVM backend: source module '%s' has no member '%s'\n",
                    module_name, member_name);
            lc->failed = 1;
            continue;
        }
        llc_add_imported_value(lc, item_binding, module_name, member_name,
                               proc_scope, global != NULL ? global->global_name : NULL);
    }
}

static void llvm_collect_imported_modules(LLVMCompiler* lc, Stmt* program) {
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type == STMT_IMPORT) llvm_register_source_import(lc, &stmt->as.import);
    }
    llvm_finalize_scope_captures(lc);
}

static void llvm_collect_symbols(LLVMCompiler* lc, Stmt* program) {
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = token_to_str(s->as.proc.name);
            llc_add_proc(lc, name);
            free(name);
        } else if (s->type == STMT_ASYNC_PROC) {
            char* name = token_to_str(s->as.async_proc.name);
            llc_add_proc(lc, name);
            free(name);
        } else if (s->type == STMT_LET) {
            char* name = token_to_str(s->as.let.name);
            llc_add_global(lc, name);
            free(name);
        } else if (s->type == STMT_STRUCT) {
            char* name = token_to_str(s->as.struct_stmt.name);
            llc_add_global_once(lc, name);
            llc_add_struct_info(lc, name, &s->as.struct_stmt);
            free(name);
        } else if (s->type == STMT_ENUM) {
            char* name = token_to_str(s->as.enum_stmt.name);
            llc_add_global_once(lc, name);
            llc_add_enum_info(lc, name, &s->as.enum_stmt);
            free(name);
        } else if (s->type == STMT_IMPORT) {
            if (s->as.import.module_name != NULL) {
                const char* bind = s->as.import.alias;
                if (bind == NULL && s->as.import.item_count == 0) {
                    const char* dot = strrchr(s->as.import.module_name, '.');
                    bind = dot != NULL ? dot + 1 : s->as.import.module_name;
                }
                if (bind != NULL) {
                    llc_add_module_binding(lc, s->as.import.module_name, bind);
                    llc_add_global(lc, bind);
                }
            }
            for (int i = 0; i < s->as.import.item_count; i++) {
                const char* item_name = (s->as.import.item_aliases && s->as.import.item_aliases[i])
                    ? s->as.import.item_aliases[i] : s->as.import.items[i];
                llc_add_global(lc, item_name);
            }
            if (s->as.import.item_count > 0) {
                llvm_process_import_constants(lc, &s->as.import);
            }
        } else if (s->type == STMT_CLASS) {
            char* cname = token_to_str(s->as.class_stmt.name);
            for (Stmt* m = s->as.class_stmt.methods; m != NULL; m = m->next) {
                if (m->type == STMT_PROC) {
                    char* mname = class_method_name(cname, m->as.proc.name);
                    llc_add_proc(lc, mname);
                    free(mname);
                } else if (m->type == STMT_ASYNC_PROC) {
                    char* mname = class_method_name(cname, m->as.async_proc.name);
                    llc_add_proc(lc, mname);
                    free(mname);
                }
            }
            free(cname);
        }
    }
}

static int llvm_emit_expr(LLVMCompiler* lc, Expr* expr);
static void llvm_emit_call_adapter(LLVMCompiler* lc, LLVMScopeInfo* scope);

static int llvm_emit_string_ptr(LLVMCompiler* lc, const char* value) {
    int str_id = llc_add_string(lc, value != NULL ? value : "");
    size_t slen = strlen(value != NULL ? value : "") + 1;
    int ptr_reg = llc_new_reg(lc);
    ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
            ptr_reg, slen, slen, str_id);
    return ptr_reg;
}

static int llvm_emit_string_value(LLVMCompiler* lc, const char* value) {
    int ptr_reg = llvm_emit_string_ptr(lc, value);
    int r = llc_new_reg(lc);
    ll_line(lc, "%%%d = call %%SageValue @sage_rt_string(i8* %%%d)", r, ptr_reg);
    return r;
}

static void llvm_emit_dict_set_string(LLVMCompiler* lc, int dict_reg, const char* key, int value_reg) {
    int ptr_reg = llvm_emit_string_ptr(lc, key);
    ll_line(lc, "call void @sage_rt_dict_set(%%SageValue %%%d, i8* %%%d, %%SageValue %%%d)",
            dict_reg, ptr_reg, value_reg);
}

static unsigned long long llvm_call_mask(int count) {
    if (count <= 0) return 0;
    if (count >= 64) return ~0ULL;
    return (1ULL << count) - 1ULL;
}

static void llvm_emit_callable_arguments(LLVMCompiler* lc, Expr* call,
                                         const char* name, int param_offset,
                                         int** out_regs, int* out_count,
                                         unsigned long long* out_mask) {
    *out_regs = NULL;
    *out_count = 0;
    *out_mask = 0;
    if (call == NULL) return;

    int argument_count = call->as.call.arg_count;
    if (argument_count < 0) argument_count = 0;
    LLVMProcSignature* sig = name != NULL ? llc_find_proc_signature(lc, name) : NULL;
    if (sig == NULL) {
        *out_count = argument_count;
        if (argument_count > 0) {
            *out_regs = SAGE_ALLOC(sizeof(int) * (size_t)argument_count);
            for (int i = 0; i < argument_count; i++) {
                (*out_regs)[i] = llvm_emit_expr(lc, call->as.call.args[i]);
            }
        }
        *out_mask = llvm_call_mask(argument_count);
        return;
    }

    if (param_offset < 0) param_offset = 0;
    if (param_offset > sig->param_count) param_offset = sig->param_count;
    int count = sig->param_count - param_offset;
    int has_keyword = 0;
    if (call->as.call.kw_names != NULL) {
        for (int i = 0; i < argument_count; i++) {
            if (call->as.call.kw_names[i] != NULL) {
                has_keyword = 1;
                break;
            }
        }
    }

    if (!has_keyword) {
        if (argument_count > count) lc->failed = 1;
        int actual_count = argument_count;
        if (actual_count > count) actual_count = count;
        if (actual_count > 0) {
            *out_regs = SAGE_ALLOC(sizeof(int) * (size_t)actual_count);
            for (int i = 0; i < actual_count; i++) {
                (*out_regs)[i] = llvm_emit_expr(lc, call->as.call.args[i]);
            }
        }
        *out_count = actual_count;
        *out_mask = llvm_call_mask(actual_count);
        for (int i = 0; i < sig->required_count - param_offset; i++) {
            if (i >= actual_count) lc->failed = 1;
        }
        return;
    }

    int* regs = count > 0 ? SAGE_ALLOC(sizeof(int) * (size_t)count) : NULL;
    unsigned char* provided = count > 0 ? SAGE_ALLOC((size_t)count) : NULL;
    for (int i = 0; i < count; i++) {
        regs[i] = -1;
        provided[i] = 0;
    }

    int positional = 0;
    for (int i = 0; i < argument_count; i++) {
        int target = -1;
        const char* keyword = call->as.call.kw_names != NULL
            ? call->as.call.kw_names[i] : NULL;
        if (keyword != NULL) {
            for (int j = param_offset; j < sig->param_count; j++) {
                if (sig->param_names[j] != NULL &&
                    strcmp(keyword, sig->param_names[j]) == 0) {
                    target = j - param_offset;
                    break;
                }
            }
            if (target < 0) lc->failed = 1;
        } else {
            while (positional < count && provided[positional]) positional++;
            if (positional < count) target = positional++;
        }

        int value = llvm_emit_expr(lc, call->as.call.args[i]);
        if (target >= 0 && target < count && !provided[target]) {
            regs[target] = value;
            provided[target] = 1;
        } else {
            lc->failed = 1;
        }
    }

    unsigned long long mask = 0;
    for (int i = 0; i < count; i++) {
        if (provided[i]) {
            mask |= 1ULL << i;
        } else {
            regs[i] = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", regs[i]);
        }
    }
    for (int i = 0; i < sig->required_count - param_offset; i++) {
        if (i >= 0 && i < count && !provided[i]) lc->failed = 1;
    }

    *out_regs = regs;
    *out_count = count;
    *out_mask = mask;
    free(provided);
}

static void llvm_remap_callable_arguments(LLVMCompiler* lc, Expr* call,
                                          const char* name, int param_offset,
                                          const int* raw_regs, int raw_count,
                                          int** out_regs, int* out_count,
                                          unsigned long long* out_mask) {
    *out_regs = NULL;
    *out_count = 0;
    *out_mask = 0;
    if (raw_count < 0) raw_count = 0;
    LLVMProcSignature* sig = name != NULL ? llc_find_proc_signature(lc, name) : NULL;
    if (sig == NULL) {
        *out_count = raw_count;
        if (raw_count > 0) {
            *out_regs = SAGE_ALLOC(sizeof(int) * (size_t)raw_count);
            memcpy(*out_regs, raw_regs, sizeof(int) * (size_t)raw_count);
        }
        *out_mask = llvm_call_mask(raw_count);
        return;
    }

    if (param_offset < 0) param_offset = 0;
    if (param_offset > sig->param_count) param_offset = sig->param_count;
    int count = sig->param_count - param_offset;
    int has_keyword = 0;
    if (call != NULL && call->as.call.kw_names != NULL) {
        for (int i = 0; i < raw_count; i++) {
            if (call->as.call.kw_names[i] != NULL) {
                has_keyword = 1;
                break;
            }
        }
    }

    if (!has_keyword) {
        int actual_count = raw_count;
        if (actual_count > count) {
            lc->failed = 1;
            actual_count = count;
        }
        if (actual_count > 0) {
            *out_regs = SAGE_ALLOC(sizeof(int) * (size_t)actual_count);
            memcpy(*out_regs, raw_regs, sizeof(int) * (size_t)actual_count);
        }
        *out_count = actual_count;
        *out_mask = llvm_call_mask(actual_count);
        for (int i = 0; i < sig->required_count - param_offset; i++) {
            if (i >= actual_count) lc->failed = 1;
        }
        return;
    }

    int* regs = count > 0 ? SAGE_ALLOC(sizeof(int) * (size_t)count) : NULL;
    unsigned char* provided = count > 0 ? SAGE_ALLOC((size_t)count) : NULL;
    for (int i = 0; i < count; i++) {
        regs[i] = -1;
        provided[i] = 0;
    }
    int positional = 0;
    for (int i = 0; i < raw_count; i++) {
        int target = -1;
        const char* keyword = call->as.call.kw_names != NULL
            ? call->as.call.kw_names[i] : NULL;
        if (keyword != NULL) {
            for (int j = param_offset; j < sig->param_count; j++) {
                if (sig->param_names[j] != NULL &&
                    strcmp(keyword, sig->param_names[j]) == 0) {
                    target = j - param_offset;
                    break;
                }
            }
            if (target < 0) lc->failed = 1;
        } else {
            while (positional < count && provided[positional]) positional++;
            if (positional < count) target = positional++;
        }
        if (target >= 0 && target < count && !provided[target]) {
            regs[target] = raw_regs[i];
            provided[target] = 1;
        } else {
            lc->failed = 1;
        }
    }
    unsigned long long mask = 0;
    for (int i = 0; i < count; i++) {
        if (provided[i]) {
            mask |= 1ULL << i;
        } else {
            regs[i] = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", regs[i]);
        }
    }
    for (int i = 0; i < sig->required_count - param_offset; i++) {
        if (i >= 0 && i < count && !provided[i]) lc->failed = 1;
    }
    *out_regs = regs;
    *out_count = count;
    *out_mask = mask;
    free(provided);
}

static LLVMProcSignature* llvm_find_class_init_signature(LLVMCompiler* lc,
                                                           LLVMClassInfo* info,
                                                           int* param_offset,
                                                           char** out_name) {
    *param_offset = 0;
    *out_name = NULL;
    LLVMClassInfo* current = info;
    while (current != NULL) {
        for (Stmt* m = current->declaration->methods; m != NULL; m = m->next) {
            if (m->type != STMT_PROC ||
                !(m->as.proc.name.length == 4 &&
                  strncmp(m->as.proc.name.start, "init", 4) == 0)) continue;
            char* method_name = class_method_name(current->name, m->as.proc.name);
            LLVMProcSignature* sig = llc_find_proc_signature(lc, method_name);
            free(method_name);
            if (sig == NULL) return NULL;
            if (sig->param_count > 0 && sig->param_names[0] != NULL &&
                strcmp(sig->param_names[0], "self") == 0) {
                *param_offset = 1;
            }
            *out_name = SAGE_STRDUP(current->name);
            return sig;
        }
        current = current->parent_name != NULL
            ? llc_find_class_info(lc, current->parent_name) : NULL;
    }
    return NULL;
}

static LLVMProcSignature* llvm_find_method_signature(LLVMCompiler* lc,
                                                     LLVMClassInfo* info,
                                                     const char* method_name,
                                                     int* param_offset,
                                                     char** out_qualified_name) {
    *param_offset = 0;
    *out_qualified_name = NULL;
    LLVMClassInfo* current = info;
    while (current != NULL) {
        for (Stmt* m = current->declaration->methods; m != NULL; m = m->next) {
            if (m->type != STMT_PROC) continue;
            size_t length = strlen(method_name);
            if ((size_t)m->as.proc.name.length != length ||
                strncmp(m->as.proc.name.start, method_name, length) != 0) {
                continue;
            }
            char* qualified = class_method_name(current->name, m->as.proc.name);
            LLVMProcSignature* sig = llc_find_proc_signature(lc, qualified);
            if (sig == NULL) {
                free(qualified);
                return NULL;
            }
            if (sig->param_count > 0 && sig->param_names[0] != NULL &&
                strcmp(sig->param_names[0], "self") == 0) {
                *param_offset = 1;
            }
            *out_qualified_name = qualified;
            return sig;
        }
        current = current->parent_name != NULL
            ? llc_find_class_info(lc, current->parent_name) : NULL;
    }
    return NULL;
}

static int llvm_emit_class_construct(LLVMCompiler* lc, LLVMClassInfo* info, Expr* call) {
    int* arg_regs = NULL;
    int arg_count = 0;
    unsigned long long arg_mask = 0;
    int param_offset = 0;
    char* init_owner = NULL;
    LLVMProcSignature* init = llvm_find_class_init_signature(lc, info, &param_offset, &init_owner);
    if (init != NULL) {
        size_t size = strlen(init_owner) + 8;
        char* init_name = SAGE_ALLOC(size);
        snprintf(init_name, size, "%s_init", init_owner);
        llvm_emit_callable_arguments(lc, call, init_name, param_offset,
                                     &arg_regs, &arg_count, &arg_mask);
        free(init_name);
        free(init_owner);
    } else {
        llvm_emit_callable_arguments(lc, call, NULL, 0,
                                     &arg_regs, &arg_count, &arg_mask);
    }

    int class_ptr = llvm_emit_string_ptr(lc, info->name);
    int result;
    if (arg_count > 0) {
        int args = llc_new_reg(lc);
        ll_line(lc, "%%%d = alloca %%SageValue, i32 %d", args, arg_count);
        for (int i = 0; i < arg_count; i++) {
            int slot = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr %%SageValue, %%SageValue* %%%d, i32 %d", slot, args, i);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", arg_regs[i], slot);
        }
        result = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_construct_class(i8* %%%d, %%SageValue* %%%d, i32 %d, i64 %llu)",
                result, class_ptr, args, arg_count, arg_mask);
    } else {
        result = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_construct_class(i8* %%%d, %%SageValue* null, i32 0, i64 %llu)",
                result, class_ptr, arg_mask);
    }
    free(arg_regs);
    return result;
}

static int llvm_emit_struct_construct(LLVMCompiler* lc, LLVMStructInfo* info, Expr* call) {
    int object_reg = llc_new_reg(lc);
    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_new()", object_reg);

    int field_count = info != NULL ? info->field_count : 0;
    int* regs = field_count > 0 ? SAGE_ALLOC(sizeof(int) * (size_t)field_count) : NULL;
    for (int i = 0; i < field_count; i++) regs[i] = -1;

    int positional = 0;
    if (call != NULL) {
        for (int i = 0; i < call->as.call.arg_count; i++) {
            int target = -1;
            const char* keyword = call->as.call.kw_names != NULL ? call->as.call.kw_names[i] : NULL;
            if (keyword != NULL && info != NULL) {
                for (int j = 0; j < field_count; j++) {
                    if (info->field_names[j] != NULL && strcmp(keyword, info->field_names[j]) == 0) {
                        target = j;
                        break;
                    }
                }
                if (target < 0) lc->failed = 1;
            } else {
                while (positional < field_count && regs[positional] >= 0) positional++;
                if (positional < field_count) target = positional++;
            }

            int value = llvm_emit_expr(lc, call->as.call.args[i]);
            if (target >= 0 && target < field_count && regs[target] < 0) {
                regs[target] = value;
            } else {
                if (call->as.call.arg_count > field_count) lc->failed = 1;
                if (target >= 0) lc->failed = 1;
            }
        }
        if (call->as.call.arg_count > field_count) lc->failed = 1;
    }

    for (int i = 0; i < field_count; i++) {
        if (regs[i] < 0) {
            regs[i] = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", regs[i]);
        }
        llvm_emit_dict_set_string(lc, object_reg, info->field_names[i], regs[i]);
    }
    free(regs);
    return object_reg;
}

static void llvm_emit_type_store(LLVMCompiler* lc, const char* name, int value_reg) {
    if (llc_has_global(lc, name)) {
        ll_line(lc, "store %%SageValue %%%d, %%SageValue* @%s", value_reg, name);
    } else {
        ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", value_reg, name);
    }
}

static void llvm_emit_struct_definition(LLVMCompiler* lc, StructStmt* stmt) {
    if (stmt == NULL || stmt->name.start == NULL) return;
    char* name = token_to_str(stmt->name);
    LLVMStructInfo* info = llc_find_struct_info(lc, name);
    int object_reg = llc_new_reg(lc);
    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_new()", object_reg);
    if (info != NULL) {
        for (int i = 0; i < info->field_count; i++) {
            int field_reg = llvm_emit_string_value(lc, info->field_names[i]);
            llvm_emit_dict_set_string(lc, object_reg, info->field_names[i], field_reg);
        }
    }
    int name_reg = llvm_emit_string_value(lc, name);
    llvm_emit_dict_set_string(lc, object_reg, "__name__", name_reg);
    llvm_emit_type_store(lc, name, object_reg);
    free(name);
}

static void llvm_emit_enum_definition(LLVMCompiler* lc, EnumStmt* stmt) {
    if (stmt == NULL || stmt->name.start == NULL) return;
    char* name = token_to_str(stmt->name);
    LLVMEnumInfo* info = llc_find_enum_info(lc, name);
    int object_reg = llc_new_reg(lc);
    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_new()", object_reg);
    if (info != NULL) {
        for (int i = 0; i < info->variant_count; i++) {
            int value_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %.17e)", value_reg, (double)i);
            llvm_emit_dict_set_string(lc, object_reg, info->variant_names[i], value_reg);
        }
    }
    int name_reg = llvm_emit_string_value(lc, name);
    llvm_emit_dict_set_string(lc, object_reg, "__name__", name_reg);
    llvm_emit_type_store(lc, name, object_reg);
    free(name);
}

static int llvm_is_builtin_call(const char* name) {
    static const char* names[] = {
        "str", "len", "tonumber", "push", "pop", "array_extend",
        "array_reverse", "slice", "range", "dict_keys", "dict_values",
        "dict_has", "dict_delete", "upper", "lower", "strip", "split",
        "join", "replace", "mem_alloc", "mem_free", "mem_read", "mem_write",
        "mem_size", "struct_def", "struct_new", "struct_get", "struct_set",
        "struct_size", "asm_arch", "type", "chr", "ord", "input", "gc_disable",
        "gc_enable", "gc_collect", NULL
    };
    if (name == NULL) return 0;
    for (int i = 0; names[i] != NULL; i++) {
        if (strcmp(name, names[i]) == 0) return 1;
    }
    return 0;
}

static int llvm_emit_adapter_call(LLVMCompiler* lc, const char* adapter_symbol,
                                  const int* args, int argc,
                                  unsigned long long mask) {
    int callable = llc_new_reg(lc);
    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", callable);
    int array = -1;
    if (argc > 0) {
        array = llc_new_reg(lc);
        ll_line(lc, "%%%d = alloca %%SageValue, i32 %d", array, argc);
        for (int i = 0; i < argc; i++) {
            int slot = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr %%SageValue, %%SageValue* %%%d, i32 %d",
                    slot, array, i);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", args[i], slot);
        }
    }
    int result = llc_new_reg(lc);
    if (array >= 0) {
        ll_line(lc, "%%%d = call %%SageValue @%s(%%SageValue %%%d, %%SageValue* %%%d, i32 %d, i64 %llu)",
                result, adapter_symbol, callable, array, argc, mask);
    } else {
        ll_line(lc, "%%%d = call %%SageValue @%s(%%SageValue %%%d, %%SageValue* null, i32 0, i64 %llu)",
                result, adapter_symbol, callable, mask);
    }
    return result;
}

static int llvm_emit_dynamic_call(LLVMCompiler* lc, int callee,
                                  const int* args, int argc,
                                  unsigned long long mask) {
    int array = -1;
    if (argc > 0) {
        array = llc_new_reg(lc);
        ll_line(lc, "%%%d = alloca %%SageValue, i32 %d", array, argc);
        for (int i = 0; i < argc; i++) {
            int slot = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr %%SageValue, %%SageValue* %%%d, i32 %d", slot, array, i);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", args[i], slot);
        }
    }
    int result = llc_new_reg(lc);
    if (array >= 0) {
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_call_dynamic(%%SageValue %%%d, %%SageValue* %%%d, i32 %d, i64 %llu)",
                result, callee, array, argc, mask);
    } else {
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_call_dynamic(%%SageValue %%%d, %%SageValue* null, i32 0, i64 %llu)",
                result, callee, mask);
    }
    return result;
}

static int llvm_current_try_capture(LLVMCompiler* lc, const char* name) {
    if (lc->current_try_callback == NULL || name == NULL) return 0;
    for (int i = 0; i < lc->current_try_callback->capture_count; i++) {
        if (strcmp(lc->current_try_callback->captures[i], name) == 0) return 1;
    }
    return 0;
}

static int llvm_emit_expr(LLVMCompiler* lc, Expr* expr) {
    if (expr == NULL) {
        int r = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
        return r;
    }

    switch (expr->type) {
        case EXPR_NUMBER: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %.17e)", r, expr->as.number.value);
            return r;
        }
        case EXPR_STRING: {
            int str_id = llc_add_string(lc, expr->as.string.value);
            size_t slen = strlen(expr->as.string.value) + 1;
            int ptr_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                    ptr_reg, slen, slen, str_id);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_string(i8* %%%d)", r, ptr_reg);
            return r;
        }
        case EXPR_BOOL: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 %d)", r, expr->as.boolean.value ? 1 : 0);
            return r;
        }
        case EXPR_NIL: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
        case EXPR_BINARY: {
            if (expr->as.binary.op.type == TOKEN_AND || expr->as.binary.op.type == TOKEN_OR) {
                int left = llvm_emit_expr(lc, expr->as.binary.left);
                int left_bool = llc_new_reg(lc);
                ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", left_bool, left);
                int left_cmp = llc_new_reg(lc);
                ll_line(lc, "%%%d = icmp ne i32 %%%d, 0", left_cmp, left_bool);
                int decided_label = llc_new_label(lc);
                int evaluate_label = llc_new_label(lc);
                int merge_label = llc_new_label(lc);
                if (expr->as.binary.op.type == TOKEN_AND) {
                    ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", left_cmp, evaluate_label, decided_label);
                } else {
                    ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", left_cmp, decided_label, evaluate_label);
                }
                lc->block_terminated = 1;

                ll_emit(lc, "L%d:\n", decided_label);
                lc->block_terminated = 0;
                int decided_value = llc_new_reg(lc);
                if (expr->as.binary.op.type == TOKEN_AND) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 0)", decided_value);
                } else {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 1)", decided_value);
                }
                ll_line(lc, "br label %%L%d", merge_label);
                lc->block_terminated = 1;

                ll_emit(lc, "L%d:\n", evaluate_label);
                lc->block_terminated = 0;
                int right = llvm_emit_expr(lc, expr->as.binary.right);
                int right_bool = llc_new_reg(lc);
                ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", right_bool, right);
                int right_value = llc_new_reg(lc);
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 %%%d)", right_value, right_bool);
                ll_line(lc, "br label %%L%d", merge_label);
                lc->block_terminated = 1;

                ll_emit(lc, "L%d:\n", merge_label);
                lc->block_terminated = 0;
                int result = llc_new_reg(lc);
                ll_line(lc, "%%%d = phi %%SageValue [ %%%d, %%L%d ], [ %%%d, %%L%d ]",
                        result, decided_value, decided_label, right_value, evaluate_label);
                return result;
            }

            int left = llvm_emit_expr(lc, expr->as.binary.left);
            int right = llvm_emit_expr(lc, expr->as.binary.right);
            int r = llc_new_reg(lc);

            const char* op = expr->as.binary.op.start;
            int op_len = expr->as.binary.op.length;

            if (op_len == 1) {
                switch (*op) {
                    case '+': ll_line(lc, "%%%d = call %%SageValue @sage_rt_add(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '-': ll_line(lc, "%%%d = call %%SageValue @sage_rt_sub(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '*': ll_line(lc, "%%%d = call %%SageValue @sage_rt_mul(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '/': ll_line(lc, "%%%d = call %%SageValue @sage_rt_div(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '%': ll_line(lc, "%%%d = call %%SageValue @sage_rt_mod(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '<': ll_line(lc, "%%%d = call %%SageValue @sage_rt_lt(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '>': ll_line(lc, "%%%d = call %%SageValue @sage_rt_gt(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '&': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_and(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '|': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_or(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '^': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_xor(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '~': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_not(%%SageValue %%%d)", r, left); break;
                    default:
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                        break;
                }
            } else if (op_len == 2) {
                if (op[0] == '=' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_eq(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '!' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_neq(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '<' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_lte(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '>' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_gte(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (memcmp(op, "or", 2) == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_or(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '<' && op[1] == '<') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_shl(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '>' && op[1] == '>') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_shr(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                }
            } else if (op_len == 3 && memcmp(op, "and", 3) == 0) {
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_and(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
            } else if (op_len == 3 && memcmp(op, "not", 3) == 0) {
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_not(%%SageValue %%%d)", r, left);
            } else {
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            }
            return r;
        }
        case EXPR_VARIABLE: {
            char* name = token_to_str(expr->as.variable.name);
            // Module references (gpu, math, etc.) are handled at EXPR_GET/EXPR_CALL level;
            // if we reach here, emit nil as a placeholder (module objects don't exist in LLVM mode)
            if (llc_has_module(lc, name)) {
                int r = llc_new_reg(lc);
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                free(name);
                return r;
            }

            ImportedConst* imported = llc_find_imported_const(lc, name);
            if (imported != NULL) {
                int r;
                switch (imported->value.type) {
                    case IMPORT_CONST_NUMBER:
                        r = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %.17e)",
                                r, imported->value.number_value);
                        break;
                    case IMPORT_CONST_BOOL:
                        r = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 %d)",
                                r, imported->value.bool_value ? 1 : 0);
                        break;
                    case IMPORT_CONST_STRING: {
                        int str_id = llc_add_string(lc, imported->value.string_value);
                        size_t slen = strlen(imported->value.string_value) + 1;
                        int ptr_reg = llc_new_reg(lc);
                        ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                                ptr_reg, slen, slen, str_id);
                        r = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_string(i8* %%%d)", r, ptr_reg);
                        break;
                    }
                    case IMPORT_CONST_NIL:
                    default:
                        r = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                        break;
                }
                free(name);
                return r;
            }

            LLVMImportedValue* imported_value =
                llc_find_imported_binding_value(lc, name);
            if (imported_value != NULL) {
                int r;
                if (imported_value->proc_scope != NULL) {
                    int ptr = llc_new_reg(lc);
                    ll_line(lc, "%%%d = bitcast %%SageValue (...)* @%s to i8*",
                            ptr, imported_value->proc_scope->adapter_symbol);
                    r = llc_new_reg(lc);
                    ll_line(lc,
                            "%%%d = call %%SageValue @sage_rt_make_function(i8* %%%d, i32 %d, i32 %d)",
                            r, ptr, imported_value->proc_scope->proc->param_count,
                            imported_value->proc_scope->proc->required_count);
                } else if (imported_value->global_name != NULL) {
                    r = llc_new_reg(lc);
                    ll_line(lc, "%%%d = load %%SageValue, %%SageValue* @%s",
                            r, imported_value->global_name);
                } else {
                    r = llc_new_reg(lc);
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                }
                free(name);
                return r;
            }

            const char* module_name = lc->current_scope != NULL &&
                                     lc->current_scope->module_name != NULL
                ? lc->current_scope->module_name : lc->current_module_name;
            if (module_name != NULL) {
                LLVMImportedGlobal* module_global =
                    llc_find_imported_global(lc, module_name, name);
                if (module_global != NULL) {
                    int r = llc_new_reg(lc);
                    ll_line(lc, "%%%d = load %%SageValue, %%SageValue* @%s",
                            r, module_global->global_name);
                    free(name);
                    return r;
                }
            }

            int is_local = 0;
            if (lc->current_scope != NULL && lc->current_scope != lc->main_scope) {
                if (llvm_name_set_has(&lc->current_scope->bound_names, name)) {
                    is_local = 1;
                } else {
                    for (int i = 0; i < lc->current_scope->capture_count; i++) {
                        if (strcmp(lc->current_scope->captures[i], name) == 0) {
                            is_local = 1;
                            break;
                        }
                    }
                }
            }
            int is_global = 0;
            for (int i = 0; i < lc->global_count; i++) {
                if (strcmp(lc->global_names[i], name) == 0) {
                    is_global = 1;
                    break;
                }
            }
            int is_proc = 0;
            for (int i = 0; i < lc->proc_count; i++) {
                if (strcmp(lc->proc_names[i], name) == 0) {
                    is_proc = 1;
                    break;
                }
            }

            int is_try_capture = llvm_current_try_capture(lc, name);
            int r;
            if (!is_local && !is_global && is_proc) {
                LLVMScopeInfo* proc_scope = llc_find_top_scope_by_name(lc, name);
                const char* signature_name = proc_scope != NULL &&
                                             proc_scope->signature_name != NULL
                    ? proc_scope->signature_name : name;
                LLVMProcSignature* sig = llc_find_proc_signature(lc, signature_name);
                const char* entry_symbol = proc_scope != NULL && proc_scope->adapter_symbol != NULL
                    ? proc_scope->adapter_symbol : NULL;
                size_t symbol_size = entry_symbol != NULL
                    ? strlen(entry_symbol) + 32 : strlen(name) + 32;
                char* symbol = SAGE_ALLOC(symbol_size);
                if (entry_symbol != NULL) {
                    snprintf(symbol, symbol_size, "%s", entry_symbol);
                } else {
                    snprintf(symbol, symbol_size, "sage_fn_%s", name);
                }
                int ptr_reg = llc_new_reg(lc);
                ll_line(lc, "%%%d = bitcast %%SageValue (...)* @%s to i8*", ptr_reg, symbol);
                r = llc_new_reg(lc);
                int param_count = sig != NULL ? sig->param_count : -1;
                int required_count = sig != NULL ? sig->required_count : -1;
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_make_function(i8* %%%d, i32 %d, i32 %d)",
                        r, ptr_reg, param_count, required_count);
                free(symbol);
            } else if (is_try_capture) {
                int pointer = llc_new_reg(lc);
                int value = llc_new_reg(lc);
                ll_line(lc, "%%%d = load %%SageValue*, %%SageValue** %%%s", pointer, name);
                ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%d", value, pointer);
                r = value;
            } else {
                r = llc_new_reg(lc);
                if (is_local) {
                    ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%s", r, name);
                } else if (is_global) {
                    ll_line(lc, "%%%d = load %%SageValue, %%SageValue* @%s", r, name);
                } else {
                    ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%s", r, name);
                }
            }
            free(name);
            return r;
        }
        case EXPR_CALL: {
            int* arg_regs = NULL;
            int call_arg_count = 0;
            unsigned long long call_arg_mask = 0;
            char* direct_name = NULL;
            const char* direct_signature_name = NULL;
            LLVMProcSignature* direct_signature = NULL;
            LLVMScopeInfo* direct_scope = NULL;
            LLVMStructInfo* direct_struct = NULL;
            LLVMClassInfo* direct_class = NULL;

            if (expr->as.call.callee != NULL && expr->as.call.callee->type == EXPR_VARIABLE) {
                direct_name = token_to_str(expr->as.call.callee->as.variable.name);
                direct_class = llc_find_class_info(lc, direct_name);
                if (direct_class != NULL) {
                    int result = llvm_emit_class_construct(lc, direct_class, expr);
                    free(direct_name);
                    return result;
                }
                direct_struct = llc_find_struct_info(lc, direct_name);
                if (direct_struct != NULL) {
                    int result = llvm_emit_struct_construct(lc, direct_struct, expr);
                    free(direct_name);
                    return result;
                }

                LLVMImportedValue* imported_value =
                    llc_find_imported_binding_value(lc, direct_name);
                if (imported_value != NULL) {
                    if (imported_value->proc_scope == NULL) {
                        fprintf(stderr, "LLVM backend: imported value '%s' is not callable\n",
                                direct_name);
                        lc->failed = 1;
                        free(direct_name);
                        int result = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", result);
                        return result;
                    }
                    llvm_emit_callable_arguments(
                        lc, expr, imported_value->proc_scope->signature_name, 0,
                        &arg_regs, &call_arg_count, &call_arg_mask);
                    int result = llvm_emit_adapter_call(
                        lc, imported_value->proc_scope->adapter_symbol, arg_regs,
                        call_arg_count, call_arg_mask);
                    free(arg_regs);
                    free(direct_name);
                    return result;
                }

                direct_scope = llc_find_top_scope_by_name(lc, direct_name);
                direct_signature_name = direct_scope != NULL &&
                                        direct_scope->signature_name != NULL
                    ? direct_scope->signature_name : direct_name;
                direct_signature = llc_find_proc_signature(lc, direct_signature_name);
            }

            if (direct_signature != NULL) {
                llvm_emit_callable_arguments(lc, expr, direct_signature_name, 0,
                                             &arg_regs, &call_arg_count, &call_arg_mask);
                int result;
                if (direct_scope != NULL && !direct_scope->is_nested) {
                    result = llvm_emit_adapter_call(
                        lc, direct_scope->adapter_symbol, arg_regs,
                        call_arg_count, call_arg_mask);
                } else {
                    int callee = llvm_emit_expr(lc, expr->as.call.callee);
                    result = llvm_emit_dynamic_call(lc, callee, arg_regs,
                                                     call_arg_count, call_arg_mask);
                }
                free(arg_regs);
                free(direct_name);
                return result;
            }

            if (direct_name != NULL) {
                free(direct_name);
                direct_name = NULL;
            }
            llvm_emit_callable_arguments(lc, expr, NULL, 0,
                                         &arg_regs, &call_arg_count, &call_arg_mask);

            if (expr->as.call.callee->type == EXPR_SUPER) {
                if (lc->parent_class_name == NULL) {
                    fprintf(stderr, "LLVM backend: 'super' used outside a class with a parent\n");
                    int r = llc_new_reg(lc);
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                    if (arg_regs) free(arg_regs);
                    return r;
                }

                int arg_offset = 0;
                if (expr->as.call.arg_count > 0 &&
                    expr->as.call.args[0]->type == EXPR_VARIABLE) {
                    char* first_arg_name = token_to_str(expr->as.call.args[0]->as.variable.name);
                    if (strcmp(first_arg_name, "self") == 0) arg_offset = 1;
                    free(first_arg_name);
                }

                char* method = token_to_str(expr->as.call.callee->as.super_expr.method);
                LLVMClassInfo* parent_info = llc_find_class_info(lc, lc->parent_class_name);
                int parent_offset = 0;
                char* qualified_name = NULL;
                LLVMProcSignature* parent_signature = llvm_find_method_signature(
                    lc, parent_info, method, &parent_offset, &qualified_name);
                LLVMScopeInfo* parent_scope = llc_find_scope_by_qualified_name(
                    lc, qualified_name);
                if (parent_signature != NULL && parent_scope != NULL) {
                    Expr adjusted = *expr;
                    if (arg_offset > 0) {
                        adjusted.as.call.args = expr->as.call.args + arg_offset;
                        adjusted.as.call.kw_names = expr->as.call.kw_names != NULL
                            ? expr->as.call.kw_names + arg_offset : NULL;
                        adjusted.as.call.arg_count -= arg_offset;
                    }
                    const int* raw_regs = arg_offset > 0
                        ? arg_regs + arg_offset : arg_regs;
                    int raw_count = adjusted.as.call.arg_count;
                    int* remapped_regs = NULL;
                    int remapped_count = 0;
                    unsigned long long remapped_mask = 0;
                    llvm_remap_callable_arguments(
                        lc, &adjusted, qualified_name, parent_offset,
                        raw_regs, raw_count, &remapped_regs, &remapped_count,
                        &remapped_mask);
                    free(arg_regs);
                    arg_regs = remapped_regs;
                    call_arg_count = remapped_count;
                    call_arg_mask = remapped_mask;
                    int* full_args = NULL;
                    int full_count = call_arg_count;
                    unsigned long long full_mask = call_arg_mask;
                    if (parent_offset > 0) {
                        int self_value = llc_new_reg(lc);
                        ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%self", self_value);
                        full_count = call_arg_count + 1;
                        full_args = SAGE_ALLOC(sizeof(int) * (size_t)full_count);
                        full_args[0] = self_value;
                        for (int i = 0; i < call_arg_count; i++) {
                            full_args[i + 1] = arg_regs[i];
                        }
                        full_mask = (call_arg_mask << 1) | 1ULL;
                    } else {
                        full_args = arg_regs;
                    }
                    int result = llvm_emit_adapter_call(
                        lc, parent_scope->adapter_symbol, full_args,
                        full_count, full_mask);
                    if (full_args != arg_regs) free(full_args);
                    free(arg_regs);
                    free(qualified_name);
                    free(method);
                    return result;
                }

                free(qualified_name);
                int r = llc_new_reg(lc);
                ll_emit(lc, "    %%%d = call %%SageValue @sage_fn_%s_%s(%%SageValue %%arg_self", r, lc->parent_class_name, method);
                for (int i = 0; i < expr->as.call.arg_count - arg_offset; i++) {
                    ll_emit(lc, ", %%SageValue %%%d", arg_regs[i + arg_offset]);
                }
                ll_emit(lc, ")\n");
                free(method);
                if (arg_regs) free(arg_regs);
                return r;
            }

            int r = -1;

            // Check for builtin calls
            if (expr->as.call.callee->type == EXPR_VARIABLE) {
                char* name = token_to_str(expr->as.call.callee->as.variable.name);
                if (llvm_is_builtin_call(name)) r = llc_new_reg(lc);

                if (strcmp(name, "str") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_str(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "len") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_len(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "tonumber") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_tonumber(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "push") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_push(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "pop") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_pop(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "array_extend") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_extend(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "array_reverse") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_reverse(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "slice") == 0 && expr->as.call.arg_count == 3) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_slice(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2]);
                } else if (strcmp(name, "range") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_range(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "range") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_range2(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "range") == 0 && expr->as.call.arg_count == 3) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_range3(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2]);
                } else if (strcmp(name, "dict_keys") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_keys(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "dict_values") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_values(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "dict_has") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_has(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "dict_delete") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_delete(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "upper") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_upper(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "lower") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_lower(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "strip") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_strip(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "split") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_split(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "join") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_join(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "replace") == 0 && expr->as.call.arg_count == 3) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_replace(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2]);
                } else if (strcmp(name, "mem_alloc") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_mem_alloc(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "mem_free") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_mem_free(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "mem_read") == 0 && expr->as.call.arg_count == 3) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_mem_read(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2]);
                } else if (strcmp(name, "mem_write") == 0 && expr->as.call.arg_count == 4) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_mem_write(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3]);
                } else if (strcmp(name, "mem_size") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_mem_size(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "struct_def") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_struct_def(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "struct_new") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_struct_new(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "struct_get") == 0 && expr->as.call.arg_count == 3) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_struct_get(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2]);
                } else if (strcmp(name, "struct_set") == 0 && expr->as.call.arg_count == 4) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_struct_set(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3]);
                } else if (strcmp(name, "struct_size") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_struct_size(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "asm_arch") == 0 && expr->as.call.arg_count == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_asm_arch()", r);
                } else if (strcmp(name, "type") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_type(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "chr") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_chr(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "ord") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_ord(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "input") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_input(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "gc_disable") == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                } else if (strcmp(name, "gc_enable") == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                } else if (strcmp(name, "gc_collect") == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                } else {
                    int callee = llvm_emit_expr(lc, expr->as.call.callee);
                    r = llvm_emit_dynamic_call(lc, callee, arg_regs,
                                                call_arg_count, call_arg_mask);
                }

                free(name);
            } else if (expr->as.call.callee->type == EXPR_GET &&
                       expr->as.call.callee->as.get.object->type != EXPR_VARIABLE) {
                char* method_name = token_to_str(expr->as.call.callee->as.get.property);
                Expr* object_expr = expr->as.call.callee->as.get.object;
                LLVMClassInfo* object_class = NULL;
                if (object_expr->type == EXPR_CALL &&
                    object_expr->as.call.callee != NULL &&
                    object_expr->as.call.callee->type == EXPR_VARIABLE) {
                    char* class_name = token_to_str(object_expr->as.call.callee->as.variable.name);
                    object_class = llc_find_class_info(lc, class_name);
                    free(class_name);
                }
                int method_offset = 0;
                char* qualified_name = NULL;
                LLVMProcSignature* method_signature = NULL;
                if (object_class != NULL) {
                    method_signature = llvm_find_method_signature(
                        lc, object_class, method_name, &method_offset,
                        &qualified_name);
                }
                if (method_signature != NULL) {
                    int* remapped_regs = NULL;
                    int remapped_count = 0;
                    unsigned long long remapped_mask = 0;
                    llvm_remap_callable_arguments(
                        lc, expr, qualified_name, method_offset,
                        arg_regs, call_arg_count, &remapped_regs,
                        &remapped_count, &remapped_mask);
                    free(arg_regs);
                    arg_regs = remapped_regs;
                    call_arg_count = remapped_count;
                    call_arg_mask = remapped_mask;
                }
                free(qualified_name);
                int object = llvm_emit_expr(lc, object_expr);
                int method_ptr = llvm_emit_string_ptr(lc, method_name);
                int method_result;
                if (call_arg_count > 0) {
                    int array = llc_new_reg(lc);
                    ll_line(lc, "%%%d = alloca %%SageValue, i32 %d", array, call_arg_count);
                    for (int i = 0; i < call_arg_count; i++) {
                        int slot = llc_new_reg(lc);
                        ll_line(lc, "%%%d = getelementptr %%SageValue, %%SageValue* %%%d, i32 %d",
                                slot, array, i);
                        ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", arg_regs[i], slot);
                    }
                    method_result = llc_new_reg(lc);
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_call_method(%%SageValue %%%d, i8* %%%d, %%SageValue* %%%d, i32 %d, i64 %llu)",
                            method_result, object, method_ptr, array, call_arg_count,
                            call_arg_mask);
                } else {
                    method_result = llc_new_reg(lc);
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_call_method(%%SageValue %%%d, i8* %%%d, %%SageValue* null, i32 0, i64 %llu)",
                            method_result, object, method_ptr, call_arg_mask);
                }
                free(method_name);
                free(arg_regs);
                return method_result;
            } else if (expr->as.call.callee->type == EXPR_GET &&
                       expr->as.call.callee->as.get.object->type == EXPR_VARIABLE) {
                char* mod_name = token_to_str(expr->as.call.callee->as.get.object->as.variable.name);
                char* method_name = token_to_str(expr->as.call.callee->as.get.property);

                const char* source_module = llc_module_name_for_binding(lc, mod_name);
                if (source_module != NULL) {
                    LLVMScopeInfo* proc_scope = llc_find_module_proc_scope(
                        lc, source_module, method_name);
                    int method_result;
                    if (proc_scope != NULL) {
                        int* remapped_regs = NULL;
                        int remapped_count = 0;
                        unsigned long long remapped_mask = 0;
                        llvm_remap_callable_arguments(
                            lc, expr, proc_scope->signature_name, 0,
                            arg_regs, call_arg_count, &remapped_regs,
                            &remapped_count, &remapped_mask);
                        free(arg_regs);
                        arg_regs = remapped_regs;
                        call_arg_count = remapped_count;
                        call_arg_mask = remapped_mask;
                        method_result = llvm_emit_adapter_call(
                            lc, proc_scope->adapter_symbol, arg_regs,
                            call_arg_count, call_arg_mask);
                    } else {
                        fprintf(stderr,
                                "LLVM backend: source module '%s' has no callable member '%s'\n",
                                source_module, method_name);
                        lc->failed = 1;
                        method_result = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", method_result);
                    }
                    free(mod_name);
                    free(method_name);
                    free(arg_regs);
                    return method_result;
                }

                if (!llc_has_module(lc, mod_name)) {
                    LLVMClassInfo* object_class = llc_find_class_info(lc, mod_name);
                    if (object_class == NULL) {
                        int value_shadowed = 0;
                        if (lc->current_scope != NULL && lc->current_scope != lc->main_scope) {
                            value_shadowed = llvm_name_set_has(&lc->current_scope->bound_names, mod_name);
                            for (int i = 0; !value_shadowed && i < lc->current_scope->capture_count; i++) {
                                if (strcmp(lc->current_scope->captures[i], mod_name) == 0) {
                                    value_shadowed = 1;
                                }
                            }
                        }
                        if (!value_shadowed) {
                            const char* value_class = llc_find_value_class(lc, mod_name);
                            if (value_class != NULL) {
                                object_class = llc_find_class_info(lc, value_class);
                            }
                        }
                    }
                    int method_offset = 0;
                    char* qualified_name = NULL;
                    LLVMProcSignature* method_signature = NULL;
                    if (object_class != NULL) {
                        method_signature = llvm_find_method_signature(
                            lc, object_class, method_name, &method_offset,
                            &qualified_name);
                    }
                    if (method_signature != NULL) {
                        int* remapped_regs = NULL;
                        int remapped_count = 0;
                        unsigned long long remapped_mask = 0;
                        llvm_remap_callable_arguments(
                            lc, expr, qualified_name, method_offset,
                            arg_regs, call_arg_count, &remapped_regs,
                            &remapped_count, &remapped_mask);
                        free(arg_regs);
                        arg_regs = remapped_regs;
                        call_arg_count = remapped_count;
                        call_arg_mask = remapped_mask;
                    }
                    free(qualified_name);
                    int object = llvm_emit_expr(lc, expr->as.call.callee->as.get.object);
                    int method_ptr = llvm_emit_string_ptr(lc, method_name);
                    int method_result;
                    if (call_arg_count > 0) {
                        int array = llc_new_reg(lc);
                        ll_line(lc, "%%%d = alloca %%SageValue, i32 %d", array, call_arg_count);
                        for (int i = 0; i < call_arg_count; i++) {
                            int slot = llc_new_reg(lc);
                            ll_line(lc, "%%%d = getelementptr %%SageValue, %%SageValue* %%%d, i32 %d", slot, array, i);
                            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", arg_regs[i], slot);
                        }
                        method_result = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_call_method(%%SageValue %%%d, i8* %%%d, %%SageValue* %%%d, i32 %d, i64 %llu)",
                                method_result, object, method_ptr, array, call_arg_count,
                                call_arg_mask);
                    } else {
                        method_result = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_call_method(%%SageValue %%%d, i8* %%%d, %%SageValue* null, i32 0, i64 %llu)",
                                method_result, object, method_ptr, call_arg_mask);
                    }
                    free(mod_name);
                    free(method_name);
                    free(arg_regs);
                    return method_result;
                }

                if (llc_has_module(lc, mod_name) && strcmp(mod_name, "gpu") == 0) {
                    int gpu_r = llvm_try_emit_gpu_call(lc, method_name, arg_regs, expr->as.call.arg_count);
                    if (gpu_r >= 0) {
                        free(mod_name);
                        free(method_name);
                        free(arg_regs);
                        return gpu_r;
                    }
                }

                r = llc_new_reg(lc);

                // io module: readfile, writefile
                int handled = 0;
                if (strcmp(mod_name, "io") == 0) {
                    if (strcmp(method_name, "readfile") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_readfile(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    } else if (strcmp(method_name, "writefile") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_writefile(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    } else if (strcmp(method_name, "readbytes") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_readbytes(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    } else if (strcmp(method_name, "writebytes") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_writebytes(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    } else if (strcmp(method_name, "appendbytes") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_appendbytes(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    } else if (strcmp(method_name, "exists") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_exists(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    }
                }
                // ml_native module: dispatch to sage_rt_* runtime functions
                if (!handled && strcmp(mod_name, "ml_native") == 0) {
                    if (strcmp(method_name, "load_weights") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_load_weights(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "forward_pass") == 0 && expr->as.call.arg_count == 17) {
                        // 17 args: embed,qw,kw,vw,ow,gate,up,down,norm1,norm2,fnorm,lmhead,ids,d,ff,V,S
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_forward_pass("
                            "%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, "
                            "%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, "
                            "%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, "
                            "%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, "
                            "%%SageValue %%%d)",
                            r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3],
                            arg_regs[4], arg_regs[5], arg_regs[6], arg_regs[7],
                            arg_regs[8], arg_regs[9], arg_regs[10], arg_regs[11],
                            arg_regs[12], arg_regs[13], arg_regs[14], arg_regs[15], arg_regs[16]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "matmul") == 0 && expr->as.call.arg_count == 5) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_matmul(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "rms_norm") == 0 && expr->as.call.arg_count == 5) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_rms_norm(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "silu") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_silu(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "add") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_add(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "scale") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_scale(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "cross_entropy") == 0 && expr->as.call.arg_count == 4) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_cross_entropy(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "benchmark") == 0) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "gpu_available") == 0) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 0)", r);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "auto_parallel") == 0) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double 1.0)", r);
                        handled = 1;
                    }
                }

                // Fallback: emit as nil for unrecognized module calls
                if (!handled) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                }
                free(mod_name);
                free(method_name);
            } else {
                int callee_reg = llvm_emit_expr(lc, expr->as.call.callee);
                r = llvm_emit_dynamic_call(lc, callee_reg, arg_regs,
                                            call_arg_count, call_arg_mask);
            }

            free(arg_regs);
            return r;
        }
        case EXPR_ARRAY: {
            int arr_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_new(i32 %d)", arr_reg, expr->as.array.count);
            for (int i = 0; i < expr->as.array.count; i++) {
                int elem = llvm_emit_expr(lc, expr->as.array.elements[i]);
                ll_line(lc, "call void @sage_rt_array_set(%%SageValue %%%d, i32 %d, %%SageValue %%%d)", arr_reg, i, elem);
            }
            return arr_reg;
        }
        case EXPR_INDEX: {
            if (expr->as.index.array != NULL && expr->as.index.array->type == EXPR_VARIABLE &&
                expr->as.index.index != NULL && expr->as.index.index->type == EXPR_STRING) {
                char* enum_name = token_to_str(expr->as.index.array->as.variable.name);
                LLVMEnumInfo* info = llc_find_enum_info(lc, enum_name);
                if (info != NULL && expr->as.index.index->as.string.value != NULL) {
                    const char* variant = expr->as.index.index->as.string.value;
                    int result = -1;
                    for (int i = 0; i < info->variant_count; i++) {
                        if (strcmp(info->variant_names[i], variant) == 0) {
                            result = i;
                            break;
                        }
                    }
                    free(enum_name);
                    int r = llc_new_reg(lc);
                    if (result >= 0) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %.17e)", r, (double)result);
                    } else {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                    }
                    return r;
                }
                free(enum_name);
            }
            int arr = llvm_emit_expr(lc, expr->as.index.array);
            int idx = llvm_emit_expr(lc, expr->as.index.index);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_index(%%SageValue %%%d, %%SageValue %%%d)", r, arr, idx);
            return r;
        }
        case EXPR_INDEX_SET: {
            int arr = llvm_emit_expr(lc, expr->as.index_set.array);
            int idx = llvm_emit_expr(lc, expr->as.index_set.index);
            int val = llvm_emit_expr(lc, expr->as.index_set.value);
            ll_line(lc, "call void @sage_rt_index_set(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", arr, idx, val);
            return val;
        }
        case EXPR_DICT: {
            int dict_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_new()", dict_reg);
            for (int i = 0; i < expr->as.dict.count; i++) {
                int val = llvm_emit_expr(lc, expr->as.dict.values[i]);
                int str_id = llc_add_string(lc, expr->as.dict.keys[i]);
                size_t slen = strlen(expr->as.dict.keys[i]) + 1;
                int ptr = llc_new_reg(lc);
                ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                        ptr, slen, slen, str_id);
                ll_line(lc, "call void @sage_rt_dict_set(%%SageValue %%%d, i8* %%%d, %%SageValue %%%d)", dict_reg, ptr, val);
            }
            return dict_reg;
        }
        case EXPR_TUPLE: {
            int tup_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_tuple_new(i32 %d)", tup_reg, expr->as.tuple.count);
            for (int i = 0; i < expr->as.tuple.count; i++) {
                int elem = llvm_emit_expr(lc, expr->as.tuple.elements[i]);
                ll_line(lc, "call void @sage_rt_tuple_set(%%SageValue %%%d, i32 %d, %%SageValue %%%d)", tup_reg, i, elem);
            }
            return tup_reg;
        }
        case EXPR_SLICE: {
            int arr = llvm_emit_expr(lc, expr->as.slice.array);
            int start = llvm_emit_expr(lc, expr->as.slice.start);
            int end = llvm_emit_expr(lc, expr->as.slice.end);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_slice(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arr, start, end);
            return r;
        }
        case EXPR_GET: {
            // Check for GPU module constant access: gpu.BUFFER_STORAGE etc.
            if (expr->as.get.object->type == EXPR_VARIABLE) {
                char* mod_name = token_to_str(expr->as.get.object->as.variable.name);
                char* prop_name = token_to_str(expr->as.get.property);
                const char* source_module = llc_module_name_for_binding(lc, mod_name);
                if (source_module != NULL) {
                    LLVMImportedGlobal* global = llc_find_imported_global(
                        lc, source_module, prop_name);
                    LLVMScopeInfo* proc_scope = llc_find_module_proc_scope(
                        lc, source_module, prop_name);
                    int result = llc_new_reg(lc);
                    if (global != NULL) {
                        ll_line(lc, "%%%d = load %%SageValue, %%SageValue* @%s",
                                result, global->global_name);
                    } else if (proc_scope != NULL) {
                        int ptr = llc_new_reg(lc);
                        ll_line(lc, "%%%d = bitcast %%SageValue (...)* @%s to i8*",
                                ptr, proc_scope->adapter_symbol);
                        ll_line(lc,
                                "%%%d = call %%SageValue @sage_rt_make_function(i8* %%%d, i32 %d, i32 %d)",
                                result, ptr, proc_scope->proc->param_count,
                                proc_scope->proc->required_count);
                    } else {
                        fprintf(stderr,
                                "LLVM backend: source module '%s' has no member '%s'\n",
                                source_module, prop_name);
                        lc->failed = 1;
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", result);
                    }
                    free(mod_name);
                    free(prop_name);
                    return result;
                }
                if (llc_has_module(lc, mod_name) && strcmp(mod_name, "gpu") == 0) {
                    double const_val;
                    if (llvm_resolve_gpu_constant(prop_name, &const_val)) {
                        int r = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %.17e)", r, const_val);
                        free(mod_name);
                        free(prop_name);
                        return r;
                    }
                }
                free(mod_name);
                free(prop_name);
            }
            int obj = llvm_emit_expr(lc, expr->as.get.object);
            char* prop = token_to_str(expr->as.get.property);
            int str_id = llc_add_string(lc, prop);
            size_t slen = strlen(prop) + 1;
            int ptr = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                    ptr, slen, slen, str_id);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_get_attr(%%SageValue %%%d, i8* %%%d)", r, obj, ptr);
            free(prop);
            return r;
        }
        case EXPR_SET: {
            if (expr->as.set.object == NULL) {
                // Variable assignment: name = value
                int val = llvm_emit_expr(lc, expr->as.set.value);
                char* name = token_to_str(expr->as.set.property);
                // Check if it's a global variable
                int is_global = 0;
                for (int i = 0; i < lc->global_count; i++) {
                    if (strcmp(lc->global_names[i], name) == 0) { is_global = 1; break; }
                }
                if (llvm_current_try_capture(lc, name)) {
                    int pointer = llc_new_reg(lc);
                    ll_line(lc, "%%%d = load %%SageValue*, %%SageValue** %%%s", pointer, name);
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", val, pointer);
                } else if (is_global) {
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* @%s", val, name);
                } else {
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", val, name);
                }
                free(name);
                return val;
            }
            // Property set: object.property = value
            int obj = llvm_emit_expr(lc, expr->as.set.object);
            int val = llvm_emit_expr(lc, expr->as.set.value);
            char* prop = token_to_str(expr->as.set.property);
            int str_id = llc_add_string(lc, prop);
            size_t slen = strlen(prop) + 1;
            int ptr = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                    ptr, slen, slen, str_id);
            ll_line(lc, "call void @sage_rt_set_attr(%%SageValue %%%d, i8* %%%d, %%SageValue %%%d)", obj, ptr, val);
            free(prop);
            return val;
        }
        case EXPR_AWAIT: {
            // Await not supported in LLVM backend
            fprintf(stderr, "LLVM backend: await not supported in compiled mode\n");
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
        case EXPR_SUPER: {
            // super.method() in LLVM: emits nil (classes are interpreter-only for now)
            // The LLVM backend doesn't support full class dispatch yet
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
        // Phase 17: comptime expression — emit inner expression
        case EXPR_COMPTIME:
            return llvm_emit_expr(lc, expr->as.comptime.expression);
        default: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
    }
}

static void llvm_emit_call_adapter(LLVMCompiler* lc, LLVMScopeInfo* scope) {
    if (scope == NULL || scope->proc == NULL || scope->adapter_symbol == NULL) return;

    ProcStmt* proc = scope->proc;
    LLVMScopeInfo* previous_scope = lc->current_scope;
    int previous_block_terminated = lc->block_terminated;
    lc->current_scope = scope;
    lc->block_terminated = 0;
    lc->next_reg = 0;

    fprintf(lc->out, "define %%SageValue @%s(%%SageValue %%arg_sage_callable, "
                    "%%SageValue* %%arg_sage_args, i32 %%arg_sage_argc, "
                    "i64 %%arg_sage_mask) {\n",
            scope->adapter_symbol);
    int entry = llc_new_label(lc);
    ll_emit(lc, "L%d:\n", entry);

    for (int i = 0; i < scope->capture_count; i++) {
        const char* name = scope->captures[i];
        ll_line(lc, "%%%s = alloca %%SageValue", name);
        int value = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_closure_get(%%SageValue %%arg_sage_callable, i32 %d)",
                value, i);
        ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", value, name);
    }

    for (int i = 0; i < proc->param_count; i++) {
        char* name = token_to_str(proc->params[i]);
        ll_line(lc, "%%%s = alloca %%SageValue", name);

        int bit = llc_new_reg(lc);
        ll_line(lc, "%%%d = shl i64 1, %d", bit, i);
        int masked = llc_new_reg(lc);
        ll_line(lc, "%%%d = and i64 %%arg_sage_mask, %%%d", masked, bit);
        int has_arg = llc_new_reg(lc);
        ll_line(lc, "%%%d = icmp ne i64 %%%d, 0", has_arg, masked);
        int provided_label = llc_new_label(lc);
        int missing_label = llc_new_label(lc);
        int merge_label = llc_new_label(lc);
        ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d",
                has_arg, provided_label, missing_label);

        ll_emit(lc, "L%d:\n", provided_label);
        lc->block_terminated = 0;
        int slot = llc_new_reg(lc);
        ll_line(lc, "%%%d = getelementptr %%SageValue, %%SageValue* %%arg_sage_args, i32 %d",
                slot, i);
        int provided_value = llc_new_reg(lc);
        ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%d", provided_value, slot);
        ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", provided_value, name);
        ll_line(lc, "br label %%L%d", merge_label);

        ll_emit(lc, "L%d:\n", missing_label);
        lc->block_terminated = 0;
        int value;
        if (proc->defaults != NULL && proc->defaults[i] != NULL) {
            value = llvm_emit_expr(lc, proc->defaults[i]);
        } else {
            value = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", value);
        }
        ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", value, name);
        ll_line(lc, "br label %%L%d", merge_label);

        ll_emit(lc, "L%d:\n", merge_label);
        lc->block_terminated = 0;
        free(name);
    }

    int* values = proc->param_count > 0
        ? SAGE_ALLOC(sizeof(int) * (size_t)proc->param_count) : NULL;
    for (int i = 0; i < proc->param_count; i++) {
        char* name = token_to_str(proc->params[i]);
        values[i] = llc_new_reg(lc);
        ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%s", values[i], name);
        free(name);
    }

    int result = llc_new_reg(lc);
    fprintf(lc->out, "  %%%d = call %%SageValue @%s(", result, scope->symbol);
    if (scope->is_nested) {
        fputs("%SageValue %arg_sage_callable", lc->out);
        if (proc->param_count > 0) fputs(", ", lc->out);
    }
    for (int i = 0; i < proc->param_count; i++) {
        if (i > 0) fputs(", ", lc->out);
        fprintf(lc->out, "%%SageValue %%%d", values[i]);
    }
    fputs(")\n", lc->out);
    ll_line(lc, "ret %%SageValue %%%d", result);
    fputs("}\n\n", lc->out);
    free(values);

    lc->current_scope = previous_scope;
    lc->block_terminated = previous_block_terminated;
}

// ============================================================================
// Statement Emission
// ============================================================================

static void llvm_emit_stmt(LLVMCompiler* lc, Stmt* stmt);
static LLVMTryCallback* llvm_prepare_try_callback(LLVMCompiler* lc, Stmt* statement);

static void llvm_emit_stmt_list(LLVMCompiler* lc, Stmt* head) {
    for (Stmt* s = head; s != NULL; s = s->next) {
        if (lc->block_terminated) break;
        llvm_emit_stmt(lc, s);
    }
}

static void llvm_emit_stmt(LLVMCompiler* lc, Stmt* stmt) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_PRINT: {
            int r = llvm_emit_expr(lc, stmt->as.print.expression);
            ll_line(lc, "call void @sage_rt_print(%%SageValue %%%d)", r);
            break;
        }
        case STMT_EXPRESSION: {
            llvm_emit_expr(lc, stmt->as.expression);
            break;
        }
        case STMT_LET: {
            char* name = token_to_str(stmt->as.let.name);
            int val = llvm_emit_expr(lc, stmt->as.let.initializer);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", val, name);
            free(name);
            break;
        }
        case STMT_IF: {
            int cond_val = llvm_emit_expr(lc, stmt->as.if_stmt.condition);
            int bool_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", bool_reg, cond_val);
            int cmp_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp ne i32 %%%d, 0", cmp_reg, bool_reg);

            int then_label = llc_new_label(lc);
            int else_label = llc_new_label(lc);
            int merge_label = llc_new_label(lc);

            if (stmt->as.if_stmt.else_branch != NULL) {
                ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, then_label, else_label);
            } else {
                ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, then_label, merge_label);
            }

            ll_emit(lc, "L%d:\n", then_label);
            lc->block_terminated = 0;
            llvm_emit_stmt_list(lc, stmt->as.if_stmt.then_branch);
            if (!lc->block_terminated) ll_line(lc, "br label %%L%d", merge_label);

            if (stmt->as.if_stmt.else_branch != NULL) {
                ll_emit(lc, "L%d:\n", else_label);
                lc->block_terminated = 0;
                llvm_emit_stmt_list(lc, stmt->as.if_stmt.else_branch);
                if (!lc->block_terminated) ll_line(lc, "br label %%L%d", merge_label);
            }

            ll_emit(lc, "L%d:\n", merge_label);
            lc->block_terminated = 0;
            break;
        }
        case STMT_WHILE: {
            if (lc->loop_depth >= 1024) {
                fprintf(stderr, "LLVM backend: loop nesting too deep (max 1024)\n");
                lc->failed = 1;
                return;
            }
            int cond_label = llc_new_label(lc);
            int body_label = llc_new_label(lc);
            int end_label = llc_new_label(lc);

            // Push loop labels for break/continue
            lc->loop_cond_labels[lc->loop_depth] = cond_label;
            lc->loop_end_labels[lc->loop_depth] = end_label;
            lc->loop_depth++;

            ll_line(lc, "br label %%L%d", cond_label);
            ll_emit(lc, "L%d:\n", cond_label);

            int cond_val = llvm_emit_expr(lc, stmt->as.while_stmt.condition);
            int bool_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", bool_reg, cond_val);
            int cmp_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp ne i32 %%%d, 0", cmp_reg, bool_reg);
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, body_label, end_label);

            ll_emit(lc, "L%d:\n", body_label);
            lc->block_terminated = 0;
            llvm_emit_stmt_list(lc, stmt->as.while_stmt.body);
            if (!lc->block_terminated) ll_line(lc, "br label %%L%d", cond_label);

            ll_emit(lc, "L%d:\n", end_label);
            lc->block_terminated = 0;
            lc->loop_depth--;
            break;
        }
        case STMT_BLOCK:
            llvm_emit_stmt_list(lc, stmt->as.block.statements);
            break;
        case STMT_RETURN: {
            if (lc->block_terminated) break;
            int r;
            if (stmt->as.ret.value != NULL) {
                r = llvm_emit_expr(lc, stmt->as.ret.value);
            } else {
                r = llc_new_reg(lc);
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            }
            if (lc->deferred_return_active) {
                ll_line(lc, "store i32 2, i32* %%%d", lc->deferred_mode_slot);
                ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", r, lc->deferred_return_slot);
                ll_line(lc, "br label %%L%d", lc->deferred_return_label);
            } else if (lc->current_try_callback != NULL) {
                ll_line(lc, "call void @sage_rt_try_return(%%SageValue %%%d) noreturn", r);
                ll_line(lc, "unreachable");
            } else if (lc->current_scope == lc->main_scope) {
                ll_line(lc, "ret i32 0");
            } else {
                ll_line(lc, "ret %%SageValue %%%d", r);
            }
            lc->block_terminated = 1;
            break;
        }
        case STMT_PROC: {
            LLVMScopeInfo* child = lc->current_scope != NULL
                ? lc->current_scope->first_child : NULL;
            while (child != NULL && child->declaration != stmt) child = child->next_sibling;
            if (child == NULL) break;
            char* name = token_to_str(stmt->as.proc.name);
            if (child->capture_count > 0) {
                int captures = llc_new_reg(lc);
                ll_line(lc, "%%%d = alloca %%SageValue, i32 %d", captures, child->capture_count);
                for (int i = 0; i < child->capture_count; i++) {
                    Expr capture;
                    memset(&capture, 0, sizeof(capture));
                    capture.type = EXPR_VARIABLE;
                    capture.as.variable.name.start = (char*)child->captures[i];
                    capture.as.variable.name.length = (int)strlen(child->captures[i]);
                    int value = llvm_emit_expr(lc, &capture);
                    int slot = llc_new_reg(lc);
                    ll_line(lc, "%%%d = getelementptr %%SageValue, %%SageValue* %%%d, i32 %d", slot, captures, i);
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", value, slot);
                }
                int function = llc_new_reg(lc);
                ll_line(lc, "%%%d = bitcast %%SageValue (...)* @%s to i8*", function, child->adapter_symbol);
                int closure = llc_new_reg(lc);
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_make_closure(i8* %%%d, i32 %d, %%SageValue* %%%d, i32 %d, i32 %d)",
                        closure, function, child->capture_count, captures,
                        child->proc->param_count, child->proc->required_count);
                ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", closure, name);
            } else {
                int function = llc_new_reg(lc);
                ll_line(lc, "%%%d = bitcast %%SageValue (...)* @%s to i8*", function, child->adapter_symbol);
                int closure = llc_new_reg(lc);
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_make_closure(i8* %%%d, i32 0, %%SageValue* null, i32 %d, i32 %d)",
                        closure, function, child->proc->param_count, child->proc->required_count);
                ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", closure, name);
            }
            free(name);
            break;
        }
        case STMT_FOR: {
            // for variable in iterable: body
            if (lc->loop_depth >= 1024) {
                fprintf(stderr, "LLVM backend: loop nesting too deep (max 1024)\n");
                lc->failed = 1;
                return;
            }
            // Emit iterable (must be array)
            int iter = llvm_emit_expr(lc, stmt->as.for_stmt.iterable);
            int len_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call i32 @sage_rt_array_len(%%SageValue %%%d)", len_reg, iter);

            // Loop variable (alloca already emitted by collect_local_names at function entry)
            char* var_name = token_to_str(stmt->as.for_stmt.variable);
            int idx_ptr = llc_new_reg(lc);
            ll_line(lc, "%%%d = alloca i32", idx_ptr);
            ll_line(lc, "store i32 0, i32* %%%d", idx_ptr);

            int cond_label = llc_new_label(lc);
            int body_label = llc_new_label(lc);
            int end_label = llc_new_label(lc);

            // Push loop labels for break/continue
            lc->loop_cond_labels[lc->loop_depth] = cond_label;
            lc->loop_end_labels[lc->loop_depth] = end_label;
            lc->loop_depth++;

            ll_line(lc, "br label %%L%d", cond_label);
            ll_emit(lc, "L%d:\n", cond_label);

            int cur_idx = llc_new_reg(lc);
            ll_line(lc, "%%%d = load i32, i32* %%%d", cur_idx, idx_ptr);
            int cmp = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp slt i32 %%%d, %%%d", cmp, cur_idx, len_reg);
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp, body_label, end_label);

            ll_emit(lc, "L%d:\n", body_label);

            // Get current element: arr[idx]
            // Convert i32 idx to SageValue number for indexing
            int idx_double = llc_new_reg(lc);
            ll_line(lc, "%%%d = sitofp i32 %%%d to double", idx_double, cur_idx);
            int idx_sage = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %%%d)", idx_sage, idx_double);
            int elem = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_index(%%SageValue %%%d, %%SageValue %%%d)", elem, iter, idx_sage);

            // Store element in loop variable
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", elem, var_name);

            lc->block_terminated = 0;
            llvm_emit_stmt_list(lc, stmt->as.for_stmt.body);

            if (!lc->block_terminated) {
                int next_idx = llc_new_reg(lc);
                ll_line(lc, "%%%d = add nsw i32 %%%d, 1", next_idx, cur_idx);
                ll_line(lc, "store i32 %%%d, i32* %%%d", next_idx, idx_ptr);
                ll_line(lc, "br label %%L%d", cond_label);
            }

            ll_emit(lc, "L%d:\n", end_label);

            lc->loop_depth--;
            free(var_name);
            break;
        }
        case STMT_BREAK: {
            if (lc->loop_depth > 0 && !lc->block_terminated) {
                ll_line(lc, "br label %%L%d", lc->loop_end_labels[lc->loop_depth - 1]);
                lc->block_terminated = 1;
                // Emit unreachable label for any following code
                int unr = llc_new_label(lc);
                ll_emit(lc, "L%d:\n", unr);
                lc->block_terminated = 0;
            }
            break;
        }
        case STMT_CONTINUE: {
            if (lc->loop_depth > 0 && !lc->block_terminated) {
                ll_line(lc, "br label %%L%d", lc->loop_cond_labels[lc->loop_depth - 1]);
                lc->block_terminated = 1;
                int unr = llc_new_label(lc);
                ll_emit(lc, "L%d:\n", unr);
                lc->block_terminated = 0;
            }
            break;
        }
        case STMT_CLASS:
            // Classes are collected and emitted at the top level
            break;
        case STMT_TRY: {
            if (lc->block_terminated) break;
            LLVMTryCallback* callback = llvm_prepare_try_callback(lc, stmt);
            int context = llc_new_reg(lc);
            ll_line(lc, "%%%d = call i8* @sage_rt_try_enter()", context);
            int capture_array = -1;
            if (callback->capture_count > 0) {
                capture_array = llc_new_reg(lc);
                ll_line(lc, "%%%d = alloca %%SageValue*, i32 %d", capture_array, callback->capture_count);
                for (int i = 0; i < callback->capture_count; i++) {
                    int slot = llc_new_reg(lc);
                    ll_line(lc, "%%%d = alloca %%SageValue*", slot);
                    ll_line(lc, "store %%SageValue* %%%s, %%SageValue** %%%d", callback->captures[i], slot);
                    int position = llc_new_reg(lc);
                    ll_line(lc, "%%%d = getelementptr %%SageValue*, %%SageValue** %%%d, i32 %d",
                            position, capture_array, i);
                    ll_line(lc, "store %%SageValue* %%%d, %%SageValue** %%%d", slot, position);
                }
            }
            int callback_function = llc_new_reg(lc);
            ll_line(lc, "%%%d = bitcast %%SageValue (%%SageValue**)* @%s to i8*",
                    callback_function, callback->symbol);
            int status = llc_new_reg(lc);
            if (capture_array >= 0) {
                ll_line(lc, "%%%d = call i32 @sage_rt_try_run(i8* %%%d, i8* %%%d, %%SageValue** %%%d)",
                        status, context, callback_function, capture_array);
            } else {
                ll_line(lc, "%%%d = call i32 @sage_rt_try_run(i8* %%%d, i8* %%%d, %%SageValue** null)",
                        status, context, callback_function);
            }
            int mode_slot = llc_new_reg(lc);
            ll_line(lc, "%%%d = alloca i32", mode_slot);
            ll_line(lc, "store i32 0, i32* %%%d", mode_slot);
            int return_slot = llc_new_reg(lc);
            ll_line(lc, "%%%d = alloca %%SageValue", return_slot);
            int return_nil = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", return_nil);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", return_nil, return_slot);
            int exception_slot = llc_new_reg(lc);
            ll_line(lc, "%%%d = alloca %%SageValue", exception_slot);
            int exception_nil = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", exception_nil);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", exception_nil, exception_slot);

            int is_exception = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp eq i32 %%%d, 1", is_exception, status);
            int is_return = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp eq i32 %%%d, 2", is_return, status);
            int catch_label = llc_new_label(lc);
            int return_test_label = llc_new_label(lc);
            int return_label = llc_new_label(lc);
            int normal_label = llc_new_label(lc);
            int cleanup_label = llc_new_label(lc);
            int dispatch_label = llc_new_label(lc);
            int merge_label = llc_new_label(lc);
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", is_exception, catch_label, return_test_label);
            ll_emit(lc, "L%d:\n", return_test_label);
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", is_return, return_label, normal_label);

            int previous_deferred_active = lc->deferred_return_active;
            int previous_deferred_label = lc->deferred_return_label;
            int previous_deferred_mode = lc->deferred_mode_slot;
            int previous_deferred_return = lc->deferred_return_slot;
            int previous_deferred_exception = lc->deferred_exception_slot;
            lc->deferred_return_active = 1;
            lc->deferred_return_label = cleanup_label;
            lc->deferred_mode_slot = mode_slot;
            lc->deferred_return_slot = return_slot;
            lc->deferred_exception_slot = exception_slot;

            ll_emit(lc, "L%d:\n", catch_label);
            lc->block_terminated = 0;
            int exception = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_exception_value()", exception);
            if (stmt->as.try_stmt.catch_count > 0) {
                ll_line(lc, "store i32 0, i32* %%%d", mode_slot);
            } else {
                ll_line(lc, "store i32 1, i32* %%%d", mode_slot);
            }
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", exception, exception_slot);
            ll_line(lc, "call void @sage_rt_try_leave(i8* %%%d)", context);
            if (stmt->as.try_stmt.catch_count > 0) {
                char* name = token_to_str(stmt->as.try_stmt.catches[0]->exception_var);
                if (llc_has_global(lc, name)) {
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* @%s", exception, name);
                } else {
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", exception, name);
                }
                free(name);
                llvm_emit_stmt_list(lc, stmt->as.try_stmt.catches[0]->body);
            }
            if (!lc->block_terminated) ll_line(lc, "br label %%L%d", cleanup_label);
            lc->block_terminated = 1;

            ll_emit(lc, "L%d:\n", return_label);
            lc->block_terminated = 0;
            int pending_return = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_try_return_value()", pending_return);
            ll_line(lc, "store i32 2, i32* %%%d", mode_slot);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", pending_return, return_slot);
            ll_line(lc, "call void @sage_rt_try_leave(i8* %%%d)", context);
            ll_line(lc, "br label %%L%d", cleanup_label);
            lc->block_terminated = 1;

            ll_emit(lc, "L%d:\n", normal_label);
            lc->block_terminated = 0;
            ll_line(lc, "call void @sage_rt_try_leave(i8* %%%d)", context);
            ll_line(lc, "br label %%L%d", cleanup_label);
            lc->block_terminated = 1;

            ll_emit(lc, "L%d:\n", cleanup_label);
            lc->deferred_return_label = dispatch_label;
            lc->block_terminated = 0;
            llvm_emit_stmt_list(lc, stmt->as.try_stmt.finally_block);
            if (!lc->block_terminated) ll_line(lc, "br label %%L%d", dispatch_label);
            lc->block_terminated = 1;

            lc->deferred_return_active = previous_deferred_active;
            lc->deferred_return_label = previous_deferred_label;
            lc->deferred_mode_slot = previous_deferred_mode;
            lc->deferred_return_slot = previous_deferred_return;
            lc->deferred_exception_slot = previous_deferred_exception;

            ll_emit(lc, "L%d:\n", dispatch_label);
            lc->block_terminated = 0;
            int pending_mode = llc_new_reg(lc);
            ll_line(lc, "%%%d = load i32, i32* %%%d", pending_mode, mode_slot);
            int pending_exception = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp eq i32 %%%d, 1", pending_exception, pending_mode);
            int pending_is_return = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp eq i32 %%%d, 2", pending_is_return, pending_mode);
            int exception_action = llc_new_label(lc);
            int return_check = llc_new_label(lc);
            int return_action = llc_new_label(lc);
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", pending_exception, exception_action, return_check);

            ll_emit(lc, "L%d:\n", exception_action);
            lc->block_terminated = 0;
            int pending_exception_value = llc_new_reg(lc);
            ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%d", pending_exception_value, exception_slot);
            if (previous_deferred_active) {
                ll_line(lc, "store i32 1, i32* %%%d", previous_deferred_mode);
                ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", pending_exception_value, previous_deferred_exception);
                ll_line(lc, "br label %%L%d", previous_deferred_label);
            } else {
                ll_line(lc, "call void @sage_rt_raise(%%SageValue %%%d) noreturn", pending_exception_value);
                ll_line(lc, "unreachable");
            }
            lc->block_terminated = 1;

            ll_emit(lc, "L%d:\n", return_check);
            lc->block_terminated = 0;
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", pending_is_return, return_action, merge_label);
            lc->block_terminated = 1;

            ll_emit(lc, "L%d:\n", return_action);
            lc->block_terminated = 0;
            int pending_return_value = llc_new_reg(lc);
            ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%d", pending_return_value, return_slot);
            if (previous_deferred_active) {
                ll_line(lc, "store i32 2, i32* %%%d", previous_deferred_mode);
                ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", pending_return_value, previous_deferred_return);
                ll_line(lc, "br label %%L%d", previous_deferred_label);
            } else if (lc->current_try_callback != NULL) {
                ll_line(lc, "call void @sage_rt_try_return(%%SageValue %%%d) noreturn", pending_return_value);
                ll_line(lc, "unreachable");
            } else if (lc->current_scope == lc->main_scope) {
                ll_line(lc, "ret i32 0");
            } else {
                ll_line(lc, "ret %%SageValue %%%d", pending_return_value);
            }
            lc->block_terminated = 1;

            ll_emit(lc, "L%d:\n", merge_label);
            lc->block_terminated = 0;
            break;
        }
        case STMT_RAISE: {
            int val;
            if (stmt->as.raise.exception != NULL) {
                val = llvm_emit_expr(lc, stmt->as.raise.exception);
            } else {
                val = llvm_emit_string_value(lc, "exception");
            }
            if (lc->deferred_return_active) {
                ll_line(lc, "store i32 1, i32* %%%d", lc->deferred_mode_slot);
                ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%d", val, lc->deferred_exception_slot);
                ll_line(lc, "br label %%L%d", lc->deferred_return_label);
            } else {
                ll_line(lc, "call void @sage_rt_raise(%%SageValue %%%d) noreturn", val);
                ll_line(lc, "unreachable");
            }
            lc->block_terminated = 1;
            break;
        }
        case STMT_IMPORT: {
            // Track imported modules for GPU/graphics support in compiled mode
            const char* mod_name = stmt->as.import.module_name;
            if (mod_name != NULL) {
                const char* binding = stmt->as.import.alias;
                if (binding == NULL && stmt->as.import.item_count == 0) {
                    const char* dot = strrchr(mod_name, '.');
                    binding = dot != NULL ? dot + 1 : mod_name;
                }
                if (binding != NULL) llc_add_module_binding(lc, mod_name, binding);
            }
            break;
        }
        case STMT_MATCH: {
            if (lc->block_terminated) break;
            int match_val = llvm_emit_expr(lc, stmt->as.match_stmt.value);
            int lbl_end = llc_new_label(lc);
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                CaseClause* clause = stmt->as.match_stmt.cases[i];
                int lbl_next = llc_new_label(lc);
                int lbl_then = llc_new_label(lc);
                int lbl_guard = clause->guard != NULL ? llc_new_label(lc) : -1;
                int wildcard = clause->pattern == NULL ||
                               (clause->pattern->type == EXPR_VARIABLE &&
                                clause->pattern->as.variable.name.length == 1 &&
                                clause->pattern->as.variable.name.start[0] == '_');
                int binding = !wildcard && clause->pattern->type == EXPR_VARIABLE;

                if (wildcard) {
                    if (lbl_guard >= 0) ll_line(lc, "br label %%L%d", lbl_guard);
                    else ll_line(lc, "br label %%L%d", lbl_then);
                } else if (binding) {
                    char* pattern_name = token_to_str(clause->pattern->as.variable.name);
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", match_val, pattern_name);
                    free(pattern_name);
                    if (lbl_guard >= 0) ll_line(lc, "br label %%L%d", lbl_guard);
                    else ll_line(lc, "br label %%L%d", lbl_then);
                } else {
                    int pat_reg = llvm_emit_expr(lc, clause->pattern);
                    int eq_reg = llc_new_reg(lc);
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_eq(%%SageValue %%%d, %%SageValue %%%d)",
                            eq_reg, match_val, pat_reg);
                    int bool_reg = llc_new_reg(lc);
                    ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", bool_reg, eq_reg);
                    int cmp_reg = llc_new_reg(lc);
                    ll_line(lc, "%%%d = icmp ne i32 %%%d, 0", cmp_reg, bool_reg);
                    if (lbl_guard >= 0) {
                        ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, lbl_guard, lbl_next);
                    } else {
                        ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, lbl_then, lbl_next);
                    }
                }

                if (lbl_guard >= 0) {
                    ll_emit(lc, "L%d:\n", lbl_guard);
                    int guard_val = llvm_emit_expr(lc, clause->guard);
                    int guard_bool = llc_new_reg(lc);
                    ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", guard_bool, guard_val);
                    int guard_cmp = llc_new_reg(lc);
                    ll_line(lc, "%%%d = icmp ne i32 %%%d, 0", guard_cmp, guard_bool);
                    ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", guard_cmp, lbl_then, lbl_next);
                }

                ll_emit(lc, "L%d:\n", lbl_then);
                lc->block_terminated = 0;
                llvm_emit_stmt_list(lc, clause->body);
                if (!lc->block_terminated) ll_line(lc, "br label %%L%d", lbl_end);
                ll_emit(lc, "L%d:\n", lbl_next);
                lc->block_terminated = 0;
            }
            if (stmt->as.match_stmt.default_case != NULL) {
                llvm_emit_stmt_list(lc, stmt->as.match_stmt.default_case);
            }
            if (!lc->block_terminated) ll_line(lc, "br label %%L%d", lbl_end);
            ll_emit(lc, "L%d:\n", lbl_end);
            lc->block_terminated = 0;
            break;
        }
        case STMT_DEFER:
            // In LLVM compiled code, emit defer body inline (best-effort)
            llvm_emit_stmt_list(lc, stmt->as.defer.statement);
            break;
        case STMT_YIELD:
        case STMT_ASYNC_PROC:
            fprintf(stderr, "LLVM backend: unsupported statement type %d (yield/async)\n", stmt->type);
            break;

        // Phase 17: comptime block — emit body as regular code (constant folding optimizes)
        case STMT_COMPTIME:
            llvm_emit_stmt_list(lc, stmt->as.comptime.body);
            break;

        case STMT_STRUCT:
            llvm_emit_struct_definition(lc, &stmt->as.struct_stmt);
            break;
        case STMT_ENUM:
            llvm_emit_enum_definition(lc, &stmt->as.enum_stmt);
            break;
        case STMT_TRAIT:
        case STMT_MACRO_DEF:
            break;
    }
}

// ============================================================================
// Local Variable Collection (pre-allocate all locals with alloca at entry)
// ============================================================================

static void collect_local_names(Stmt* stmt, char*** names, int* count, int* cap) {
    for (Stmt* s = stmt; s != NULL; s = s->next) {
        if (s->type == STMT_LET) {
            char* name = token_to_str(s->as.let.name);
            // Check for duplicates
            int dup = 0;
            for (int i = 0; i < *count; i++) {
                if (strcmp((*names)[i], name) == 0) { dup = 1; break; }
            }
            if (!dup) {
                if (*count >= *cap) {
                    *cap = *cap ? *cap * 2 : 16;
                    *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                }
                (*names)[(*count)++] = name;
            } else {
                free(name);
            }
        } else if (s->type == STMT_PROC || s->type == STMT_ASYNC_PROC) {
            Token token = s->type == STMT_PROC ? s->as.proc.name : s->as.async_proc.name;
            char* name = token_to_str(token);
            int dup = 0;
            for (int i = 0; i < *count; i++) {
                if (strcmp((*names)[i], name) == 0) { dup = 1; break; }
            }
            if (!dup) {
                if (*count >= *cap) {
                    *cap = *cap ? *cap * 2 : 16;
                    *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                }
                (*names)[(*count)++] = name;
            } else {
                free(name);
            }
        }
        // Recurse into sub-blocks
        if (s->type == STMT_IF) {
            collect_local_names(s->as.if_stmt.then_branch, names, count, cap);
            collect_local_names(s->as.if_stmt.else_branch, names, count, cap);
        } else if (s->type == STMT_WHILE) {
            collect_local_names(s->as.while_stmt.body, names, count, cap);
        } else if (s->type == STMT_FOR) {
            // For loop variable
            char* var = token_to_str(s->as.for_stmt.variable);
            int dup = 0;
            for (int i = 0; i < *count; i++) {
                if (strcmp((*names)[i], var) == 0) { dup = 1; break; }
            }
            if (!dup) {
                if (*count >= *cap) {
                    *cap = *cap ? *cap * 2 : 16;
                    *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                }
                (*names)[(*count)++] = var;
            } else {
                free(var);
            }
            collect_local_names(s->as.for_stmt.body, names, count, cap);
        } else if (s->type == STMT_BLOCK) {
            collect_local_names(s->as.block.statements, names, count, cap);
        } else if (s->type == STMT_TRY) {
            collect_local_names(s->as.try_stmt.try_block, names, count, cap);
            for (int i = 0; i < s->as.try_stmt.catch_count; i++) {
                char* name = token_to_str(s->as.try_stmt.catches[i]->exception_var);
                int dup = 0;
                for (int j = 0; j < *count; j++) {
                    if (strcmp((*names)[j], name) == 0) { dup = 1; break; }
                }
                if (!dup) {
                    if (*count >= *cap) {
                        *cap = *cap ? *cap * 2 : 16;
                        *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                    }
                    (*names)[(*count)++] = name;
                } else {
                    free(name);
                }
                collect_local_names(s->as.try_stmt.catches[i]->body, names, count, cap);
            }
            collect_local_names(s->as.try_stmt.finally_block, names, count, cap);
        } else if (s->type == STMT_COMPTIME) {
            collect_local_names(s->as.comptime.body, names, count, cap);
        } else if (s->type == STMT_MATCH) {
            for (int i = 0; i < s->as.match_stmt.case_count; i++) {
                CaseClause* clause = s->as.match_stmt.cases[i];
                if (clause->pattern != NULL && clause->pattern->type == EXPR_VARIABLE &&
                    !(clause->pattern->as.variable.name.length == 1 &&
                      clause->pattern->as.variable.name.start[0] == '_')) {
                    char* pattern_name = token_to_str(clause->pattern->as.variable.name);
                    int dup = 0;
                    for (int j = 0; j < *count; j++) {
                        if (strcmp((*names)[j], pattern_name) == 0) {
                            dup = 1;
                            break;
                        }
                    }
                    if (!dup) {
                        if (*count >= *cap) {
                            *cap = *cap ? *cap * 2 : 16;
                            *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                        }
                        (*names)[(*count)++] = pattern_name;
                    } else {
                        free(pattern_name);
                    }
                }
                collect_local_names(clause->body, names, count, cap);
            }
            collect_local_names(s->as.match_stmt.default_case, names, count, cap);
        } else if (s->type == STMT_STRUCT || s->type == STMT_ENUM) {
            Token type_token = s->type == STMT_STRUCT ? s->as.struct_stmt.name : s->as.enum_stmt.name;
            char* type_name = token_to_str(type_token);
            int dup = 0;
            for (int j = 0; j < *count; j++) {
                if (strcmp((*names)[j], type_name) == 0) {
                    dup = 1;
                    break;
                }
            }
            if (!dup) {
                if (*count >= *cap) {
                    *cap = *cap ? *cap * 2 : 16;
                    *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                }
                (*names)[(*count)++] = type_name;
            } else {
                free(type_name);
            }
        } else if (s->type == STMT_IMPORT) {
            // Import binding variable (e.g. import agent.critic -> "critic")
            const char* bind = s->as.import.alias;
            if (bind == NULL && s->as.import.item_count == 0 && s->as.import.module_name != NULL) {
                const char* dot = strrchr(s->as.import.module_name, '.');
                bind = dot ? dot + 1 : s->as.import.module_name;
            }
            if (bind != NULL) {
                char* var = SAGE_STRDUP(bind);
                int dup = 0;
                for (int i = 0; i < *count; i++) {
                    if (strcmp((*names)[i], var) == 0) { dup = 1; break; }
                }
                if (!dup) {
                    if (*count >= *cap) {
                        *cap = *cap ? *cap * 2 : 16;
                        *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                    }
                    (*names)[(*count)++] = var;
                } else {
                    free(var);
                }
            }
        }
    }
}

// ============================================================================
// Function Definition Emission
// ============================================================================

static void llvm_emit_function(LLVMCompiler* lc, Stmt* proc,
                               LLVMScopeInfo* scope, const char* symbol) {
    lc->block_terminated = 0;
    LLVMScopeInfo* previous_scope = lc->current_scope;
    lc->current_scope = scope;

    fprintf(lc->out, "define %%SageValue @%s(", symbol);
    int first = 1;
    if (scope != NULL && scope->is_nested) {
        fputs("%SageValue %arg_sage_closure_env", lc->out);
        first = 0;
    }
    for (int i = 0; i < proc->as.proc.param_count; i++) {
        if (!first) fputs(", ", lc->out);
        char* param = token_to_str(proc->as.proc.params[i]);
        fprintf(lc->out, "%%SageValue %%arg_%s", param);
        free(param);
        first = 0;
    }
    fputs(") {\n", lc->out);
    int entry_label = llc_new_label(lc);
    ll_emit(lc, "L%d:\n", entry_label);

    for (int i = 0; i < proc->as.proc.param_count; i++) {
        char* param = token_to_str(proc->as.proc.params[i]);
        ll_line(lc, "%%%s = alloca %%SageValue", param);
        ll_line(lc, "store %%SageValue %%arg_%s, %%SageValue* %%%s", param, param);
        free(param);
    }

    if (scope != NULL) {
        for (int i = 0; i < scope->capture_count; i++) {
            const char* name = scope->captures[i];
            ll_line(lc, "%%%s = alloca %%SageValue", name);
            int value = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_closure_get(%%SageValue %%arg_sage_closure_env, i32 %d)",
                    value, i);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", value, name);
        }
    }

    char** locals = NULL;
    int local_count = 0, local_cap = 0;
    collect_local_names(proc->as.proc.body, &locals, &local_count, &local_cap);
    for (int i = 0; i < local_count; i++) {
        int already_allocated = 0;
        for (int j = 0; j < proc->as.proc.param_count; j++) {
            char* param = token_to_str(proc->as.proc.params[j]);
            if (strcmp(param, locals[i]) == 0) already_allocated = 1;
            free(param);
            if (already_allocated) break;
        }
        if (!already_allocated && scope != NULL) {
            for (int j = 0; j < scope->capture_count; j++) {
                if (strcmp(scope->captures[j], locals[i]) == 0) {
                    already_allocated = 1;
                    break;
                }
            }
        }
        if (!already_allocated) ll_line(lc, "%%%s = alloca %%SageValue", locals[i]);
        free(locals[i]);
    }
    free(locals);

    llvm_emit_stmt_list(lc, proc->as.proc.body);

    if (!lc->block_terminated) {
        int nil_reg = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", nil_reg);
        ll_line(lc, "ret %%SageValue %%%d", nil_reg);
    }

    fputs("}\n\n", lc->out);
    lc->current_scope = previous_scope;
}

static void llvm_emit_nested_functions(LLVMCompiler* lc, LLVMScopeInfo* scope) {
    for (LLVMScopeInfo* child = scope->first_child; child != NULL; child = child->next_sibling) {
        lc->next_reg = 0;
        llvm_emit_function(lc, child->declaration, child, child->symbol);
        llvm_emit_call_adapter(lc, child);
        llvm_emit_nested_functions(lc, child);
    }
}

static int llvm_scope_stores_name(LLVMScopeInfo* scope, const char* name) {
    if (scope == NULL) return 0;
    if (llvm_name_set_has(&scope->bound_names, name)) return 1;
    for (int i = 0; i < scope->capture_count; i++) {
        if (strcmp(scope->captures[i], name) == 0) return 1;
    }
    return 0;
}

static LLVMTryCallback* llvm_prepare_try_callback(LLVMCompiler* lc, Stmt* statement) {
    if (lc->try_callback_count >= lc->try_callback_capacity) {
        lc->try_callback_capacity = lc->try_callback_capacity ? lc->try_callback_capacity * 2 : 8;
        lc->try_callbacks = SAGE_REALLOC(lc->try_callbacks,
            sizeof(LLVMTryCallback) * (size_t)lc->try_callback_capacity);
    }
    LLVMTryCallback* callback = &lc->try_callbacks[lc->try_callback_count++];
    memset(callback, 0, sizeof(*callback));
    callback->statement = statement;
    callback->owner = lc->current_scope;
    size_t size = 64;
    callback->symbol = SAGE_ALLOC(size);
    snprintf(callback->symbol, size, "sage_fn_try_%d", lc->next_try_id++);
    if (lc->current_class_name != NULL) callback->class_name = SAGE_STRDUP(lc->current_class_name);
    if (lc->parent_class_name != NULL) callback->parent_name = SAGE_STRDUP(lc->parent_class_name);

    LLVMNameSet referenced;
    memset(&referenced, 0, sizeof(referenced));
    llvm_collect_stmt_names(&referenced, statement->as.try_stmt.try_block);
    for (int i = 0; i < referenced.count; i++) {
        const char* name = referenced.items[i];
        if (callback->owner == lc->main_scope) continue;
        if (!llvm_scope_stores_name(callback->owner, name)) continue;
        int is_proc = 0;
        for (int j = 0; j < lc->proc_count; j++) {
            if (strcmp(lc->proc_names[j], name) == 0) {
                is_proc = 1;
                break;
            }
        }
        if (is_proc) continue;
        callback->captures = SAGE_REALLOC(callback->captures,
            sizeof(char*) * (size_t)(callback->capture_count + 1));
        callback->captures[callback->capture_count++] = SAGE_STRDUP(name);
    }
    llvm_name_set_free(&referenced);
    return callback;
}

static void llvm_emit_try_callback(LLVMCompiler* lc, LLVMTryCallback* callback) {
    lc->block_terminated = 0;
    lc->next_reg = 0;
    LLVMScopeInfo* previous_scope = lc->current_scope;
    LLVMTryCallback* previous_try_callback = lc->current_try_callback;
    int previous_deferred_active = lc->deferred_return_active;
    int previous_deferred_label = lc->deferred_return_label;
    int previous_deferred_mode = lc->deferred_mode_slot;
    int previous_deferred_return = lc->deferred_return_slot;
    int previous_deferred_exception = lc->deferred_exception_slot;
    char* previous_class = lc->current_class_name;
    char* previous_parent = lc->parent_class_name;
    lc->current_scope = callback->owner;
    lc->current_try_callback = callback;
    lc->deferred_return_active = 0;
    lc->deferred_return_label = 0;
    lc->deferred_mode_slot = 0;
    lc->deferred_return_slot = 0;
    lc->deferred_exception_slot = 0;
    lc->current_class_name = callback->class_name;
    lc->parent_class_name = callback->parent_name;

    fprintf(lc->out, "define %%SageValue @%s(%%SageValue** %%arg_try_context) {\n", callback->symbol);
    int entry = llc_new_label(lc);
    ll_emit(lc, "L%d:\n", entry);
    for (int i = 0; i < callback->capture_count; i++) {
        ll_line(lc, "%%%s = alloca %%SageValue*", callback->captures[i]);
        int slot = llc_new_reg(lc);
        ll_line(lc, "%%%d = getelementptr %%SageValue*, %%SageValue** %%arg_try_context, i32 %d", slot, i);
        int pointer = llc_new_reg(lc);
        ll_line(lc, "%%%d = load %%SageValue*, %%SageValue** %%%d", pointer, slot);
        ll_line(lc, "store %%SageValue* %%%d, %%SageValue** %%%s", pointer, callback->captures[i]);
    }

    char** locals = NULL;
    int local_count = 0;
    int local_cap = 0;
    collect_local_names(callback->statement->as.try_stmt.try_block,
                        &locals, &local_count, &local_cap);
    for (int i = 0; i < local_count; i++) {
        int captured = 0;
        for (int j = 0; j < callback->capture_count; j++) {
            if (strcmp(callback->captures[j], locals[i]) == 0) captured = 1;
        }
        if (!captured) ll_line(lc, "%%%s = alloca %%SageValue", locals[i]);
        free(locals[i]);
    }
    free(locals);

    llvm_emit_stmt_list(lc, callback->statement->as.try_stmt.try_block);
    if (!lc->block_terminated) {
        int nil = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", nil);
        ll_line(lc, "ret %%SageValue %%%d", nil);
    }
    fputs("}\n\n", lc->out);
    lc->current_scope = previous_scope;
    lc->current_try_callback = previous_try_callback;
    lc->deferred_return_active = previous_deferred_active;
    lc->deferred_return_label = previous_deferred_label;
    lc->deferred_mode_slot = previous_deferred_mode;
    lc->deferred_return_slot = previous_deferred_return;
    lc->deferred_exception_slot = previous_deferred_exception;
    lc->current_class_name = previous_class;
    lc->parent_class_name = previous_parent;
}

static void llvm_emit_try_callbacks(LLVMCompiler* lc) {
    for (int i = 0; i < lc->try_callback_count; i++) {
        llvm_emit_try_callback(lc, &lc->try_callbacks[i]);
    }
}

static int llvm_stmt_needs_unoptimized(Stmt* stmt);

static int llvm_expr_needs_unoptimized(const Expr* expr) {
    if (expr == NULL) return 0;
    switch (expr->type) {
        case EXPR_CALL:
            if (expr->as.call.kw_names != NULL) {
                for (int i = 0; i < expr->as.call.arg_count; i++) {
                    if (expr->as.call.kw_names[i] != NULL) return 1;
                }
            }
            if (llvm_expr_needs_unoptimized(expr->as.call.callee)) return 1;
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                if (llvm_expr_needs_unoptimized(expr->as.call.args[i])) return 1;
            }
            return 0;
        case EXPR_BINARY:
            return llvm_expr_needs_unoptimized(expr->as.binary.left) ||
                   llvm_expr_needs_unoptimized(expr->as.binary.right);
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                if (llvm_expr_needs_unoptimized(expr->as.array.elements[i])) return 1;
            }
            return 0;
        case EXPR_INDEX:
            return llvm_expr_needs_unoptimized(expr->as.index.array) ||
                   llvm_expr_needs_unoptimized(expr->as.index.index);
        case EXPR_INDEX_SET:
            return llvm_expr_needs_unoptimized(expr->as.index_set.array) ||
                   llvm_expr_needs_unoptimized(expr->as.index_set.index) ||
                   llvm_expr_needs_unoptimized(expr->as.index_set.value);
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                if (llvm_expr_needs_unoptimized(expr->as.dict.values[i])) return 1;
            }
            return 0;
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                if (llvm_expr_needs_unoptimized(expr->as.tuple.elements[i])) return 1;
            }
            return 0;
        case EXPR_SLICE:
            return llvm_expr_needs_unoptimized(expr->as.slice.array) ||
                   llvm_expr_needs_unoptimized(expr->as.slice.start) ||
                   llvm_expr_needs_unoptimized(expr->as.slice.end);
        case EXPR_GET:
            return llvm_expr_needs_unoptimized(expr->as.get.object);
        case EXPR_SET:
            return llvm_expr_needs_unoptimized(expr->as.set.object) ||
                   llvm_expr_needs_unoptimized(expr->as.set.value);
        case EXPR_AWAIT:
            return llvm_expr_needs_unoptimized(expr->as.await.expression);
        case EXPR_COMPTIME:
            return llvm_expr_needs_unoptimized(expr->as.comptime.expression);
        case EXPR_PROC:
            return llvm_stmt_needs_unoptimized(expr->as.proc_expr.body);
        default:
            return 0;
    }
}

static int llvm_stmt_needs_unoptimized(Stmt* stmt) {
    for (Stmt* s = stmt; s != NULL; s = s->next) {
        switch (s->type) {
            case STMT_PROC: {
                ProcStmt* proc = &s->as.proc;
                if (proc->defaults != NULL) {
                    for (int i = 0; i < proc->param_count; i++) {
                        if (proc->defaults[i] != NULL) return 1;
                    }
                }
                if (llvm_stmt_needs_unoptimized(proc->body)) return 1;
                break;
            }
            case STMT_ASYNC_PROC: {
                ProcStmt* proc = &s->as.async_proc;
                if (proc->defaults != NULL) {
                    for (int i = 0; i < proc->param_count; i++) {
                        if (proc->defaults[i] != NULL) return 1;
                    }
                }
                if (llvm_stmt_needs_unoptimized(proc->body)) return 1;
                break;
            }
            case STMT_STRUCT:
            case STMT_ENUM:
                return 1;
            case STMT_CLASS:
                if (llvm_stmt_needs_unoptimized(s->as.class_stmt.methods)) return 1;
                break;
            case STMT_LET:
                if (llvm_expr_needs_unoptimized(s->as.let.initializer)) return 1;
                break;
            case STMT_PRINT:
                if (llvm_expr_needs_unoptimized(s->as.print.expression)) return 1;
                break;
            case STMT_EXPRESSION:
                if (llvm_expr_needs_unoptimized(s->as.expression)) return 1;
                break;
            case STMT_IF:
                if (llvm_expr_needs_unoptimized(s->as.if_stmt.condition) ||
                    llvm_stmt_needs_unoptimized(s->as.if_stmt.then_branch) ||
                    llvm_stmt_needs_unoptimized(s->as.if_stmt.else_branch)) return 1;
                break;
            case STMT_BLOCK:
                if (llvm_stmt_needs_unoptimized(s->as.block.statements)) return 1;
                break;
            case STMT_WHILE:
                if (llvm_expr_needs_unoptimized(s->as.while_stmt.condition) ||
                    llvm_stmt_needs_unoptimized(s->as.while_stmt.body)) return 1;
                break;
            case STMT_FOR:
                if (llvm_expr_needs_unoptimized(s->as.for_stmt.iterable) ||
                    llvm_stmt_needs_unoptimized(s->as.for_stmt.body)) return 1;
                break;
            case STMT_RETURN:
                if (llvm_expr_needs_unoptimized(s->as.ret.value)) return 1;
                break;
            case STMT_MATCH:
                for (int i = 0; i < s->as.match_stmt.case_count; i++) {
                    CaseClause* clause = s->as.match_stmt.cases[i];
                    if (clause == NULL) continue;
                    if (clause->guard != NULL) return 1;
                    if (llvm_expr_needs_unoptimized(clause->pattern) ||
                        llvm_expr_needs_unoptimized(clause->guard) ||
                        llvm_stmt_needs_unoptimized(clause->body)) return 1;
                }
                if (llvm_stmt_needs_unoptimized(s->as.match_stmt.default_case)) return 1;
                break;
            case STMT_DEFER:
                if (llvm_stmt_needs_unoptimized(s->as.defer.statement)) return 1;
                break;
            case STMT_TRY:
                if (llvm_stmt_needs_unoptimized(s->as.try_stmt.try_block)) return 1;
                for (int i = 0; i < s->as.try_stmt.catch_count; i++) {
                    if (llvm_stmt_needs_unoptimized(s->as.try_stmt.catches[i]->body)) return 1;
                }
                if (llvm_stmt_needs_unoptimized(s->as.try_stmt.finally_block)) return 1;
                break;
            case STMT_RAISE:
                if (llvm_expr_needs_unoptimized(s->as.raise.exception)) return 1;
                break;
            case STMT_COMPTIME:
                if (llvm_stmt_needs_unoptimized(s->as.comptime.body)) return 1;
                break;
            case STMT_MACRO_DEF:
                if (llvm_stmt_needs_unoptimized(s->as.macro_def.body)) return 1;
                break;
            default:
                break;
        }
    }
    return 0;
}

// ============================================================================
// Main Compilation Function
// ============================================================================

static int write_llvm_output(const char* source, const char* input_path, const char* output_path,
                             int opt_level, int debug_info) {
    FILE* out = fopen(output_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "Could not open LLVM output \"%s\": %s\n", output_path, strerror(errno));
        return 0;
    }

    LLVMCompiler lc;
    memset(&lc, 0, sizeof(lc));
    lc.out = out;
    lc.input_path = input_path;
    lc.next_reg = 0;
    lc.next_label = 0;

    Stmt* source_program = parse_program(source);
    Stmt* program = source_program;
    llvm_collect_metadata(&lc, source_program);

    if (opt_level > 0 && lc.class_info_count == 0 && lc.next_nested_id == 0 &&
        !llvm_stmt_needs_unoptimized(source_program)) {
        PassContext pass_ctx;
        pass_ctx.opt_level = opt_level;
        pass_ctx.debug_info = debug_info;
        pass_ctx.verbose = 0;
        pass_ctx.input_path = input_path;
        program = run_passes(program, &pass_ctx);
    }

    // Collect symbols
    llvm_collect_imported_modules(&lc, program);
    llvm_collect_symbols(&lc, program);
    if (lc.failed) {
        fclose(out);
        free_stmt(program);
        if (program != source_program) free_stmt(source_program);
        llc_free(&lc);
        return 0;
    }

    // Emit type definitions and runtime declarations
    emit_type_definitions(&lc);

    // Emit string constants (first pass to collect, then we'll fix up)
    // We do a two-pass approach: first emit functions, capture strings, then prepend
    // For simplicity, emit strings after functions (LLVM allows forward refs)

    // Emit global variables
    for (int i = 0; i < lc.global_count; i++) {
        fprintf(out, "@%s = internal global %%SageValue zeroinitializer\n", lc.global_names[i]);
    }
    if (lc.global_count > 0) fputc('\n', out);

    // Emit function definitions
    for (int i = 0; i < lc.source_module_count; i++) {
        Stmt* module_ast = lc.source_modules[i].ast;
        for (Stmt* stmt = module_ast; stmt != NULL; stmt = stmt->next) {
            if (stmt->type != STMT_PROC) continue;
            LLVMScopeInfo* scope = llc_find_scope(&lc, stmt);
            if (scope == NULL) continue;
            lc.next_reg = 0;
            llvm_emit_function(&lc, stmt, scope, scope->symbol);
            llvm_emit_call_adapter(&lc, scope);
            llvm_emit_nested_functions(&lc, scope);
        }
    }
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            LLVMScopeInfo* scope = llc_find_scope(&lc, s);
            if (scope == NULL) continue;
            lc.next_reg = 0;
            llvm_emit_function(&lc, s, scope, scope->symbol);
            llvm_emit_call_adapter(&lc, scope);
            llvm_emit_nested_functions(&lc, scope);
        } else if (s->type == STMT_CLASS) {
            // Emit each class method as a standalone function
            char* cname = token_to_str(s->as.class_stmt.name);
            char* pname = s->as.class_stmt.has_parent ? token_to_str(s->as.class_stmt.parent) : NULL;
            lc.current_class_name = cname;
            lc.parent_class_name = pname;

            for (Stmt* m = s->as.class_stmt.methods; m != NULL; m = m->next) {
                if (m->type == STMT_PROC) {
                    LLVMScopeInfo* scope = llc_find_scope(&lc, m);
                    if (scope == NULL) continue;
                    lc.next_reg = 0;
                    llvm_emit_function(&lc, m, scope, scope->symbol);
                    llvm_emit_call_adapter(&lc, scope);
                    llvm_emit_nested_functions(&lc, scope);
                }
            }
            lc.current_class_name = NULL;
            lc.parent_class_name = NULL;
            free(cname);
            if (pname) free(pname);
        }
    }

    llvm_emit_nested_functions(&lc, lc.main_scope);

    // Emit main function
    lc.next_reg = 0;
    int main_entry_label = llc_new_label(&lc);
    fprintf(out, "define i32 @main() {\n");
    fprintf(out, "L%d:\n", main_entry_label);
    lc.current_scope = lc.main_scope;
    lc.block_terminated = 0;

    for (int i = 0; i < lc.class_info_count; i++) {
        LLVMClassInfo* info = &lc.class_infos[i];
        int name = llvm_emit_string_ptr(&lc, info->name);
        int parent = info->parent_name != NULL
            ? llvm_emit_string_ptr(&lc, info->parent_name) : 0;
        if (parent > 0) {
            ll_line(&lc, "call void @sage_rt_register_class(i8* %%%d, i8* %%%d)", name, parent);
        } else {
            ll_line(&lc, "call void @sage_rt_register_class(i8* %%%d, i8* null)", name);
        }
    }
    for (int i = 0; i < lc.class_info_count; i++) {
        LLVMClassInfo* info = &lc.class_infos[i];
        int class_name = llvm_emit_string_ptr(&lc, info->name);
        for (Stmt* m = info->declaration->methods; m != NULL; m = m->next) {
            if (m->type != STMT_PROC) continue;
            LLVMScopeInfo* scope = llc_find_scope(&lc, m);
            if (scope == NULL) continue;
            char* method_name = token_to_str(m->as.proc.name);
            int method = llvm_emit_string_ptr(&lc, method_name);
            int function = llc_new_reg(&lc);
            ll_line(&lc, "%%%d = bitcast %%SageValue (...)* @%s to i8*", function, scope->adapter_symbol);
            int required_count = m->as.proc.required_count;
            if (required_count < 0 || required_count > m->as.proc.param_count) {
                required_count = m->as.proc.param_count;
            }
            int has_self = m->as.proc.param_count > 0 &&
                m->as.proc.params[0].length == 4 &&
                strncmp(m->as.proc.params[0].start, "self", 4) == 0;
            ll_line(&lc, "call void @sage_rt_register_method(i8* %%%d, i8* %%%d, i8* %%%d, i32 %d, i32 %d, i32 %d)",
                    class_name, method, function, m->as.proc.param_count,
                    required_count, has_self);
            free(method_name);
        }
    }

    for (int i = 0; i < lc.source_module_count; i++) {
        lc.current_module_name = lc.source_modules[i].name;
        for (Stmt* stmt = lc.source_modules[i].ast; stmt != NULL; stmt = stmt->next) {
            if (stmt->type != STMT_LET) continue;
            char* member_name = token_to_str(stmt->as.let.name);
            LLVMImportedGlobal* global = llc_find_imported_global(
                &lc, lc.current_module_name, member_name);
            if (global != NULL && stmt->as.let.initializer != NULL) {
                int value = llvm_emit_expr(&lc, stmt->as.let.initializer);
                ll_line(&lc, "store %%SageValue %%%d, %%SageValue* @%s", value, global->global_name);
            }
            free(member_name);
        }
    }
    lc.current_module_name = NULL;

    // Pre-allocate all local variables used in main (for/let inside loops/blocks)
    {
        char** main_locals = NULL;
        int main_local_count = 0, main_local_cap = 0;
        // Collect locals from non-proc, non-class top-level statements
        for (Stmt* ms = program; ms != NULL; ms = ms->next) {
            if (ms->type != STMT_PROC && ms->type != STMT_CLASS) {
                // Wrap single stmt in a temporary chain for collect
                Stmt* saved_next = ms->next;
                ms->next = NULL;
                collect_local_names(ms, &main_locals, &main_local_count, &main_local_cap);
                ms->next = saved_next;
            }
        }
        for (int ml = 0; ml < main_local_count; ml++) {
            // Skip globals (they use @name, not %name)
            int is_global = 0;
            for (int gi = 0; gi < lc.global_count; gi++) {
                if (strcmp(lc.global_names[gi], main_locals[ml]) == 0) { is_global = 1; break; }
            }
            if (!is_global) {
                ll_line(&lc, "%%%s = alloca %%SageValue", main_locals[ml]);
            }
            free(main_locals[ml]);
        }
        free(main_locals);
    }

    // Emit top-level statements
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type != STMT_PROC && s->type != STMT_CLASS) {
            if (s->type == STMT_LET) {
                char* name = token_to_str(s->as.let.name);
                int val = llvm_emit_expr(&lc, s->as.let.initializer);
                ll_line(&lc, "store %%SageValue %%%d, %%SageValue* @%s", val, name);
                free(name);
            } else {
                llvm_emit_stmt(&lc, s);
            }
        }
    }

    ll_line(&lc, "ret i32 0");
    fprintf(out, "}\n\n");

    llvm_emit_try_callbacks(&lc);

    // Emit string constants
    for (int i = 0; i < lc.string_count; i++) {
        size_t slen = strlen(lc.strings[i]) + 1;
        fprintf(out, "@.str.%d = private unnamed_addr constant [%zu x i8] c\"", i, slen);
        emit_escaped_string(out, lc.strings[i]);
        fprintf(out, "\\00\"\n");
    }

    if (lc.failed) {
        fclose(out);
        free_stmt(program);
        if (program != source_program) free_stmt(source_program);
        llc_free(&lc);
        return 0;
    }

    fclose(out);
    free_stmt(program);
    if (program != source_program) free_stmt(source_program);
    llc_free(&lc);
    return 1;
}

// ============================================================================
// Public API
// ============================================================================

int compile_source_to_llvm_ir(const char* source, const char* input_path,
                              const char* output_path, int opt_level, int debug_info) {
    return write_llvm_output(source, input_path, output_path, opt_level, debug_info);
}

int compile_source_to_llvm_executable(const char* source, const char* input_path,
                                      const char* ll_output_path, const char* exe_output_path,
                                      int opt_level, int debug_info) {
    if (!write_llvm_output(source, input_path, ll_output_path, opt_level, debug_info)) {
        return 0;
    }

    // Use clang to compile the LLVM IR directly
    // clang can handle .ll files natively
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Could not fork for LLVM compilation.\n");
        return 0;
    }

    if (pid == 0) {
        char executable_dir[PATH_MAX] = "";
        ssize_t executable_len = readlink("/proc/self/exe", executable_dir, sizeof(executable_dir) - 1);
        if (executable_len > 0) {
            executable_dir[executable_len] = '\0';
            char *last_slash = strrchr(executable_dir, '/');
            if (last_slash != NULL) {
                *last_slash = '\0';
            }
        } else {
            executable_dir[0] = '\0';
        }

        char executable_runtime[PATH_MAX] = "";
        char executable_gpu[PATH_MAX] = "";
        char installed_runtime[PATH_MAX] = "";
        char installed_gpu[PATH_MAX] = "";
        if (executable_dir[0] != '\0') {
            snprintf(executable_runtime, sizeof(executable_runtime), "%s/obj/llvm_runtime.o", executable_dir);
            snprintf(executable_gpu, sizeof(executable_gpu), "%s/obj/gpu_api.o", executable_dir);
            snprintf(installed_runtime, sizeof(installed_runtime), "%s/../share/sage/obj/llvm_runtime.o", executable_dir);
            snprintf(installed_gpu, sizeof(installed_gpu), "%s/../share/sage/obj/gpu_api.o", executable_dir);
        }

        const char* rt_paths[] = { "obj/llvm_runtime.o", "./llvm_runtime.o", executable_runtime, installed_runtime, NULL };
        const char* rt_path = NULL;
        for (int i = 0; rt_paths[i] != NULL; i++) {
            if (rt_paths[i][0] != '\0' && access(rt_paths[i], F_OK) == 0) { rt_path = rt_paths[i]; break; }
        }

        const char* gpu_paths[] = { "obj/gpu_api.o", "./gpu_api.o", executable_gpu, installed_gpu, NULL };
        const char* gpu_path = NULL;
        for (int i = 0; gpu_paths[i] != NULL; i++) {
            if (gpu_paths[i][0] != '\0' && access(gpu_paths[i], F_OK) == 0) { gpu_path = gpu_paths[i]; break; }
        }

        // Build clang argument list dynamically based on available libraries
        const char* args[32];
        int argc = 0;
        args[argc++] = "clang";
        args[argc++] = "-O2";
        args[argc++] = ll_output_path;
        if (rt_path) args[argc++] = rt_path;
        if (gpu_path) args[argc++] = gpu_path;
        args[argc++] = "-o";
        args[argc++] = exe_output_path;
        args[argc++] = "-lm";
        args[argc++] = "-lpthread";
        // Link GPU libraries if gpu_api.o is available
        if (gpu_path) {
            // Vulkan
            #ifdef SAGE_HAS_VULKAN
            args[argc++] = "-lvulkan";
            #endif
            // GLFW
            #ifdef SAGE_HAS_GLFW
            args[argc++] = "-lglfw";
            #endif
            // OpenGL (always try — linker will skip if unused)
            args[argc++] = "-lGL";
            args[argc++] = "-ldl";
        }
        args[argc] = NULL;

        execvp("clang", (char* const*)args);
        // If clang not found, fall through
        fprintf(stderr, "Could not execute clang: %s\n", strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "Could not wait for clang.\n");
        return 0;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "LLVM compilation failed.\n");
        return 0;
    }

    return 1;
}
