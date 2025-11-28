// ... (File is too large to show complete, showing key changes)

// Add at top after includes:
static int has_exception = 0;
static Value current_exception = { VAL_NIL };

static void set_exception(Value exc) {
    has_exception = 1;
    current_exception = exc;
}

static void clear_exception() {
    has_exception = 0;
    current_exception = val_nil();
}

// In EXPR_CALL case, after: ExecResult res = interpret(func->body, scope);
// Add:
if (res.is_throwing) {
    set_exception(res.exception_value);
    return val_nil();
}

// In every interpret() statement handler, after each statement:
// Check: if (has_exception) return (ExecResult){ val_nil(), 0, 0, 0, 1, current_exception };

// This is a quick architectural fix. Full solution would refactor eval_expr
// to return ExecResult instead of Value.