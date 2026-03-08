// src/module.c
#include "module.h"
#include "lexer.h"
#include "parser.h"
#include "ast.h"
#include "interpreter.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Global module cache
ModuleCache* global_module_cache = NULL;

// Create a new module cache
ModuleCache* create_module_cache() {
    ModuleCache* cache = malloc(sizeof(ModuleCache));
    cache->modules = NULL;
    cache->search_paths = malloc(sizeof(char*) * MAX_SEARCH_PATHS);
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
    
    cache->search_paths[cache->search_path_count] = strdup(path);
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

// Resolve module path by searching in search paths
char* resolve_module_path(ModuleCache* cache, const char* name) {
    char path[MAX_MODULE_PATH];
    
    // Try each search path
    for (int i = 0; i < cache->search_path_count; i++) {
        // Try .sage extension
        snprintf(path, MAX_MODULE_PATH, "%s/%s.sage", cache->search_paths[i], name);
        if (file_exists(path)) {
            return strdup(path);
        }
        
        // Try without extension (for directories with __init__.sage)
        snprintf(path, MAX_MODULE_PATH, "%s/%s/__init__.sage", cache->search_paths[i], name);
        if (file_exists(path)) {
            return strdup(path);
        }
    }
    
    return NULL;
}

// Find a module in the cache
Module* find_module(ModuleCache* cache, const char* name) {
    Module* current = cache->modules;
    while (current) {
        if (strcmp(current->name, name) == 0) {
            return current;
        }
        current = current->next;
    }
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
    fseek(file, 0, SEEK_SET);
    
    char* buffer = malloc(length + 1);
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
        init_lexer(module->source);
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
    module = malloc(sizeof(Module));
    module->name = strdup(name);
    module->path = path;
    module->source = NULL;
    module->ast = NULL;
    module->ast_tail = NULL;
    module->env = NULL;
    module->is_loaded = false;
    module->is_loading = false;
    module->next = cache->modules;
    
    // Add to cache
    cache->modules = module;
    
    return module;
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
    
    // Define module in current environment (with name length)
    env_define(env, module_name, strlen(module_name), val_module(module));
    
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

// Initialize the module system
void init_module_system() {
    if (!global_module_cache) {
        global_module_cache = create_module_cache();
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

// Register standard library modules (stub for now)
void register_stdlib_modules(ModuleCache* cache) {
    (void)cache;  // Suppress unused parameter warning
}

// Create math module (stub)
Module* create_math_module() {
    return NULL;
}

// Create io module (stub)
Module* create_io_module() {
    return NULL;
}

// Create string module (stub)
Module* create_string_module() {
    return NULL;
}
