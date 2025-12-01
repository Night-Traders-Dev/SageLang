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

// Helper macro for creating normal expression results
#define EVAL_RESULT(v) ((ExecResult){ (v), 0, 0, 0, 0, val_nil(), 0, NULL })
#define EVAL_EXCEPTION(exc) ((ExecResult){ val_nil(), 0, 0, 0, 1, (exc), 0, NULL })
#define RESULT_NORMAL(v) ((ExecResult){ (v), 0, 0, 0, 0, val_nil(), 0, NULL })

// [Rest of the interpreter code stays the same until the switch statement in interpret()]
// I'll add the STMT_IMPORT case right before STMT_MATCH

        // PHASE 8: Import statement (stub for now)
        case STMT_IMPORT: {
            // TODO: Implement import statement execution
            // For now, just print a message that imports are not yet supported
            fprintf(stderr, "Note: Import statements not yet fully implemented.\n");
            fprintf(stderr, "      Module requested: %s\n", stmt->as.import.module_name);
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_MATCH:
        case STMT_DEFER:
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
