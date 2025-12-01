// include/module.h
#ifndef SAGE_MODULE_H
#define SAGE_MODULE_H

#include "value.h"
#include "env.h"
#include <stdbool.h>

// Maximum path length for module files
#define MAX_MODULE_PATH 1024

// Module search paths
#define MAX_SEARCH_PATHS 16

// Module structure
typedef struct Module {
    char* name;              // Module name (e.g., "math", "io")
    char* path;              // Full file path to module
    Environment* env;        // Module's exported environment
    bool is_loaded;          // Whether module has been loaded
    bool is_loading;         // Circular dependency detection
    struct Module* next;     // For module cache linked list
} Module;

// Module cache - stores loaded modules
typedef struct {
    Module* modules;         // Linked list of loaded modules
    char** search_paths;     // Array of paths to search for modules
    int search_path_count;   // Number of search paths
} ModuleCache;

// Import statement types
typedef enum {
    IMPORT_ALL,              // import module
    IMPORT_FROM,             // from module import item1, item2
    IMPORT_AS                // import module as alias
} ImportType;

// Import item (for 'from module import x, y')
typedef struct {
    char* name;              // Original name in module
    char* alias;             // Optional alias (NULL if not aliased)
} ImportItem;

// Import statement data
typedef struct {
    ImportType type;
    char* module_name;       // Module to import from
    char* alias;             // For IMPORT_AS type
    ImportItem* items;       // For IMPORT_FROM type (NULL-terminated)
    int item_count;          // Number of items to import
} ImportData;

// Global module cache
extern ModuleCache* global_module_cache;

// Module cache management
ModuleCache* create_module_cache();
void destroy_module_cache(ModuleCache* cache);
void add_search_path(ModuleCache* cache, const char* path);

// Module loading and resolution
Module* load_module(ModuleCache* cache, const char* name);
Module* find_module(ModuleCache* cache, const char* name);
char* resolve_module_path(ModuleCache* cache, const char* name);

// Module execution
bool execute_module(Module* module, Environment* global_env);

// Import handling
bool import_module(Environment* env, ImportData* import_data);
bool import_all(Environment* env, const char* module_name);
bool import_from(Environment* env, const char* module_name, ImportItem* items, int count);
bool import_as(Environment* env, const char* module_name, const char* alias);

// Standard library modules
void register_stdlib_modules(ModuleCache* cache);
Module* create_math_module();
Module* create_io_module();
Module* create_string_module();

// Module initialization
void init_module_system();
void cleanup_module_system();

#endif
