/*
 * sage-lsp: Standalone LSP server entry point.
 *
 * This is a thin wrapper so that editors can invoke "sage-lsp" directly.
 * Equivalent to running "sage --lsp".
 */

#include <setjmp.h>
#include "lsp.h"

/* These globals are normally defined in main.c for the interpreter/REPL.
 * The standalone LSP binary needs them because the parser and interpreter
 * reference them (via repl.h's sage_error_exit). */
int g_repl_mode = 0;
jmp_buf g_repl_error_jmp;

int main(void) {
    lsp_run();
    return 0;
}
