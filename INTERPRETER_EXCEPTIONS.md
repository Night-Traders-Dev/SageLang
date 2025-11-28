# Interpreter Exception Integration

Add these cases to the `interpret()` function in `src/interpreter.c`:

## STMT_RAISE Case

Add this after `STMT_RETURN` case:

```c
case STMT_RAISE: {
    // Evaluate exception expression
    Value exc_val = eval_expr(stmt->as.raise.exception, env);
    
    // Convert to exception if it's a string
    if (IS_STRING(exc_val)) {
        exc_val = val_exception(AS_STRING(exc_val));
    } else if (!IS_EXCEPTION(exc_val)) {
        // Convert other types to string then exception
        char msg[256];
        if (IS_NUMBER(exc_val)) {
            snprintf(msg, sizeof(msg), "Error: %g", AS_NUMBER(exc_val));
        } else {
            snprintf(msg, sizeof(msg), "Unknown error");
        }
        exc_val = val_exception(msg);
    }
    
    // Return with is_throwing flag
    return (ExecResult){ val_nil(), 0, 0, 0, 1, exc_val };
}
```

## STMT_TRY Case

Add this after `STMT_RAISE` case:

```c
case STMT_TRY: {
    // Execute try block
    ExecResult try_result = interpret(stmt->as.try_stmt.try_block, env);
    
    // If exception thrown, try to catch it
    if (try_result.is_throwing) {
        // Try each catch handler
        for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
            CatchClause* catch_clause = stmt->as.try_stmt.catches[i];
            
            // Create scope with exception variable
            Env* catch_env = env_create(env);
            Token var = catch_clause->exception_var;
            env_define(catch_env, var.start, var.length, try_result.exception_value);
            
            // Execute catch handler
            ExecResult catch_result = interpret(catch_clause->body, catch_env);
            
            // If catch handled it (no throw), clear exception
            if (!catch_result.is_throwing) {
                try_result = catch_result;
                break;
            }
            
            // If catch also threw, propagate that exception
            try_result = catch_result;
        }
    }
    
    // Always execute finally block
    if (stmt->as.try_stmt.finally_block != NULL) {
        interpret(stmt->as.try_stmt.finally_block, env);
    }
    
    // Return result (may still be throwing if not caught)
    return try_result;
}
```

## Update STMT_BLOCK Case

Replace the existing STMT_BLOCK case with this to add exception propagation:

```c
case STMT_BLOCK: {
    Stmt* current = stmt->as.block.statements;
    while (current != NULL) {
        ExecResult res = interpret(current, env);
        
        // Propagate exceptions, returns, breaks, continues
        if (res.is_returning || res.is_breaking || 
            res.is_continuing || res.is_throwing) {
            return res;
        }
        
        current = current->next;
    }
    return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil() };
}
```

## Initialize ExecResult Properly

Make sure all ExecResult returns include the exception fields:

```c
// For normal returns (no exception):
return (ExecResult){ value, 0, 0, 0, 0, val_nil() };

// For exceptions:
return (ExecResult){ val_nil(), 0, 0, 0, 1, exception_value };
```

## Testing

After adding these cases:

```bash
make clean && make
./sage examples/exceptions.sage
```

Expected output:
- All 7 examples run successfully
- Exceptions caught and handled
- Finally blocks execute
- Error messages displayed correctly
