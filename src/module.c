// src/module.c
#include "module.h"
#include "lexer.h"
#include "ast.h"
#include "interpreter.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// Forward declaration for parse function from parser.c
extern Stmt* parse();
extern void parser_init();

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
        free(current->name);
        free(current->path);
        if (current->env) {
            // Environment will be cleaned up by GC
        }
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

// Check if a file exists
static bool file_exists(const char* path) {
    struct stat buffer;
    return (stat(path, &buffer) == 0);
}

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

// Execute a module and populate its environment
bool execute_module(Module* module, Environment* global_env) {
    if (module->is_loaded) {
        return true;  // Already loaded
    }
    
    if (module->is_loading) {
        fprintf(stderr, "Error: Circular dependency detected for module '%s'\n", module->name);
        return false;
    }
    
    module->is_loading = true;
    
    // Read module source code
    char* source = read_file(module->path);
    if (!source) {
        module->is_loading = false;
        return false;
    }
    
    // Create module environment (child of global)
    module->env = env_create(global_env);
    
    // Lex and parse the module
    init_lexer(source);
    parser_init();
    Stmt* ast = parse();
    
    if (!ast) {
        fprintf(stderr, "Error: Failed to parse module '%s'\n", module->name);
        free(source);
        module->is_loading = false;
        return false;
    }
    
    // Execute the module in its own environment
    ExecResult result = execute(ast, module->env);
    
    free(source);
    module->is_loading = false;
    
    if (result.is_throwing) {
        fprintf(stderr, "Error: Exception in module '%s': ", module->name);
        if (result.value.type == VAL_EXCEPTION) {
            fprintf(stderr, "%s\n", result.value.as.exception->message);
        } else {
            fprintf(stderr, "Unknown error\n");
        }
        return false;
    }
    
    module->is_loaded = true;
    return true;
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
    if (!execute_module(module, env)) {
        return false;
    }
    
    // Import all exported values from module into current environment
    // For now, we'll create a namespace object that holds the module's environment
    // This allows: import math; math.sqrt(16)
    
    // Create a module value (we'll need to add VAL_MODULE type)
    Value module_val;
    module_val.type = VAL_STRING;  // Temporary - will be VAL_MODULE
    module_val.as.string = strdup(module_name);
    
    // Define module in current environment
    env_define(env, module_name, module_val);
    
    return true;
}

// Import specific items: from math import sqrt, cos
bool import_from(Environment* env, const char* module_name, ImportItem* items, int count) {
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
    if (!execute_module(module, env)) {
        return false;
    }
    
    // Import each specified item
    for (int i = 0; i < count; i++) {
        const char* item_name = items[i].name;
        const char* alias = items[i].alias ? items[i].alias : item_name;
        
        // Look up the item in the module's environment
        Value* value = env_get(module->env, item_name);
        if (!value) {
            fprintf(stderr, "Error: Module '%s' has no attribute '%s'\n", 
                    module_name, item_name);
            return false;
        }
        
        // Define in current environment (with alias if provided)
        env_define(env, alias, *value);
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
    if (!execute_module(module, env)) {
        return false;
    }
    
    // Create module value
    Value module_val;
    module_val.type = VAL_STRING;  // Temporary - will be VAL_MODULE
    module_val.as.string = strdup(module_name);
    
    // Define with alias
    env_define(env, alias, module_val);
    
    return true;
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
        // Register standard library modules
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
    // TODO: Register built-in modules like math, io, string
    // These will be implemented as native C modules
    (void)cache;  // Suppress unused parameter warning
}

// Create math module (stub)
Module* create_math_module() {
    // TODO: Implement native math module
    return NULL;
}

// Create io module (stub)
Module* create_io_module() {
    // TODO: Implement native I/O module
    return NULL;
}

// Create string module (stub)
Module* create_string_module() {
    // TODO: Implement native string utilities module
    return NULL;
}
