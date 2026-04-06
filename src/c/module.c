// src/module.c
#define _DEFAULT_SOURCE
#include "module.h"
#include "lexer.h"
#include "parser.h"
#include "ast.h"
#include "interpreter.h"
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>
#include "gc.h"
#include "sage_thread.h"

// Global module cache (mutex-protected for thread safety)
ModuleCache* global_module_cache = NULL;
static sage_mutex_t module_mutex = SAGE_MUTEX_INITIALIZER;

// Create a new module cache
ModuleCache* create_module_cache() {
    ModuleCache* cache = SAGE_ALLOC(sizeof(ModuleCache));
    cache->modules = NULL;
    cache->search_paths = SAGE_ALLOC(sizeof(char*) * MAX_SEARCH_PATHS);
    cache->search_path_count = 0;
    
    // Add default search paths
    add_search_path(cache, ".");           // Current directory
    add_search_path(cache, "./lib");       // Local lib directory
    add_search_path(cache, "./modules");   // Local modules directory
    
    return cache;
}

// Destroy module cache and free all resources
void destroy_module_cache(ModuleCache* cache) {
    if (!cache) return;
    
    // Free all modules
    Module* current = cache->modules;
    while (current) {
        Module* next = current->next;
        free_stmt(current->ast);
        free(current->name);
        free(current->path);
        free(current->source);
        free(current);
        current = next;
    }
    
    // Free search paths
    for (int i = 0; i < cache->search_path_count; i++) {
        free(cache->search_paths[i]);
    }
    free(cache->search_paths);
    free(cache);
}

// Add a search path to the module cache
void add_search_path(ModuleCache* cache, const char* path) {
    if (cache->search_path_count >= MAX_SEARCH_PATHS) {
        fprintf(stderr, "Error: Maximum search paths exceeded\n");
        return;
    }
    
    cache->search_paths[cache->search_path_count] = SAGE_STRDUP(path);
    cache->search_path_count++;
}

#ifdef PICO_BUILD
static bool file_exists(const char* path) {
    (void)path;  // Unused parameter
    return false;  // No filesystem on Pico
}
#else
#include <sys/stat.h>
static bool file_exists(const char* path) {
    struct stat buffer;
    return (stat(path, &buffer) == 0);
}
#endif

// Validate module name: only allow alphanumeric, underscore, and single dots (no path separators)
static bool is_valid_module_name(const char* name) {
    if (name == NULL || name[0] == '\0') return false;
    for (const char* p = name; *p != '\0'; p++) {
        char c = *p;
        if (c == '/' || c == '\\') return false;  // No path separators
        if (c == '.' && *(p + 1) == '.') return false;  // No ".." sequences
    }
    return true;
}

#ifndef PICO_BUILD
#include <limits.h>
// Verify resolved path is within the search directory (prevent path traversal)
static bool path_is_within(const char* resolved, const char* search_dir) {
    char real_search[PATH_MAX];
    char real_resolved[PATH_MAX];

    if (realpath(search_dir, real_search) == NULL) return false;
    if (realpath(resolved, real_resolved) == NULL) return false;

    size_t search_len = strlen(real_search);
    return strncmp(real_resolved, real_search, search_len) == 0 &&
           (real_resolved[search_len] == '/' || real_resolved[search_len] == '\0');
}
#endif

// Convert dotted module name to path form (dots become slashes)
static char* module_name_to_path(const char* name) {
    size_t len = strlen(name);
    char* path_name = SAGE_ALLOC(len + 1);
    for (size_t i = 0; i < len; i++) {
        path_name[i] = (name[i] == '.') ? '/' : name[i];
    }
    path_name[len] = '\0';
    return path_name;
}

// Resolve module path by searching in search paths
char* resolve_module_path(ModuleCache* cache, const char* name) {
    // Reject module names with path traversal attempts
    if (!is_valid_module_name(name)) {
        fprintf(stderr, "Error: Invalid module name '%s' (path traversal not allowed)\n", name);
        return NULL;
    }

    // Convert dots to slashes for filesystem lookup
    char* path_name = module_name_to_path(name);
    char path[MAX_MODULE_PATH];

    // Try each search path
    for (int i = 0; i < cache->search_path_count; i++) {
        // Try .sage extension
        int written = snprintf(path, MAX_MODULE_PATH, "%s/%s.sage", cache->search_paths[i], path_name);
        if (written >= MAX_MODULE_PATH) {
            fprintf(stderr, "Error: Module path too long for '%s'\n", name);
            continue;
        }
        if (file_exists(path)) {
#ifndef PICO_BUILD
            if (!path_is_within(path, cache->search_paths[i])) {
                fprintf(stderr, "Error: Module '%s' resolves outside search directory\n", name);
                continue;
            }
#endif
            free(path_name);
            return SAGE_STRDUP(path);
        }

        // Try without extension (for directories with __init__.sage)
        written = snprintf(path, MAX_MODULE_PATH, "%s/%s/__init__.sage", cache->search_paths[i], path_name);
        if (written >= MAX_MODULE_PATH) continue;
        if (file_exists(path)) {
#ifndef PICO_BUILD
            if (!path_is_within(path, cache->search_paths[i])) {
                fprintf(stderr, "Error: Module '%s' resolves outside search directory\n", name);
                continue;
            }
#endif
            free(path_name);
            return SAGE_STRDUP(path);
        }
    }

    free(path_name);
    return NULL;
}

// Find a module in the cache (thread-safe)
Module* find_module(ModuleCache* cache, const char* name) {
    sage_mutex_lock(&module_mutex);
    Module* current = cache->modules;
    while (current) {
        if (strcmp(current->name, name) == 0) {
            sage_mutex_unlock(&module_mutex);
            return current;
        }
        current = current->next;
    }
    sage_mutex_unlock(&module_mutex);
    return NULL;
}

// Read file contents
static char* read_file(const char* path) {
    FILE* file = fopen(path, "rb");
    if (!file) {
        fprintf(stderr, "Error: Could not open file '%s'\n", path);
        return NULL;
    }
    
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    if (length < 0) {
        fclose(file);
        return NULL;
    }
    fseek(file, 0, SEEK_SET);
    
    char* buffer = SAGE_ALLOC(length + 1);
    if (!buffer) {
        fclose(file);
        return NULL;
    }
    
    size_t bytes_read = fread(buffer, 1, length, file);
    buffer[bytes_read] = '\0';
    
    fclose(file);
    return buffer;
}

static Environment* module_parent_env(Environment* target_env) {
    if (g_global_env != NULL) {
        return g_global_env;
    }
    return target_env;
}

// Execute a module and populate its environment
bool execute_module(Module* module, Environment* global_env) {
    LexerState saved_lexer = lexer_get_state();
    ParserState saved_parser = parser_get_state();
    bool ok = true;

    if (module->is_loaded) {
        return true;  // Already loaded
    }
    
    if (module->is_loading) {
        fprintf(stderr, "Error: Circular dependency detected for module '%s'\n", module->name);
        return false;
    }
    
    module->is_loading = true;
    
    if (module->source == NULL) {
        module->source = read_file(module->path);
    }
    if (!module->source) {
        module->is_loading = false;
        return false;
    }
    
    if (module->env == NULL) {
        // Modules see the shared global scope and stdlib, not the caller's local scope.
        module->env = env_create(module_parent_env(global_env));
    }

    if (module->ast == NULL) {
        // Parse the module once and retain the AST for exported function/method lifetimes.
        init_lexer(module->source, module->path);
        parser_init();

        while (1) {
            Stmt* ast = parse();
            if (ast == NULL) {
                break;
            }

            if (module->ast == NULL) {
                module->ast = ast;
            } else {
                module->ast_tail->next = ast;
            }
            module->ast_tail = ast;
        }
    }

    for (Stmt* current = module->ast; current != NULL; current = current->next) {
        ExecResult result = interpret(current, module->env);
        if (result.is_throwing) {
            fprintf(stderr, "Error: Exception in module '%s': ", module->name);
            if (result.exception_value.type == VAL_EXCEPTION) {
                fprintf(stderr, "%s\n", result.exception_value.as.exception->message);
            } else {
                fprintf(stderr, "Unknown error\n");
            }
            ok = false;
            break;
        }
    }

    module->is_loading = false;
    if (ok) {
        module->is_loaded = true;
    }

    parser_set_state(saved_parser);
    lexer_set_state(saved_lexer);
    return ok;
}

// Load a module (create if not in cache)
Module* load_module(ModuleCache* cache, const char* name) {
    // Check if module is already in cache
    Module* module = find_module(cache, name);
    if (module) {
        return module;
    }
    
    // Resolve module path
    char* path = resolve_module_path(cache, name);
    if (!path) {
        fprintf(stderr, "Error: Could not find module '%s'\n", name);
        return NULL;
    }
    
    // Create new module
    module = SAGE_ALLOC(sizeof(Module));
    module->name = SAGE_STRDUP(name);
    module->path = path;
    module->source = NULL;
    module->ast = NULL;
    module->ast_tail = NULL;
    module->env = NULL;
    module->is_loaded = false;
    module->is_loading = false;
    // Add to cache (thread-safe)
    sage_mutex_lock(&module_mutex);
    module->next = cache->modules;
    cache->modules = module;
    sage_mutex_unlock(&module_mutex);

    return module;
}

// Get the last component of a dotted module name (e.g., "graphics.vulkan" -> "vulkan")
static const char* module_binding_name(const char* module_name) {
    const char* last_dot = strrchr(module_name, '.');
    return last_dot ? last_dot + 1 : module_name;
}

// Import entire module: import math
bool import_all(Environment* env, const char* module_name) {
    if (!global_module_cache) {
        fprintf(stderr, "Error: Module system not initialized\n");
        return false;
    }

    // Load the module
    Module* module = load_module(global_module_cache, module_name);
    if (!module) {
        return false;
    }

    // Execute module if not already loaded
    if (!execute_module(module, module_parent_env(env))) {
        return false;
    }

    // Bind using the last component of the dotted name (e.g., graphics.vulkan -> vulkan)
    const char* bind_name = module_binding_name(module_name);
    env_define(env, bind_name, strlen(bind_name), val_module(module));

    return true;
}

bool import_wildcard(Environment* env, const char* module_name) {
    if (!global_module_cache) {
        fprintf(stderr, "Error: Module system not initialized\n");
        return false;
    }

    Module* module = load_module(global_module_cache, module_name);
    if (!module) return false;

    if (!execute_module(module, module_parent_env(env))) return false;

    // Dump all names from the module's environment into the caller's scope
    if (module->env) {
        EnvNode* node = module->env->head;
        while (node != NULL) {
            env_define(env, node->name, strlen(node->name), node->value);
            node = node->next;
        }
    }

    return true;
}

bool import_from(Environment* env, const char* module_name, ImportItem* items, int count) {
    if (!global_module_cache) {
        fprintf(stderr, "Error: Module system not initialized\n");
        return false;
    }

    Module* module = load_module(global_module_cache, module_name);
    if (!module) return false;

    if (!execute_module(module, module_parent_env(env))) return false;

    for (int i = 0; i < count; i++) {
        const char* item_name = items[i].name;
        const char* bind_name = items[i].alias ? items[i].alias : item_name;  // ✅ NEW
        
        Value value;
        if (!env_get(module->env, item_name, strlen(item_name), &value)) {
            fprintf(stderr, "Error: Module '%s' has no attribute '%s'\n",
            module_name, item_name);
            return false;
        }

        env_define(env, bind_name, strlen(bind_name), value);  // ✅ FIX: Use alias or original
    }

    return true;
}


// Import with alias: import math as m
bool import_as(Environment* env, const char* module_name, const char* alias) {
    if (!global_module_cache) {
        fprintf(stderr, "Error: Module system not initialized\n");
        return false;
    }
    
    // Load the module
    Module* module = load_module(global_module_cache, module_name);
    if (!module) {
        return false;
    }
    
    // Execute module if not already loaded
    if (!execute_module(module, module_parent_env(env))) {
        return false;
    }
    
    // Define with alias (with name length)
    env_define(env, alias, strlen(alias), val_module(module));
    
    return true;
}

Value module_get_attr(Module* module, const char* name, int length, int* found) {
    Value value = val_nil();

    if (module == NULL || module->env == NULL) {
        if (found) *found = 0;
        return value;
    }

    if (env_get(module->env, name, length, &value)) {
        if (found) *found = 1;
        return value;
    }

    if (found) *found = 0;
    return value;
}

// Main import function that handles all import types
bool import_module(Environment* env, ImportData* import_data) {
    switch (import_data->type) {
        case IMPORT_ALL:
            return import_all(env, import_data->module_name);
            
        case IMPORT_FROM:
            return import_from(env, import_data->module_name, 
                             import_data->items, import_data->item_count);
            
        case IMPORT_AS:
            return import_as(env, import_data->module_name, import_data->alias);
            
        default:
            fprintf(stderr, "Error: Unknown import type\n");
            return false;
    }
}

// Add the install-prefix library path and SAGE_PATH env var
static void add_system_search_paths(ModuleCache* cache) {
    // 1. Installed library path (compile-time default)
#ifndef SAGE_LIB_DIR
#define SAGE_LIB_DIR "/usr/local/share/sage/lib"
#endif
    add_search_path(cache, SAGE_LIB_DIR);

    // 2. SAGE_PATH environment variable (colon-separated list of directories)
    const char* sage_path = getenv("SAGE_PATH");
    if (sage_path != NULL && sage_path[0] != '\0') {
        char buf[4096];
        size_t len = strlen(sage_path);
        if (len >= sizeof(buf)) len = sizeof(buf) - 1;
        memcpy(buf, sage_path, len);
        buf[len] = '\0';
        char* start = buf;
        for (char* p = buf; ; p++) {
            if (*p == ':' || *p == '\0') {
                char end_ch = *p;
                *p = '\0';
                if (p > start) {
                    add_search_path(cache, start);
                }
                if (end_ch == '\0') break;
                start = p + 1;
            }
        }
    }

    // 3. Executable's own directory + /../share/sage/lib (for relocatable installs)
#ifdef __linux__
    {
        char exe_path[4096];
        ssize_t n = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
        if (n > 0) {
            exe_path[n] = '\0';
            char* slash = strrchr(exe_path, '/');
            if (slash) {
                *slash = '\0';
                char rel_lib[4096];
                snprintf(rel_lib, sizeof(rel_lib), "%s/../share/sage/lib", exe_path);
                add_search_path(cache, rel_lib);
                // Also add exe_dir/lib for portable installs
                snprintf(rel_lib, sizeof(rel_lib), "%s/lib", exe_path);
                add_search_path(cache, rel_lib);
            }
        }
    }
#endif
}

// Add source file's directory as a search path
void module_add_source_dir(const char* source_path) {
    if (global_module_cache == NULL || source_path == NULL) return;
    char dir[4096];
    size_t len = strlen(source_path);
    if (len >= sizeof(dir)) return;
    memcpy(dir, source_path, len + 1);
    char* last_slash = strrchr(dir, '/');
    if (last_slash != NULL) {
        *(last_slash + 1) = '\0';
        add_search_path(global_module_cache, dir);
        // Also add dir/lib/ for project-relative libs
        char lib_dir[4096];
        snprintf(lib_dir, sizeof(lib_dir), "%slib", dir);
        add_search_path(global_module_cache, lib_dir);
    }
}

// Initialize the module system
void init_module_system() {
    if (!global_module_cache) {
        global_module_cache = create_module_cache();
        add_system_search_paths(global_module_cache);
        register_stdlib_modules(global_module_cache);
    }
}

// Cleanup the module system
void cleanup_module_system() {
    if (global_module_cache) {
        destroy_module_cache(global_module_cache);
        global_module_cache = NULL;
    }
}

// Register standard library modules (implemented in stdlib.c)
void register_stdlib_modules(ModuleCache* cache) {
    create_math_module(cache);
    create_io_module(cache);
    create_string_module(cache);
    create_sys_module(cache);
    create_thread_module(cache);
    create_fat_module(cache);
    create_socket_module(cache);
    create_tcp_module(cache);
    create_http_module(cache);
    create_ssl_module(cache);
    create_graphics_module(cache);
    create_ml_native_module(cache);
}
