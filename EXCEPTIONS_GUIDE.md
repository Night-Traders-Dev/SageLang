# Exception Handling Implementation Guide

## Overview

This document provides complete implementation details for SageLang's exception handling system.

## Architecture

### AST Structures ✅ COMPLETE

```c
typedef struct {
    Token exception_var;   // Variable to bind exception to (e.g., 'e')
    Stmt* body;            // Code to execute if exception caught
} CatchClause;

typedef struct {
    Stmt* try_block;       // Code to try
    CatchClause** catches; // Array of catch handlers  
    int catch_count;
    Stmt* finally_block;   // Optional finally block (always executes)
} TryStmt;

typedef struct {
    Expr* exception;       // Exception value to raise
} RaiseStmt;
```

### Value System ✅ COMPLETE

```c
typedef struct {
    char* message;  // Error message
} ExceptionValue;

// VAL_EXCEPTION added to ValueType enum
// val_exception(const char* message) constructor
// print_value() updated
```

### ExecResult ✅ COMPLETE

```c
typedef struct {
    Value value;
    int is_returning;
    int is_breaking;
    int is_continuing;
    int is_throwing;        // NEW: Exception being thrown
    Value exception_value;  // NEW: The exception
} ExecResult;
```

## Parser Implementation 🚧 TODO

### Add to statement() function:

```c
static Stmt* statement() {
    // ... existing statements ...
    if (match(TOKEN_TRY)) return try_statement();
    if (match(TOKEN_RAISE)) return raise_statement();
    // ... rest ...
}
```

### try_statement() implementation:

```c
static Stmt* try_statement() {
    // try:
    consume(TOKEN_COLON, "Expect ':' after 'try'.");
    consume(TOKEN_NEWLINE, "Expect newline after try.");
    Stmt* try_block = block();
    
    // Parse catch clauses
    CatchClause** catches = NULL;
    int catch_count = 0;
    int catch_capacity = 0;
    
    while (match(TOKEN_CATCH)) {
        // catch e:
        consume(TOKEN_IDENTIFIER, "Expect exception variable after 'catch'.");
        Token exception_var = previous_token;
        
        consume(TOKEN_COLON, "Expect ':' after catch variable.");
        consume(TOKEN_NEWLINE, "Expect newline after catch clause.");
        Stmt* catch_body = block();
        
        CatchClause* clause = new_catch_clause(exception_var, catch_body);
        
        if (catch_count >= catch_capacity) {
            catch_capacity = catch_capacity == 0 ? 2 : catch_capacity * 2;
            catches = realloc(catches, sizeof(CatchClause*) * catch_capacity);
        }
        catches[catch_count++] = clause;
    }
    
    // Optional finally:
    Stmt* finally_block = NULL;
    if (match(TOKEN_FINALLY)) {
        consume(TOKEN_COLON, "Expect ':' after 'finally'.");
        consume(TOKEN_NEWLINE, "Expect newline after finally.");
        finally_block = block();
    }
    
    return new_try_stmt(try_block, catches, catch_count, finally_block);
}
```

### raise_statement() implementation:

```c
static Stmt* raise_statement() {
    // raise expression
    Expr* exception = expression();
    return new_raise_stmt(exception);
}
```

## Interpreter Implementation 🚧 TODO

### STMT_RAISE case:

```c
case STMT_RAISE: {
    // Evaluate exception expression
    Value exc_val = eval_expr(stmt->as.raise.exception, env);
    
    // Convert to exception if it's a string
    if (IS_STRING(exc_val)) {
        exc_val = val_exception(AS_STRING(exc_val));
    } else if (!IS_EXCEPTION(exc_val)) {
        exc_val = val_exception("Unknown error");
    }
    
    // Return with is_throwing flag
    return (ExecResult){ val_nil(), 0, 0, 0, 1, exc_val };
}
```

### STMT_TRY case:

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

### Exception Propagation:

After each statement execution in blocks, check for exceptions:

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

## Testing

Run the examples:

```bash
./sage examples/exceptions.sage
```

Expected output shows:
- Basic exception catching
- Finally block execution
- Exception propagation
- Nested try/catch
- Resource cleanup patterns

## Status

- ✅ AST structures
- ✅ Value system
- ✅ ExecResult extension
- ✅ Examples
- 🚧 Parser (60% - needs integration)
- 🚧 Interpreter (70% - needs STMT_TRY/STMT_RAISE)
- ⏳ Testing

## Next Steps

1. Add try_statement() and raise_statement() to parser.c
2. Add STMT_TRY and STMT_RAISE cases to interpret() in interpreter.c
3. Update exception propagation in STMT_BLOCK
4. Test with examples/exceptions.sage
5. Update PR to ready for review
