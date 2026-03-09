#ifndef SAGE_REPL_H
#define SAGE_REPL_H

#include <setjmp.h>

// REPL error recovery: when g_repl_mode is set, errors longjmp back
// to the REPL loop instead of calling exit(1).
extern int g_repl_mode;
extern jmp_buf g_repl_error_jmp;

// Call this instead of exit(1) in parser/interpreter error paths.
// In REPL mode it longjmps back; otherwise it exits.
static inline void sage_error_exit(void) {
    if (g_repl_mode) {
        longjmp(g_repl_error_jmp, 1);
    }
    exit(1);
}

#endif
