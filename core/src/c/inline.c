#include "pass.h"

Stmt* pass_inline(Stmt* program, PassContext* ctx) {
    (void)ctx;
    return program;
}
