# Exception Propagation Refactoring Guide

## Problem

Exceptions thrown inside functions don't propagate to caller's try/catch blocks because:
- `eval_expr()` returns `Value` not `ExecResult`
- When a function raises an exception, the `ExecResult.is_throwing` flag is lost
- The exception never reaches the outer try/catch

## Solution

Refactor `eval_expr()` to return `ExecResult` instead of `Value`.

## Changes Required

### 1. Function Signature

```c
// OLD:
static Value eval_expr(Expr* expr, Env* env);

// NEW:
static ExecResult eval_expr(Expr* expr, Env* env);
```

### 2. Return Statement Pattern

```c
// OLD:
return val_number(42);

// NEW:
return (ExecResult){ val_number(42), 0, 0, 0, 0, val_nil() };

// Helper macro for cleaner code:
#define EVAL_RESULT(v) ((ExecResult){ (v), 0, 0, 0, 0, val_nil() })

// Then use:
return EVAL_RESULT(val_number(42));
```

### 3. Call Sites - Extract Value

Every place that calls `eval_expr()` needs updating:

```c
// OLD:
Value v = eval_expr(expr, env);

// NEW:
ExecResult result = eval_expr(expr, env);
if (result.is_throwing) return result;  // Propagate exception
Value v = result.value;
```

### 4. Binary Operations

```c
static ExecResult eval_binary(BinaryExpr* b, Env* env) {
    ExecResult left_result = eval_expr(b->left, env);
    if (left_result.is_throwing) return left_result;
    Value left = left_result.value;

    // Short-circuit for OR
    if (b->op.type == TOKEN_OR) {
        if (is_truthy(left)) {
            return EVAL_RESULT(val_bool(1));
        }
        ExecResult right_result = eval_expr(b->right, env);
        if (right_result.is_throwing) return right_result;
        return EVAL_RESULT(val_bool(is_truthy(right_result.value)));
    }

    // Similar for AND
    if (b->op.type == TOKEN_AND) {
        if (!is_truthy(left)) {
            return EVAL_RESULT(val_bool(0));
        }
        ExecResult right_result = eval_expr(b->right, env);
        if (right_result.is_throwing) return right_result;
        return EVAL_RESULT(val_bool(is_truthy(right_result.value)));
    }

    ExecResult right_result = eval_expr(b->right, env);
    if (right_result.is_throwing) return right_result;
    Value right = right_result.value;

    // ... rest of operations ...
    return EVAL_RESULT(result_value);
}
```

### 5. Function Calls

```c
case EXPR_CALL: {
    // ...
    ProcStmt* func = find_function(callee.start, callee.length);
    if (func) {
        // Evaluate arguments
        for (int i = 0; i < func->param_count; i++) {
            ExecResult arg_result = eval_expr(expr->as.call.args[i], env);
            if (arg_result.is_throwing) return arg_result;  // NEW!
            Value argVal = arg_result.value;
            Token paramName = func->params[i];
            env_define(scope, paramName.start, paramName.length, argVal);
        }

        ExecResult res = interpret(func->body, scope);
        // NEW: Check for exceptions!
        if (res.is_throwing) return res;
        return EVAL_RESULT(res.value);
    }
}
```

### 6. Array Expressions

```c
case EXPR_ARRAY: {
    Value arr = val_array();
    for (int i = 0; i < expr->as.array.count; i++) {
        ExecResult elem_result = eval_expr(expr->as.array.elements[i], env);
        if (elem_result.is_throwing) return elem_result;  // NEW!
        array_push(&arr, elem_result.value);
    }
    return EVAL_RESULT(arr);
}
```

### 7. Statement Handlers Using eval_expr

```c
case STMT_PRINT: {
    ExecResult result = eval_expr(stmt->as.print.expression, env);
    if (result.is_throwing) return result;  // NEW!
    print_value(result.value);
    printf("\n");
    return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil() };
}

case STMT_LET: {
    Value val = val_nil();
    if (stmt->as.let.initializer != NULL) {
        ExecResult result = eval_expr(stmt->as.let.initializer, env);
        if (result.is_throwing) return result;  // NEW!
        val = result.value;
    }
    Token t = stmt->as.let.name;
    env_define(env, t.start, t.length, val);
    return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil() };
}
```

## Complete List of Changes

### In `eval_expr()` function:
1. Change return type from `Value` to `ExecResult`
2. Wrap all return values: `return val_X()` → `return EVAL_RESULT(val_X())`
3. For error cases returning `val_nil()`, return `EVAL_RESULT(val_nil())`

### In all callers of `eval_expr()`:
1. Change: `Value v = eval_expr(...)` to `ExecResult r = eval_expr(...)`
2. Add: `if (r.is_throwing) return r;` immediately after
3. Change variable uses: `v` → `r.value`

### Functions to update:
- `eval_binary()` - both left and right operand checks
- All cases in `eval_expr()` switch
- All cases in `interpret()` that call `eval_expr()`
- `is_truthy()` - keep as-is (takes Value)
- `print_value()` - keep as-is (takes Value)

## Testing

After refactoring:
```bash
make clean && make
./sage examples/exceptions.sage
```

Expected: All 7 examples pass including:
- Example 4: Exception in function properly caught
- Example 6: Validation function exceptions caught in loop

## Estimated Impact

- Lines changed: ~200
- Functions modified: ~15
- Test coverage: All exception examples should work
- Performance: Negligible (struct copy overhead minimal)

## Alternative: Quick Fix

If full refactor is too large, add global exception state:

```c
static int has_pending_exception = 0;
static Value pending_exception = {VAL_NIL};

// In function calls:
ExecResult res = interpret(func->body, scope);
if (res.is_throwing) {
    has_pending_exception = 1;
    pending_exception = res.exception_value;
    return val_nil();
}

// In interpret() after eval_expr():
if (has_pending_exception) {
    ExecResult exc_result = {val_nil(), 0, 0, 0, 1, pending_exception};
    has_pending_exception = 0;
    return exc_result;
}
```

This is hacky but works without full refactor.