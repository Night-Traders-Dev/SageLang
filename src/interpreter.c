#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "interpreter.h"
#include "token.h"
#include "env.h"
#include "value.h"
#include "gc.h"
#include "ast.h"
#include "module.h"  // Phase 8: Module system

// External module cache from module.c
extern ModuleCache* global_module_cache;

// Rest of interpreter code stays the same until STMT_IMPORT case...
// [I'll only show the changed part for brevity]

// PHASE 8: Import statement execution
case STMT_IMPORT: {
    // Initialize module system if not already initialized
    if (!global_module_cache) {
        init_module_system();
    }
    
    char* module_name = stmt->as.import.module_name;
    char** items = stmt->as.import.items;
    int item_count = stmt->as.import.item_count;
    char* alias = stmt->as.import.alias;
    int import_all = stmt->as.import.import_all;
    
    // Handle different import types
    if (import_all && !alias) {
        // import module_name (no alias)
        if (!import_all(env, module_name)) {
            fprintf(stderr, "Error: Failed to import module '%s'\n", module_name);
            return (ExecResult){ val_nil(), 0, 0, 0, 1, val_exception("Import error"), 0, NULL };
        }
    } else if (import_all && alias) {
        // import module_name as alias
        if (!import_as(env, module_name, alias)) {
            fprintf(stderr, "Error: Failed to import module '%s' as '%s'\n", module_name, alias);
            return (ExecResult){ val_nil(), 0, 0, 0, 1, val_exception("Import error"), 0, NULL };
        }
    } else {
        // from module_name import item1, item2, ...
        ImportItem* import_items = malloc(sizeof(ImportItem) * item_count);
        for (int i = 0; i < item_count; i++) {
            import_items[i].name = items[i];
            import_items[i].alias = NULL;  // TODO: support 'from X import Y as Z'
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
